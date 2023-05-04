defmodule Store.Sqlite do
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts], location: :keep do
      @base opts[:base]
      @table opts[:table]
      @mod opts[:mod]
      @stmts opts[:stmt]
      @create opts[:create]
      @keys opts[:keys] || 1
      @cache opts[:cache] || false
      @max_cache_size opts[:cache_size] || 1_000_000
      require Logger
      alias Exqlite.Sqlite3
      alias Ippan.Utils
      use GenServer

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, hibernate_after: 5_000, name: @base)
      end

      @impl true
      def init(path) when is_binary(path) do
        {:ok, conn} = open(path)

        :ok = create(conn)

        statements =
          for {name, sql} <- @stmts, into: %{} do
            {:ok, statement} = Sqlite3.prepare(conn, sql)
            {name, statement}
          end

        begin(conn)

        if @cache do
          {:ok, %{conn: conn, stmt: statements, ets: :ets.new(@base, [:set])}}
        else
          {:ok, %{conn: conn, stmt: statements}}
        end
      end

      def init(conn) when is_reference(conn) do
        :ok = create(conn)

        statements =
          for {name, sql} <- @stmts, into: %{} do
            {:ok, statement} = Sqlite3.prepare(conn, sql)
            {name, statement}
          end

        begin(conn)

        if @cache do
          {:ok, %{conn: conn, stmt: statements, ets: :ets.new(@base, [:set])}}
        else
          {:ok, %{conn: conn, stmt: statements}}
        end
      end

      @spec open(binary()) :: {:ok, reference()}
      def open(path) do
        path
        |> Path.dirname()
        |> File.mkdir_p()

        {:ok, conn} = Sqlite3.open(path)
        Sqlite3.execute(conn, "PRAGMA journal_mode = OFF")
        Sqlite3.execute(conn, "PRAGMA synchronous = OFF")
        Sqlite3.execute(conn, "PRAGMA cache_size = -1000000")
        # Sqlite3.execute(conn, "PRAGMA locking_mode = EXCLUSIVE")
        Sqlite3.execute(conn, "PRAGMA temp_store = memory")
        Sqlite3.execute(conn, "PRAGMA case_sensitive_like = ON")
        {:ok, conn}
      end

      @spec open_readonly(binary()) :: {:ok, term()}
      def open_readonly(path) do
        flags = [:sqlite_open_readonly, :sqlite_open_uri]

        result = {:ok, conn} = Sqlite3.open(path, flags)
        Sqlite3.execute(conn, "PRAGMA case_sensitive_like=ON")
        result
      end

      def open_memory do
        result = {:ok, conn} = Sqlite3.open(":memory:")
        Sqlite3.execute(conn, "PRAGMA cache_size = -1000000")
        Sqlite3.execute(conn, "PRAGMA temp_store = memory")
        Sqlite3.execute(conn, "PRAGMA case_sensitive_like = ON")
        result
      end

      def get_state, do: :sys.get_state(@base)

      def begin do
        call(@base, :begin)
      end

      def commit do
        call(@base, :commit)
      end

      def begin(conn) do
        Sqlite3.execute(conn, "BEGIN")
      end

      def commit(conn) do
        Sqlite3.execute(conn, "COMMIT")
      end

      def create(conn) do
        for sql <- List.wrap(@create) do
          Sqlite3.execute(conn, sql)
        end
      end

      def insert(params) do
        call(@base, {:insert, params})
      end

      def upsert(params) do
        call(@base, {:upsert, params})
      end

      def replace(params) do
        call(@base, {:replace, params})
      end

      def lookup(key) do
        call(@base, {:lookup, key})
      end

      def exists?(key) do
        call(@base, {:exists, key})
      end

      def owner?(key, owner) do
        call(@base, {:owner, key, owner})
      end

      def all do
        call(@base, :all)
      end

      @spec update(map | Keyword.t(), map | Keyword.t()) ::
              non_neg_integer() | {:error, term()}
      def update(map_set_fields, map_where) do
        {fields, values} = Utils.rows_to_columns(map_set_fields)
        {w_fields, w_values} = Utils.rows_to_columns(map_where)

        set_fields =
          for key <- fields do
            "#{key}=?"
          end
          |> Enum.join(" ")

        where =
          for key <- w_fields do
            "#{key}=?"
          end
          |> Enum.join(" AND ")

        call(@base, {:update, set_fields, where, values ++ w_values})
      end

      @spec delete(binary | list) :: non_neg_integer() | {:error, term()}
      def delete(key) do
        call(@base, {:delete, key})
      end

      def delete_all do
        call(@base, :delete_all)
      end

      def drop do
        call(@base, :drop)
      end

      def execute_prepare(stmt_name, params) do
        call(@base, {:execute_prepare, stmt_name, params})
      end

      def execute(sql) do
        call(@base, {:execute, sql})
      end

      def launch(fun) do
        call(@base, {:call, fun})
      end

      @impl true
      if @cache do
        def handle_call(
              {:insert, params},
              _from,
              %{conn: conn, ets: ets, stmt: stmt} = state
            ) do
          statement = Map.get(stmt, :insert)
          Sqlite3.bind(conn, statement, params)
          result = Sqlite3.step(conn, statement)

          :ets.delete(ets, params_to_ets(params))
          {:reply, result, state}
        end

        def handle_call(
              {:lookup, params},
              _from,
              %{conn: conn, stmt: stmt, ets: ets} = state
            ) do
          ret =
            case :ets.lookup(ets, params_to_ets(params)) do
              [{_key, value}] ->
                {:ok, value}

              [] ->
                statement = Map.get(stmt, :lookup)
                Sqlite3.bind(conn, statement, params)
                result = Sqlite3.fetch_all(conn, statement)

                case result do
                  {:ok, data} = result ->
                    if :ets.info(ets, :size) > @max_cache_size do
                      :ets.delete_all_objects(ets)
                    end

                    :ets.insert(ets, List.to_tuple(data))
                    result

                  error ->
                    error
                end
            end

          {:reply, ret, state}
        end

        def handle_call(
              {:exists, id},
              _from,
              %{conn: conn, ets: ets, stmt: stmt} = state
            ) do
          case :ets.member(ets, id) do
            false ->
              statement = Map.get(stmt, :exists)
              Sqlite3.bind(conn, statement, [id])
              result = {:row, [1]} == Sqlite3.step(conn, statement)
              {:reply, result, state}

            true ->
              {:reply, true, state}
          end
        end

        def handle_call(
              {:owner, id, owner},
              _from,
              %{conn: conn, ets: ets, stmt: stmt} = state
            ) do
          case :ets.lookup(ets, id) do
            [] ->
              statement = Map.get(stmt, :owner)
              Sqlite3.bind(conn, statement, [id, owner])
              result = {:row, [1]} == Sqlite3.step(conn, statement)
              {:reply, result, state}

            [{_, value}] ->
              map = call(@mod, :to_map, [value])
              {:reply, map.owner == owner, state}
          end
        end

        def handle_call(
              {:delete, params},
              _from,
              %{conn: conn, ets: ets, stmt: stmt} = state
            ) do
          statement = Map.get(stmt, :delete)
          Sqlite3.bind(conn, statement, List.wrap(params))

          case Sqlite3.step(conn, statement) do
            :done ->
              n = changes(conn)
              :ets.delete(ets, params_to_ets(params))
              {:reply, n, state}

            _ ->
              {:reply, 0, state}
          end
        end

        def handle_call(:delete_all, _from, %{conn: conn, ets: ets} = state) do
          result = Sqlite3.execute(conn, "DELETE FROM #{@table}")
          :ets.delete_all_objects(ets)
          n = changes(conn)
          Sqlite3.execute(conn, "VACUUM")
          {:reply, n, state}
        end
      else
        def handle_call({:insert, params}, _from, %{conn: conn, stmt: stmt} = state) do
          statement = Map.get(stmt, :insert)
          Sqlite3.bind(conn, statement, params)
          result = Sqlite3.step(conn, statement)
          {:reply, result, state}
        end

        def handle_call({:upsert, params}, _from, %{conn: conn, stmt: stmt} = state) do
          statement = Map.get(stmt, :upsert)
          Sqlite3.bind(conn, statement, params)
          result = Sqlite3.step(conn, statement)
          {:reply, result, state}
        end

        def handle_call({:replace, params}, _from, %{conn: conn, stmt: stmt} = state) do
          statement = Map.get(stmt, :replace)
          Sqlite3.bind(conn, statement, params)
          result = Sqlite3.step(conn, statement)
          {:reply, result, state}
        end

        def handle_call({:lookup, params}, _from, %{conn: conn, stmt: stmt} = state) do
          statement = Map.get(stmt, :lookup)
          Sqlite3.bind(conn, statement, params)
          result = Sqlite3.fetch_all(conn, statement)
          {:reply, result, state}
        end

        def handle_call({:exists, id}, _from, %{conn: conn, stmt: stmt} = state) do
          statement = Map.get(stmt, :exists)
          Sqlite3.bind(conn, statement, [id])
          result = {:row, [1]} == Sqlite3.step(conn, statement)
          {:reply, result, state}
        end

        def handle_call({:owner, id, owner}, _from, %{conn: conn, stmt: stmt} = state) do
          statement = Map.get(stmt, :owner)
          Sqlite3.bind(conn, statement, [id, owner])
          result = {:row, [1]} == Sqlite3.step(conn, statement)
          {:reply, result, state}
        end

        def handle_call({:delete, params}, _from, %{conn: conn, stmt: stmt} = state) do
          statement = Map.get(stmt, :delete)
          Sqlite3.bind(conn, statement, List.wrap(params))

          case Sqlite3.step(conn, statement) do
            :done ->
              n = changes(conn)
              {:reply, n, state}

            _ ->
              {:reply, 0, state}
          end
        end

        def handle_call(:delete_all, _from, %{conn: conn} = state) do
          result = Sqlite3.execute(conn, "DELETE FROM #{@table}")
          n = changes(conn)
          Sqlite3.execute(conn, "VACUUM")
          {:reply, n, state}
        end
      end

      def handle_call({:call, fun}, _from, state) do
        try do
          fun.(state)
        rescue
          _ex ->
            {:reply, :error, state}
        end
      end

      def handle_call(
            {:update, set_fields, where, values_list},
            _from,
            %{conn: conn} = state
          ) do
        {:ok, statement} =
          Sqlite3.prepare(conn, "UPDATE #{@table} SET #{set_fields} WHERE #{where}")

        Sqlite3.bind(conn, statement, values_list)

        case Sqlite3.step(conn, statement) do
          :done ->
            changes(conn)

            case Map.get(state, :ets) do
              nil -> :ok
              ets -> :ets.delete(ets, params_to_ets(values_list))
            end

          _ ->
            Sqlite3.release(conn, statement)
            {:reply, 0, state}
        end
      end

      def handle_call(:all, _from, %{conn: conn, stmt: stmt} = state) do
        {:ok, statement} = Sqlite3.prepare(conn, "SELECT * FROM #{@table}")
        result = Sqlite3.fetch_all(conn, statement)
        Sqlite3.release(conn, statement)
        {:reply, result, state}
      end

      def handle_call(
            {:execute_prepare, stmt_name, params},
            _from,
            %{conn: conn, stmt: stmt} = state
          ) do
        statement = Map.get(stmt, stmt_name)
        Sqlite3.bind(conn, statement, params)
        result = Sqlite3.fetch_all(conn, statement)
        {:reply, result, state}
      end

      def handle_call({:execute, sql}, _from, %{conn: conn} = state) do
        result = Sqlite3.execute(conn, sql)
        {:reply, result, state}
      end

      def handle_call(:begin, _from, %{conn: conn} = state) do
        Sqlite3.execute(conn, "BEGIN")
        {:reply, :ok, state}
      end

      def handle_call(:commit, _from, %{conn: conn} = state) do
        Sqlite3.execute(conn, "COMMIT")
        {:reply, :ok, state}
      end

      def handle_call(:create, _from, %{conn: conn} = state) do
        for sql <- List.wrap(@create) do
          Sqlite3.execute(conn, sql)
        end

        {:reply, :ok, state}
      end

      def handle_call(:drop, _from, %{conn: conn} = state) do
        result = Sqlite3.execute(conn, "DROP TABLE #{@table}")
        Sqlite3.execute(conn, "VACUUM")
        {:reply, result, state}
      end

      def sync(conn) do
        Logger.debug("Sync #{@table}")
        commit(conn)
        Sqlite3.execute(conn, "PRAGMA wal_checkpoint(TRUNCATE)")
        begin(conn)
      end

      @impl true
      def terminate(_reason, %{conn: conn, ets: ets} = state) do
        sync(conn)
        Sqlite3.execute(conn, "VACUUM")
        Sqlite3.execute(conn, "PRAGMA optimize")
        Sqlite3.close(conn)
        :ets.delete(ets)
      end

      def terminate(_reason, %{conn: conn} = state) do
        sync(conn)
        Sqlite3.execute(conn, "VACUUM")
        Sqlite3.execute(conn, "PRAGMA optimize")
        Sqlite3.close(conn)
      end

      defp call(pid, msg, timeout \\ :infinity) do
        GenServer.call(pid, msg, timeout)
      end

      defp changes(conn) do
        {:ok, n} = Sqlite3.changes(conn)
        n
      end

      defp params_to_ets([key]), do: key
      defp params_to_ets(params) when is_list(params), do: Enum.take(params, @keys)
      defp params_to_ets(key), do: key
    end
  end
end
