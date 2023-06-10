defmodule BlockTimer do
  use GenServer
  alias Ippan.Request

  @otp_app :ipncore
  @block_interval Application.compile_env(:ipncore, :block_interval)
  @block_max_size Application.compile_env(:ipncore, :block_max_size)
  @block_version Application.compile_env(:ipncore, :block_version)
  @file_extension "json"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    validator_id = Default.validator_id()
    # local_blocks = BlockStore.count(validator_id)
    my_last_block = BlockStore.last(validator_id)

    {:ok,
     %{
       height: my_last_block.height,
       round: my_last_block.round
     }, {:continue, :init}}
  end

  @impl true
  def handle_continue(:init, state) do
    tref = :timer.send_after(@block_interval, :mine)
    {:noreply, Map.put(state, :tref, tref)}
  end

  @impl true
  def handle_call(:round, _from, %{round: round} = state) do
    {:reply, round, state}
  end

  @impl true
  def handle_info(:mine, %{height: height, round: old_round, tref: tref} = state) do
    :timer.cancel(tref)

    case MessageStore.fetch_by_size(@block_max_size) do
      {:ok, []} ->
        # empty block
        nil

      {:ok, requests} ->
        data_dir = Application.get_env(@otp_app, :data_dir, "data")

        block_path = Path.join([data_dir, "blocks", "#{height}.block.#{@file_extension}"])

        events =
          Enum.reduce(requests, [], fn [hash, msg, _signature, size], acc ->
            try do
              Request.handle(hash, msg, size)
            rescue
              _e ->
                acc
            end
          end)
          |> encode!()

        sync_all()

        :ok = File.write(block_path, events)
        block_size = File.stat!(block_path).size
        hashfile = hash_file(block_path)
        new_height = height + 1
        timestamp = :os.system_time(:millisecond)
        ev_count = length(events)

        BlockStore.insert([
          new_height,
          Default.validator_id(),
          hashfile,
          old_round + 1,
          timestamp,
          ev_count,
          block_size,
          @block_version
        ])

        BlockStore.sync()
    end

    tref = :timer.send_after(@block_interval, :mine)
    {:noreply, %{state | tref: tref}}
  end

  defp sync_all do
    # MessageStore.sync()
    WalletStore.sync()
    BalanceStore.sync()
    ValidatorStore.sync()
    TokenStore.sync()
    DomainStore.sync()
    DnsStore.sync()
    EnvStore.sync()
    # BlockStore.sync()
    # RoundStore.sync()
    RefundStore.sync()
  end

  defp encode!(content) do
    Jason.encode!(content)
  end

  defp decode!(content) do
    Jason.decode!(content)
  end

  @hash_module Blake3.Native
  defp hash_file(path) do
    state = @hash_module.new()

    File.stream!(path, [], 2048)
    |> Enum.reduce(state, &@hash_module.update(&2, &1))
    |> @hash_module.finalize()
  end
end