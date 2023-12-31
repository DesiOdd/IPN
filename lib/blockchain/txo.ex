defmodule Ipncore.Txo do
  use Ecto.Schema
  alias Ipncore.{Token, Tx, Repo}
  import Ecto.Query, only: [from: 1, from: 2, where: 3, order_by: 3, select: 3, join: 5]
  import Ipnutils.Filters
  alias __MODULE__

  @type t :: %__MODULE__{
          id: binary(),
          tid: binary,
          value: pos_integer(),
          address: binary(),
          type: String.t(),
          avail: boolean()
        }

  @output_type_send "S"
  @output_type_fee "%"
  @output_type_return "R"
  @output_type_coinbase "C"

  @doc """
  Avail:
  null -> is pending
  true -> is approved (Ready to use)
  false -> output is used
  """
  @primary_key false
  schema "txo" do
    field(:id, :binary)
    field(:tid, :string)
    field(:address, :binary)
    field(:type, :string)
    field(:value, :integer)
    field(:avail, :boolean, default: nil)
  end

  @spec create(binary, binary, integer, binary, binary, integer) :: t
  def create(token_id, address, value, type, tx_index, index \\ 0)

  def create(_token_id, _address, value, _type, _tx_index, index)
      when value <= 0 or index < 0,
      do: throw("outputs does not have zero or negative value or negative index")

  def create(token_id, address, value, type, tx_index, index) do
    %Txo{
      id: generate_index(tx_index, index),
      tid: token_id,
      address: address,
      type: type,
      value: value
    }
  end

  @spec order([t], integer) :: [t]
  def order(outputs, tx_index, index \\ 0)
  def order([], _tx_index, _index), do: []

  def order([output | rest], tx_index, index) do
    [
      %{
        id: generate_index(tx_index, index),
        tid: output.tid,
        address: output.address,
        type: output.type,
        value: output.value,
        avail: output.avail
      }
    ] ++
      order(rest, tx_index, index + 1)
  end

  @spec compute_sum([Txo.t()]) :: integer
  def compute_sum([]), do: 0

  def compute_sum([o | rest]) do
    o.value + compute_sum(rest)
  end

  @spec extract!([t]) :: {[Txo.t()], List.t(), List.t(), List.t(), Map.t(), integer}
  def extract!(outputs) do
    {outputs, ids, tokens, address, token_value, value} =
      Enum.reduce(outputs, {[], [], [], [], %{}, 0}, fn x, {outputs, ids, t, a, tv, v} ->
        # convert address base58 to binary
        addr = Base58Check.decode(x.address)

        # check output value major than zero
        if x.value <= 0, do: throw(40207)

        # check output types
        if x.type not in [@output_type_send, @output_type_fee, @output_type_return],
          do: throw(40207)

        output = %Txo{
          address: addr,
          tid: x.tid,
          value: x.value,
          type: x[:type] || @output_type_send
        }

        value = Map.get(tv, x.tid, 0) + x.value
        token_value = Map.put(tv, x.tid, value)

        {output ++ outputs, ids ++ [x.id], t ++ [x.tid], a ++ [addr], token_value, v + x.value}
      end)

    {ids, Enum.uniq(tokens) |> Enum.sort(), Enum.uniq(address), token_value, value}
  end

  @spec valid_amount?(Txo) :: :ok | {:error, atom()}
  def valid_amount?(output) do
    if output.value > 0, do: :ok, else: {:error, :invalid_output_value}
  end

  @spec valid_index?(Txo) :: :ok | {:error, atom()}
  def valid_index?(output) do
    if output.index > 0, do: :ok, else: {:error, :invalid_output_index}
  end

  @spec extract_coinbase!([t]) :: {List.t(), List.t(), List.t(), pos_integer()}
  def extract_coinbase!(outputs, type \\ @output_type_coinbase) do
    {outputs, tokens, address, total} =
      Enum.reduce(outputs, {[], [], [], 0}, fn %{
                                                 "address" => address,
                                                 "tid" => tid,
                                                 "value" => value
                                               },
                                               {o, t, a, v} ->
        addr = Base58Check.decode(address)

        if value <= 0 do
          throw(40207)
        end

        output = %Txo{
          address: addr,
          tid: tid,
          value: value,
          type: type
        }

        {o ++ [output], t ++ [tid], a ++ [address], v + value}
      end)

    {outputs, Enum.uniq(tokens), Enum.uniq(address), total}
  end

  @spec generate_index(binary, pos_integer()) :: binary()
  def generate_index(tx_index, index) do
    [tx_index, <<index::24>>] |> IO.iodata_to_binary()
  end

  def calc_size([]), do: 0

  def calc_size([o | rest]) do
    calc_size(o) + calc_size(rest)
  end

  def calc_size(o) do
    byte_size(o.id) + byte_size(o.tid) + 8 + byte_size(o.address)
  end

  def calc_size(txos, output_index_size) do
    Enum.reduce(txos, 0, fn o, acc ->
      output_index_size + byte_size(o.tid) + 8 + byte_size(o.address) + acc
    end)
  end

  def multi_insert_all(multi, _name, nil, _channel), do: multi
  def multi_insert_all(multi, _name, [], _channel), do: multi

  def multi_insert_all(multi, name, outputs, channel) do
    Ecto.Multi.insert_all(multi, name, Txo, outputs, prefix: channel, returning: false)
  end

  @spec update_txo_avail([binary], binary, boolean) :: {integer, List.t() | nil}
  def update_txo_avail(oids, channel_id, value) when is_list(oids) do
    from(txo in Txo,
      where: txo.id in ^oids,
      update: [set: [avail: ^value]]
    )
    |> Repo.update_all([], prefix: channel_id)
  end

  @spec update_txid_avail(binary, binary, boolean) :: {integer, List.t() | nil}
  def update_txid_avail(txid, channel_id, value) do
    from(txo in Txo,
      where: fragment("substring(?::bytea from 1 for ?)", txo.id, ^byte_size(txid)) == ^txid,
      update: [set: [avail: ^value]]
    )
    |> Repo.update_all([], prefix: channel_id)
  end

  def multi_update_avail(multi, _name, nil, _channel, _value), do: multi
  def multi_update_avail(multi, _name, [], _channel, _value), do: multi

  def multi_update_avail(multi, name, oids, channel, value) do
    query = from(txo in Txo, where: txo.id in ^oids)

    Ecto.Multi.update_all(
      multi,
      name,
      query,
      [set: [avail: value]],
      returning: false,
      prefix: channel
    )
  end

  def all(params) do
    from(Txo)
    |> where([o], not is_nil(o.avail))
    |> filter_available(params)
    |> filter_index(params)
    |> filter_address(params)
    |> filter_token(params)
    |> filter_offset(params)
    |> filter_limit(params, 50, 100)
    |> filter_select(params)
    |> sort(params)
    |> Repo.all(prefix: filter_channel(params, Default.channel()))
    |> transform(params)
  end

  defp filter_index(query, %{"hash" => hash16}) do
    hash = Base.decode16!(hash16, case: :mixed)

    sub = from(tx in Tx, where: tx.hash == ^hash, select: tx.index)

    where(
      query,
      [txo],
      fragment("substring(?::bytea from 1 for ?)", txo.id, fragment("length(?)", subquery(sub))) ==
        subquery(sub)
    )
  end

  defp filter_index(query, %{"txid" => txid}) do
    txid = Base62.decode(txid)

    where(
      query,
      [txo],
      fragment("substring(?::bytea from 1 for ?)", txo.id, ^byte_size(txid)) == ^txid
    )
  end

  defp filter_index(query, _params), do: query

  defp filter_available(query, %{"used" => "0"}) do
    where(query, [txo], txo.avail == false)
  end

  defp filter_available(query, %{"used" => "1"}) do
    where(query, [txo], txo.avail == true)
  end

  defp filter_available(query, _params), do: query

  defp filter_address(query, %{"address" => address}) do
    bin_address = Base58Check.decode(address)
    where(query, [txo], txo.address == ^bin_address)
  end

  defp filter_address(query, _params), do: query

  defp filter_token(query, %{"token" => token}) do
    where(query, [txo], txo.tid == ^token)
  end

  defp filter_token(query, _params), do: query

  defp filter_select(query, %{"show" => "props"}) do
    query
    |> join(:inner, [o], tk in Token, on: tk.id == o.tid)
    |> select([o, tk], %{
      id: o.id,
      token: o.tid,
      type: o.type,
      value: o.value,
      address: o.address,
      available: o.avail,
      decimals: tk.decimals,
      symbol: tk.props["symbol"]
    })
  end

  defp filter_select(query, %{"fmt" => "array"}) do
    select(query, [o], [
      o.id,
      o.address,
      o.tid,
      o.type,
      o.value,
      o.avail
    ])
  end

  defp filter_select(query, _params) do
    select(query, [o], %{
      id: o.id,
      token: o.tid,
      type: o.type,
      value: o.value,
      address: o.address,
      available: o.avail
    })
  end

  defp sort(query, params) do
    case Map.get(params, "sort") do
      "newest" ->
        order_by(query, [txo], desc: fragment("length(?)", txo.id), desc: txo.id)

      _ ->
        order_by(query, [txo], asc: fragment("length(?)", txo.id), asc: txo.id)
    end
  end

  defp transform(txos, %{"fmt" => "array"}) do
    Enum.map(txos, fn [id, address, token, type, value, avail] ->
      [
        Base62.encode(id),
        Base58Check.encode(address),
        token,
        type,
        value,
        avail
      ]
    end)
  end

  defp transform(txos, _) do
    Enum.map(txos, fn x ->
      %{x | id: Base62.encode(x.id), address: Base58Check.encode(x.address)}
    end)
  end
end
