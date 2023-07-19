defmodule Platform do
  import Ippan.Utils, only: [to_atom: 1]
  alias Ippan.Address

  @token Application.compile_env(:ipncore, :token)
  @json Application.compile_env(:ipncore, :json)

  def start("miner") do
    data_dir = Application.get_env(:ipncore, :data_dir)
    {:ok, pid} = WalletStore.start_link(Path.join(data_dir, "wallet/wallet.db"))
    {:ok, pid2} = TokenStore.start_link(Path.join(data_dir, "token/token.db"))
    {:ok, pid3} = ValidatorStore.start_link(Path.join(data_dir, "validator/validator.db"))

    # load native token data
    case TokenStore.lookup([@token]) do
      nil ->
        init("miner")

      token ->
        wallet_owner = token.owner
        [_, wallet_pubkey, _wallet_validator] = WalletStore.lookup([wallet_owner])

        GlobalConst.new(Global, %{
          owner: wallet_owner,
          owner_pubkey: wallet_pubkey,
          native_token: token,
          vid: Application.get_env(:ipncore, :vid)
        })
    end

    GenServer.stop(pid, :normal)
    GenServer.stop(pid2, :normal)
    GenServer.stop(pid3, :normal)
  end

  def start("verifier") do
    data_dir = Application.get_env(:ipncore, :data_dir)
    {:ok, pid} = WalletStore.start_link(Path.join(data_dir, "wallet/wallet.db"))
    init("verifier")
    GenServer.stop(pid, :normal)
  end

  def has_owner? do
    case Global.get(:owner, false) do
      false ->
        false

      _ ->
        true
    end
  end

  def owner?(nil), do: false

  def owner?(id) do
    Global.get(:owner, nil) == id
  end

  defp init(role) do
    pk =
      <<133, 210, 110, 113, 239, 43, 61, 189, 153, 31, 241, 205, 62, 28, 241, 50, 184, 225, 166,
        252, 172, 96, 246, 11, 32, 130, 167, 194, 57, 206, 148, 104>>

    pkf =
      <<9, 6, 96, 16, 73, 228, 25, 137, 34, 26, 197, 32, 216, 102, 91, 111, 98, 106, 176, 44, 4,
        33, 150, 14, 206, 230, 194, 106, 8, 105, 34, 28, 154, 25, 148, 166, 54, 157, 149, 192, 93,
        169, 29, 142, 210, 97, 118, 223, 203, 86, 130, 37, 114, 35, 80, 145, 120, 19, 134, 200,
        37, 81, 90, 118, 78, 104, 149, 21, 219, 131, 225, 33, 241, 50, 101, 143, 138, 241, 15,
        252, 179, 72, 65, 5, 105, 112, 64, 37, 59, 15, 92, 127, 121, 74, 255, 196, 93, 212, 22,
        117, 21, 220, 192, 240, 5, 130, 137, 29, 106, 212, 38, 210, 156, 129, 182, 139, 21, 22,
        79, 79, 5, 164, 168, 84, 30, 133, 13, 26, 130, 201, 35, 218, 9, 232, 121, 136, 90, 101,
        52, 106, 196, 34, 86, 100, 209, 25, 77, 224, 151, 94, 60, 250, 206, 91, 101, 100, 22, 194,
        161, 148, 43, 14, 171, 170, 249, 71, 236, 201, 21, 56, 225, 3, 24, 197, 90, 79, 0, 200,
        19, 217, 211, 78, 15, 153, 112, 167, 81, 2, 37, 18, 114, 186, 42, 250, 6, 66, 134, 179,
        22, 88, 32, 171, 43, 173, 129, 60, 146, 22, 17, 175, 8, 63, 182, 242, 181, 172, 66, 254,
        145, 64, 225, 86, 240, 160, 49, 97, 66, 12, 194, 196, 26, 91, 31, 20, 143, 105, 24, 64,
        251, 173, 204, 243, 32, 125, 174, 127, 139, 245, 177, 65, 244, 144, 197, 74, 62, 237, 251,
        137, 204, 104, 112, 170, 73, 24, 179, 234, 189, 124, 40, 60, 216, 83, 75, 126, 91, 73,
        125, 57, 215, 226, 84, 184, 45, 92, 162, 109, 95, 197, 17, 205, 40, 161, 200, 71, 179, 3,
        113, 212, 164, 83, 37, 184, 90, 116, 162, 25, 206, 17, 145, 2, 101, 35, 200, 204, 237,
        106, 191, 62, 154, 107, 124, 38, 199, 174, 32, 220, 37, 76, 102, 178, 28, 88, 188, 132,
        245, 0, 83, 36, 138, 221, 244, 92, 232, 13, 161, 9, 236, 160, 26, 87, 155, 149, 236, 7,
        114, 66, 165, 73, 116, 68, 225, 25, 122, 105, 176, 179, 129, 213, 72, 249, 18, 158, 66,
        164, 35, 2, 80, 128, 19, 122, 226, 200, 41, 128, 41, 12, 183, 138, 248, 250, 34, 35, 93,
        34, 166, 63, 235, 104, 28, 100, 84, 245, 117, 42, 114, 96, 52, 42, 190, 113, 73, 80, 85,
        179, 12, 62, 183, 33, 202, 108, 147, 97, 73, 227, 42, 108, 222, 65, 54, 144, 214, 196, 44,
        35, 187, 56, 225, 132, 161, 239, 155, 220, 90, 170, 88, 81, 97, 152, 138, 190, 100, 112,
        40, 124, 76, 160, 186, 78, 73, 228, 133, 98, 157, 162, 22, 37, 48, 227, 173, 131, 156, 48,
        189, 53, 171, 99, 69, 129, 246, 124, 16, 80, 223, 126, 179, 5, 218, 82, 192, 68, 27, 33,
        9, 219, 86, 59, 167, 125, 11, 241, 71, 104, 231, 45, 125, 154, 128, 111, 232, 14, 68, 15,
        179, 36, 23, 212, 203, 206, 211, 25, 134, 194, 3, 23, 80, 119, 116, 32, 202, 135, 141,
        129, 47, 102, 214, 229, 184, 176, 210, 225, 156, 140, 240, 240, 82, 92, 59, 91, 37, 21,
        218, 45, 136, 171, 172, 176, 103, 193, 98, 238, 160, 16, 190, 53, 180, 59, 0, 191, 25, 61,
        0, 116, 199, 208, 10, 48, 38, 202, 90, 146, 215, 247, 68, 145, 100, 131, 249, 173, 243,
        38, 208, 34, 2, 125, 155, 8, 97, 246, 243, 130, 41, 224, 168, 31, 88, 14, 163, 167, 95,
        50, 82, 253, 59, 192, 2, 100, 177, 58, 160, 119, 202, 67, 2, 217, 168, 253, 46, 91, 30,
        68, 5, 15, 8, 244, 98, 116, 89, 182, 86, 60, 124, 82, 105, 82, 66, 167, 32, 195, 86, 242,
        150, 175, 135, 81, 91, 147, 204, 206, 132, 103, 2, 218, 192, 140, 44, 118, 157, 194, 194,
        16, 94, 168, 19, 172, 200, 189, 146, 61, 230, 49, 162, 218, 226, 86, 124, 67, 111, 153,
        22, 62, 234, 129, 36, 29, 136, 213, 13, 139, 243, 233, 190, 89, 110, 195, 129, 16, 173,
        150, 131, 204, 66, 1, 85, 166, 82, 71, 154, 193, 96, 1, 158, 143, 23, 2, 208, 25, 157,
        211, 62, 86, 196, 131, 36, 220, 3, 115, 100, 136, 113, 17, 189, 0, 133, 158, 50, 124, 217,
        24, 197, 218, 123, 213, 171, 227, 185, 205, 201, 136, 192, 125, 229, 86, 197, 102, 33, 2,
        74, 228, 227, 35, 165, 60, 32, 78, 89, 115, 26, 211, 162, 112, 227, 32, 40, 130, 113, 115,
        84, 46, 136, 216, 68, 62, 5, 212, 6, 67, 230, 71, 147, 53, 21, 85, 165, 160, 238, 51, 16,
        166, 73, 250, 30, 228, 143, 94, 240, 188, 67, 117, 220, 53, 61, 49, 161, 166, 66, 158, 58,
        64, 77, 113, 119, 211, 215, 11, 87, 102, 95, 216, 54, 21, 34, 56, 213, 56, 87, 119, 220,
        6, 88, 44, 190, 169, 24, 156, 69, 152, 209, 59, 145, 2, 205, 63, 66, 93, 166, 233, 37,
        213, 252, 174, 93, 93, 27, 143, 105, 210, 108, 173, 237, 242, 121, 109, 64, 132, 205, 198,
        185, 243, 95, 104, 48, 198, 241, 246, 236, 46, 162>>

    address = Address.hash(0, pk)
    timestamp = 1_689_230_000_000

    WalletStore.insert_sync([address, pk, 0, timestamp])

    if role == "miner" do
      TokenStore.insert_sync([
        @token,
        address,
        "IPPAN",
        "https://avatar.com",
        9,
        "Þ",
        true,
        0,
        0,
        # @json.encode!(["coinbase", "lock", "burn"]),
        @json.encode!(["burn"]),
        timestamp,
        timestamp
      ])

      ValidatorStore.insert_sync([
        0,
        "visurpay.com",
        "Speedy",
        address,
        pk,
        pkf,
        nil,
        1,
        0.01,
        0,
        timestamp,
        timestamp
      ])

      ValidatorStore.insert_sync([
        1,
        "ippan.co.uk",
        "Raptor",
        address,
        pk,
        pkf,
        nil,
        1,
        0.01,
        0,
        timestamp,
        timestamp
      ])

      TokenStore.sync()
      ValidatorStore.sync()
    end

    WalletStore.sync()

    GlobalConst.new(Global, %{
      owner: address,
      owner_pubkey: pk,
      miner: System.get_env("MINER") |> to_atom(),
      vid: Application.get_env(:ipncore, :vid)
    })
  end
end
