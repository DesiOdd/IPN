defmodule Ipncore.Event do
  use Ecto.Schema
  alias Ipncore.{Address, Block, Chain, Domain, Repo, Token, Tx, Validator, Wallet}
  import Ipnutils.Macros, only: [deftypes: 1]
  # import Ipnutils.Macros, only: [deftypes: 1, defstatus: 1]
  import Ecto.Query
  import Ipnutils.Filters
  alias __MODULE__

  deftypes do
    [
      {100, "validator.new"},
      {101, "validator.update"},
      {102, "validator.delete"},
      {200, "token.new"},
      {201, "token.update"},
      {202, "token.delete"},
      {210, "tx.coinbase"},
      {211, "tx.send"},
      {212, "tx.sendmulti"},
      {213, "tx.refund"},
      {214, "tx.jackpot"},
      # only validators
      {215, "tx.reward"},
      {216, "tx.burned"},
      {400, "domain.new"},
      {401, "domain.update"},
      {402, "domain.delete"},
      {410, "dns.new"},
      {411, "dns.update"},
      {412, "dns.delete"},
      {1000, "pubkey.new"}
    ]
  else
    {false, false}
  end

  # defstatus do
  #   [
  #     {0, "no processed"},
  #     {1, "pending"},
  #     {2, "approved"},
  #     {3, "complete"},
  #     {-1, "cancelled"},
  #     {-2, "timeout"}
  #   ]
  # else
  #   {false, false}
  # end

  @channel Application.compile_env(:ipncore, :channel)
  @version Application.compile_env(:ipncore, :event_version)
  @threshold_timeout Application.compile_env(:ipncore, :event_threshold_timeout)
  @max_size Application.compile_env(:ipncore, :event_max_size)
  @max_signatures Application.compile_env(:ipncore, :event_max_signatures, 5)

  @base :ev
  @filaname "event.db"

  # mime
  # 0 - text
  # 1 - csv
  # 2 - json
  # 3 - xml
  # 4 - cbor

  @type t :: %__MODULE__{
          id: binary(),
          time: pos_integer(),
          # hash: binary(),
          type: pos_integer(),
          block_index: pos_integer(),
          sig_count: pos_integer(),
          size: pos_integer(),
          vsn: pos_integer()
        }

  @primary_key {:id, :binary, []}
  schema "event" do
    field(:time, :integer)
    field(:type, :integer)
    field(:block_index, :integer)
    field(:sig_count, :integer)
    field(:size, :integer, default: 0)
    field(:vsn, :integer)
  end

  def open(block_height) do
    dir_path = Application.get_env(:ipncore, :events_path, "events")
    filename = Path.join(dir_path, "#{block_height}.db")
    DetsPlus.open_file(@base, name: filename, auto_save_memory: 1_000_000_000)
  end

  def close do
    DetsPlus.close(@base)
  end

  def version, do: @version

  def timeout, do: @threshold_timeout

  @spec check(pos_integer, String.t(), pos_integer, term, String.t(), String.t()) ::
          {:ok, binary} | {:error, String.t()}
  def check(@version, type_name, time, body, address, sig64) do
    try do
      type_number = type_index(type_name)
      if type_name == false, do: throw("Type invalid")

      body_text = Jason.encode!(body)

      from_address = Address.from_text(address)
      hash = calc_hash(type_number, body_text, time)
      signature = Base.decode64!(sig64)

      size = byte_size(body_text) + byte_size(signature)
      if size > @max_size, do: throw("Body size exceeded")

      pubkey = Wallet.get(from_address)

      if Falcon.verify(hash, signature, pubkey) == :error, do: throw("Invalid signature")

      case type_name do
        "pubkey.new" ->
          [pubkey] = body
          Wallet.check!(hash, pubkey, signature)

        "token.new" ->
          token_id = List.first(body)
          Token.check_new!(token_id, from_address)

        "token.delete" ->
          token_id = List.first(body)
          Token.check_delete!(token_id, from_address)

        "validator.new" ->
          [hostname, name | _rest] = body
          Validator.check_new!(hostname, name, from_address)

        "validator.update" ->
          [hostname | _rest] = body
          Validator.check_update!(hostname, from_address)

        "validator.delete" ->
          [hostname | _rest] = body
          Validator.check_delete!(hostname, from_address)

        "domain.new" ->
          [name, email, avatar, validator_host] = body

          Domain.check_new!(
            name,
            email,
            avatar,
            from_address,
            validator_host,
            size
          )

        "domain.udpate" ->
          [name, _validator_host, _params] = body
          Domain.check_update!(name, from_address)

        "domain.delete" ->
          [host] = body
          Domain.check_delete!(host, from_address)

        "tx.send" ->
          [token, _to_address, amount, validator_host] = body

          Tx.check_send!(
            from_address,
            token,
            amount,
            validator_host,
            size
          )

        "tx.coinbase" ->
          [token, _outputs] = body
          Tx.check_coinbase!(from_address, token)
      end

      case Mempool.push!(hash, time, type_number, from_address, body, signature, size) do
        true ->
          {:ok, hash}

        false ->
          throw("Error push to mempool")
      end
    catch
      x -> x
    end
  end

  def new!(next_index, hash, time, type_number, from_address, body, signature, size) do
    # if check_timeout and abs(time - Chain.get_time()) > @timeout, do: throw("Event is timeout")
    type = type_name(type_number)
    put!({hash, time, @version, type_number, from_address, body, signature})

    event = %{
      id: hash,
      type: type_number,
      block_index: next_index,
      sig_count: 1,
      size: size,
      time: time,
      vsn: @version
    }

    channel = @channel

    multi =
      Ecto.Multi.new()
      |> multi_insert(event, channel)

    case type do
      "pubkey.new" ->
        List.first(body)
        |> Wallet.put!()

      "token.new" ->
        [token_id, owner, name, decimals, symbol, props] = body

        Token.new!(
          multi,
          token_id,
          from_address,
          Address.from_text(owner),
          name,
          decimals,
          symbol,
          props,
          time,
          channel
        )

      "token.update" ->
        [token_id, params] = body
        Token.event_update!(multi, token_id, params, channel)

      "token.delete" ->
        [token_id] = body
        Token.event_delete!(multi, token_id, channel)

      "validator.new" ->
        [hostname, owner, fee, fee_type] = body

        Validator.new!(
          multi,
          from_address,
          Address.from_text(owner),
          hostname,
          fee,
          fee_type,
          time,
          channel
        )

      "validator.update" ->
        [hostname, params] = body

        Validator.event_update!(
          multi,
          hostname,
          from_address,
          params,
          time,
          channel
        )

      "validator.delete" ->
        [owner] = body
        Validator.event_delete!(multi, Address.from_text(owner), time, channel)
    end
  end

  def put!(x) do
    case DetsPlus.insert_new(@base, x) do
      false ->
        throw("Event already exists")

      true ->
        true
    end
  end

  def delete(key) do
    DetsPlus.delete(@base, key)
  end

  def multi_insert(multi, event, channel) do
    Ecto.Multi.insert_all(multi, :event, Event, [event],
      returning: false,
      prefix: channel
    )
  end

  # def generate_id(next_block_index, genesis_time, hash, time) do
  #   start_time = Block.block_index_start_time(next_block_index, genesis_time)

  #   [
  #     :binary.encode_unsigned(next_block_index),
  #     <<time - start_time::16>>,
  #     :binary.part(hash, 0, 8)
  #   ]
  #   |> IO.iodata_to_binary()
  # end

  def calc_hash(type_number, event_body_text, time) do
    [
      to_string(type_number),
      event_body_text,
      to_string(time)
    ]
    |> Crypto.hash3()
  end

  def calc_hash(event) do
    [
      to_string(event.vsn),
      to_string(event.type),
      event.body,
      to_string(event.time)
    ]
    |> Crypto.hash3()
  end

  def check_signatures!(hash, sigs) do
    {addresses, byte_size} =
      Enum.reduce(sigs, {[], 0}, fn [address, signature], {acc_addr, acc_size} ->
        bin_address = Address.from_text(address)

        case Wallet.get(bin_address) do
          nil ->
            throw("There is an unregistered address")

          pubkey ->
            case Falcon.verify(hash, signature, pubkey) do
              :ok ->
                {acc_addr ++ [bin_address], byte_size(signature) + acc_size}

              :error ->
                throw("Error signature")
            end
        end
      end)

    {addresses, byte_size, length(sigs)}
  end

  # def encode_id(index) do
  #   Base62.encode(index)
  # end

  # def decode_id(index) do
  #   index
  #   |> Base62.decode()
  #   |> ByteUtils.zeros_pad_leading(104)
  # end

  defmacro map_select do
    quote do
      %{
        id: fragment("encode(?, 'hex')", ev.id),
        time: ev.time,
        type: ev.type,
        block_index: ev.block_index,
        sig_count: ev.sig_count,
        size: ev.size,
        vsn: ev.vsn
      }
    end
  end

  defmacro export_select do
    quote do
      [
        ev.vsn,
        ev.type,
        ev.body,
        ev.sigs,
        ev.time
      ]
    end
  end

  def fetch!(bin_id, channel) do
    from(ev in Event, where: ev.id == ^bin_id)
    |> Repo.one(prefix: channel)
    |> case do
      nil ->
        throw("Event no exists")

      ev ->
        ev
    end
  end

  def one(id, channel) do
    from(ev in Event, where: ev.id == ^id)
    |> Repo.one(prefix: channel)
    |> transform()
  end

  def one_by_hash(hash, channel) do
    from(ev in Event, where: ev.hash == ^hash)
    |> Repo.one(prefix: channel)
    |> transform()
  end

  def all(params) do
    from(ev in Event)
    |> filter_time(params)
    |> filter_offset(params)
    |> filter_limit(params, 10, 1000)
    |> filter_select(params)
    |> sort(params)
    |> Repo.all(prefix: filter_channel(params, Default.channel()))
    |> filter_map()
  end

  defp filter_time(query, %{"from" => from_time, "to" => to_time}) do
    where(query, [ev], ev.time >= ^from_time and ev.time <= ^to_time)
  end

  defp filter_time(query, %{"from" => from_time}) do
    where(query, [ev], ev.time >= ^from_time)
  end

  defp filter_time(query, %{"to" => to_time}) do
    where(query, [ev], ev.time <= ^to_time)
  end

  defp filter_time(query, _), do: query

  defp filter_select(query, %{"fmt" => "export"}) do
    select(query, [ev], export_select())
  end

  defp filter_select(query, _), do: select(query, [ev], map_select())

  defp sort(query, params) do
    case Map.get(params, "sort") do
      "oldest" ->
        order_by(query, [ev], asc: fragment("length(?)", ev.id), asc: ev.id)

      _ ->
        order_by(query, [ev], desc: fragment("length(?)", ev.id), desc: ev.id)
    end
  end

  defp filter_map(data) do
    Enum.map(data, fn x ->
      transform(x)
    end)
  end

  def encode_id(id) do
    Base.encode16(id, case: :lower)
  end

  def decode_id(id) do
    Base.decode16!(id, case: :lower)
  end

  defp transform(nil), do: []
  defp transform([]), do: []

  defp transform(x) do
    # %{x | id: encode_id(x.id), type: type_name(x.type)}
    %{x | type: type_name(x.type)}
  end
end