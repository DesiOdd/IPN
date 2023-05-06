defmodule Ipncore.Application do
  @moduledoc false
  use Application
  require Logger

  # alias Ippan.Address

  @otp_app :ipncore
  @opts [strategy: :one_for_one, name: Ipncore.Supervisor]

  # @compile :native
  # @compile {:hipe, [:verbose, :o3]}

  @impl true
  def start(_type, _args) do
    Logger.info("Starting application")
    # try do
    #   # create data folder
    data_dir = Application.get_env(@otp_app, :data_dir, "data")
    File.mkdir(data_dir)

    #   # load node config
    #   node_config()

    #   # run migration
    #   migration_start()

    #   # open local databases
    # with {:ok, _pid} <- Chain.open(),
    #      {:ok, _pid} <- Event.open(Block.epoch(Chain.next_index())),
    #      :mempool <- Mempool.open(),
    #      [{:ok, _pid} | _rest] <- Wallet.open(),
    #      {:ok, _pid} <- Balance.open(),
    #      {:ok, _pid} <- Token.open(),
    #      {:ok, _pid} <- Validator.open(),
    #      {:ok, _pid} <- Tx.open(),
    #      {:ok, _pid} <- Domain.open(),
    #      {:ok, _pid} <- DnsRecord.open() do
    #   Platform.start()
    # else
    #   err -> throw(err)
    # end

    #   # init chain
    #   :ok = Chain.start()

    #   # services
    children = [
      # {DetsPlus,
      #  [
      #    name: :account,
      #    file: String.to_charlist(Path.join(data_dir, "account.db")),
      #    keypos: :id,
      #    auto_save: :infinity
      #  ]},
      {AccountStore, Path.join(data_dir, "account/account.db")},
      {EnvStore, Path.join(data_dir, "env/env.db")},
      {ValidatorStore, Path.join(data_dir, "validator/validator.db")},
      {TokenStore, Path.join(data_dir, "token/token.db")},
      {BalanceStore, Path.join(data_dir, "txs/balance.db")},
      {RefundStore, Path.join(data_dir, "txs/refund.db")},
      {DomainStore, Path.join(data_dir, "domain/domain.db")},
      {DnsStore, Path.join(data_dir, "dns/dns.db")},
      {BlockStore, Path.join(data_dir, "chain/block.db")},
      {RoundStore, Path.join(data_dir, "chain/round.db")},
      RequestStore,
      # {HashList, [name: :l2]},
      Supervisor.child_spec({Phoenix.PubSub, name: :pubsub}, id: :pubsub),
      p2p_server()
    ]


    HashList.start(:l1)
    HashList.start(:l2)

    #   # start block builder
    #   BlockBuilderWork.next()

    Supervisor.start_link(children, @opts)
    # rescue
    #   DBConnection.ConnectionError ->
    #     {:error, "Database connexion failed"}
    # end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping application")
  end

  # defp migration_start do
  #   {:ok, supervisor} = Supervisor.start_link([Repo], @opts)

  #   # migration
  #   Migration.start()

  #   :ok = Supervisor.stop(supervisor, :normal)
  # end

  # defp node_config do
  #   falcon_dir = Application.get_env(@otp_app, :falcon_dir)

  #   {falcon_pk, _falcon_sk} = falcon_dir |> Falcon.read_file!()

  #   address = Address.hash(falcon_pk)
  #   Application.put_env(@otp_app, :address, address)
  #   Application.put_env(@otp_app, :address58, Address.to_text(address))
  # end

  # p2p server
  defp p2p_server do
    opts = Application.get_env(@otp_app, :p2p)
    Ippan.P2P.Server.load()
    {ThousandIsland, opts}
  end
end
