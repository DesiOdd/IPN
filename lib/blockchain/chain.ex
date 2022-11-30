defmodule Ipncore.Chain do
  require Logger
  # use Ipnutils.FastGlobal, name: FG.Chain
  # use GenServer
  alias Ipncore.{Block, Channel, IIT, Repo, BlockValidator}

  @compile {:inline, get_time: 0, genesis_time: 0, last_block: 0}
  @base :chain
  @table :chain
  @filename "chain.db"
  @unit_time Default.unit_time()

  # def start_link(_opts) do
  #   GenServer.start_link(__MODULE__, [], name: __MODULE__)
  # end

  # @impl true
  # def init(_opts) do
  #   {:ok, nil}
  # end

  # @impl true
  # def handle_info({:start_block_round, channel}, last_key) do
  #   Logger.debug("start_block_round")

  #   genesis_time = genesis_time()
  #   iit = get_time()
  #   cycle = Default.block_interval()

  #   calc_time = cycle - rem(iit - genesis_time, cycle)

  #   Process.send_after(__MODULE__, {:start_block_round, channel}, calc_time)

  #   build_all(channel)

  #   {:noreply, last_key}
  # end

  defmacrop put(atom_name, val) do
    quote do
      obj = {unquote(atom_name), unquote(val)}
      :ets.insert(@table, obj)
      DetsPlus.insert(@base, obj)
    end
  end

  defmacrop get(atom_name, default \\ nil) do
    quote do
      case :ets.lookup(@table, unquote(atom_name)) do
        [{_k, val}] -> val
        _ -> unquote(default)
      end
    end
  end

  def open do
    :ets.whereis(@table)
    |> case do
      :undefined ->
        :ets.new(@table, [
          :set,
          :public,
          :named_table,
          read_concurrency: true,
          write_concurrency: true
        ])

      _ ->
        :ok
    end

    dir_path = Application.get_env(:ipncore, :data_path, "data")
    filename = Path.join(dir_path, @filename)
    DetsPlus.open_file(@base, file: filename, auto_save: 15_000)
  end

  def close do
    DetsPlus.close(@base)
  end

  def last_block do
    get(:last_block)
  end

  def get_time do
    # diff = get(:diff_iit, 0)
    # if diff == 0, do: throw(:error_time)
    :erlang.system_time(@unit_time) + get(:diff_time, 0)
  end

  def next_index do
    case get(:next_index) do
      nil -> 0
      n -> n + 1
    end
  end

  # @impl true
  # def handle_call(:diff_time, _from, state) do
  #   {:reply, Map.get(state, :diff_iit), state}
  # end

  # def handle_call(:last_block, _from, state) do
  #   {:reply, Map.get(state, :last_block), state}
  # end

  # def handle_call(:height, _from, state) do
  #   {:reply, Map.get(state, :height), state}
  # end

  # @impl true
  # def handle_cast({:last_block, block}, state) do
  #   new_state = Map.merge(state, %{last_block: block, height: block.height})
  #   {:noreply, new_state}
  # end

  def put_iit(iit_time) when iit_time > 0 do
    put(:diff_iit, iit_time - :erlang.system_time(@unit_time))
  end

  def put_last_block(nil), do: :none

  def put_last_block(last_block) do
    put(:last_block, last_block)
    put(:next_index, last_block.height + 1)
  end

  def genesis_block, do: get(:genesis_block)
  def genesis_time, do: get(:genesis_time, 0)

  def put_genesis_block(block) do
    put(:genesis_block, block)
    put(:genesis_time, block.time)
  end

  def initialize do
    Logger.info("Chain initialize")

    channel_id = Default.channel()

    # time sync
    iit = IIT.sync()
    put_iit(iit)

    # get last block built
    last_block = last_block()
    my_address = Default.address58()

    case last_block do
      nil ->
        """
        Channel #{channel_id} is ready!
        IIT          #{Format.timestamp(iit)}
        No Blocks
        Host Address #{my_address}
        """
        |> Logger.info()

      last_block ->
        genesis_block = genesis_block()

        """
        Channel #{channel_id} is ready!
        IIT          #{Format.timestamp(iit)}
        Genesis Time #{Format.timestamp(genesis_block.time)}
        Last block   #{last_block.height}
        Next block   #{last_block.height + 1}
        Host Address #{my_address}
        """
        |> Logger.info()
    end
  end

  def add_block(prev_block, b, channel_id) do
    is_genesis_block = b.height == 0

    case BlockValidator.valid_block?(prev_block, b) do
      :ok ->
        block =
          b
          |> Map.from_struct()
          |> Map.drop([:events, :__meta__])

        IO.inspect(block)

        if is_genesis_block do
          put_genesis_block(block)
        end

        put_last_block(block)

        Ecto.Multi.new()
        |> Ecto.Multi.insert_all(:block, Block, [block], prefix: channel_id, returning: false)
        # |> Tx.set_status_complete(:txs, block.height, channel_id)
        # |> Tx.cancel_all_pending(:pending, block.height, channel_id)
        |> Channel.multi_put_genesis_time(:gen_time, channel_id, block.time, is_genesis_block)
        |> Channel.multi_update(
          :channel,
          channel_id,
          block.height,
          block.hash,
          1,
          block.ev_count
        )
        |> Repo.transaction()
        |> case do
          {:ok, _} ->
            :ok

          err ->
            IO.inspect(err)

            # Ecto.Multi.new()
            # |> Tx.cancel_all_pending(:pending, b.index, channel_id)
            # |> Repo.transaction()

            err
        end

      err ->
        IO.inspect(err)

        err
    end
  end

  # def build_next(channel) do
  #   if has_channel() do
  #     next_index = Block.next_index()
  #     next_index = if(next_index == 0, do: 0, else: next_index - 1)
  #     prev_block = prev_block()
  #     txs_approved = Tx.get_all_approved(next_index, channel)

  #     case Block.next(prev_block, txs_approved) do
  #       nil ->
  #         IO.inspect("nil block")
  #         nil

  #       block ->
  #         IO.inspect("adding block")
  #         add_block(block, prev_block, channel)
  #         block
  #     end
  #   else
  #     nil
  #   end
  # end

  # def build_all(channel) do
  # if has_channel() do
  #   before_next_index = next_index_to_build()

  #   if before_next_index >= 0 do
  #     txs_approved_grouped_by_block =
  #       Tx.get_all_approved(channel)
  #       |> Enum.filter(&(&1.block_index <= before_next_index))
  #       |> Enum.group_by(fn x -> x.block_index end)

  #     txs_approved_grouped_by_block
  #     |> Enum.map(fn {block_index, txs} ->
  #       prev_block = prev_block()
  #       block = Block.new(prev_block, block_index, txs)
  #       add_block(prev_block, block, channel)
  #       block
  #     end)
  #   else
  #     []
  #   end
  # end
  # end

  # def next_index_to_build do
  #   index = next_index()

  #   cond do
  #     index == 0 ->
  #       0

  #     true ->
  #       index - 1
  #   end
  # end
end
