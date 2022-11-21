defmodule Mempool do
  @table :mempool

  @total_threads Application.get_env(:ipncore, :total_threads, System.schedulers_online())

  def open do
    :ets.whereis(@table)
    |> case do
      :undefined ->
        :ets.new(@table, [
          :ordered_set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end
  end

  defmacro assign_worker_thread(from) do
    quote do
      :binary.last(unquote(from))
      |> rem(@total_threads)
    end
  end

  def push!(hash, time, type_number, from, body, signature, size) do
    thread = assign_worker_thread(from)
    :ets.insert_new(@table, {{time, hash}, thread, type_number, from, body, signature, size})
  end

  def get(time, hash) do
    case :ets.lookup(@table, {time, hash}) do
      [obj] -> obj
      _ -> nil
    end
  end

  def select(thread, timestamp) do
    # :ets.fun2ms(fn {{_hash, time}, thread, _type, _from, _body, _sigs, _size} = x when thread == 0 and time <= 1 -> x end)
    fun = [
      {{{:"$1", :"$2"}, :"$3", :"$4", :"$5", :"$6", :"$7", :"$8"},
       [{:andalso, {:==, :"$3", thread}, {:"=<", :"$2", timestamp}}], [:"$_"]}
    ]

    :ets.select(@table, fun)
  end

  def select_delete(timestamp) do
    # :ets.fun2ms(fn {{_hash, time}, thread, _type, _from, _body, _sigs, _size} = x when and time <= 0 -> true end)
    fun = [
      {{{:"$1", :"$2"}, :"$3", :"$4", :"$5", :"$6", :"$7", :"$8"}, [{:"=<", :"$2", timestamp}], [true]}
    ]

    :ets.select_delete(@table, fun)
  end
end