defmodule Ipncore.Tx do
  use Ecto.Schema
  require Logger
  import Ipnutils.Macros, only: [deftypes: 1, defstatus: 1]
  import Ecto.Query, only: [from: 1, from: 2, where: 3, select: 3, order_by: 3, join: 5]
  import Ipnutils.Filters
  alias Ipncore.{Address, Balance, Block, Chain, Txo, Balance, Token, Validator}
  alias __MODULE__

  @unit_time Default.unit_time()
  @status_complete 3

  @token Default.token()
  @output_reason_send "S"
  @output_reason_coinbase "C"
  @output_reason_fee "%"
  @output_reason_refund "R"

  @primary_key {:id, :binary, []}
  schema "tx" do
    field(:out_count, :integer)
    field(:token_value, :map)
    field(:fee, :integer, default: 0)
    field(:refundable, :boolean, default: false)
    field(:memo, :string)
  end

  defmacro map_select do
    quote do
      %{
        id: tx.id,
        out_count: tx.out_count,
        time: ev.time,
        token_value: ev.time,
        fee: tx.fee,
        refundable: tx.refundable,
        memo: tx.memo
      }
    end
  end

  def send!(
        multi,
        channel,
        txid,
        timestamp,
        event_size,
        token,
        from_address,
        amount,
        to_address,
        validator_address,
        refundable,
        memo
      ) do
    if amount <= 0, do: throw("Invalid amount to send")

    if from_address == to_address or to_address == Default.imposible_address(),
      do: throw("Invalid address to send")

    validator = Validator.fetch!(validator_address)
    fee_total = calc_fees(validator.fee_type, validator.fee, amount, event_size)

    outputs = [
      %{
        id: txid,
        ix: 0,
        from: from_address,
        to: to_address,
        value: amount,
        token: token,
        reason: @output_reason_send,
        avail: false
      },
      %{
        id: txid,
        ix: 1,
        token: token,
        from: from_address,
        to: validator_address,
        value: fee_total,
        reason: @output_reason_fee,
        avail: false
      }
    ]

    Balance.update!(
      [{from_address, token}, {to_address, token}, {validator_address, token}],
      %{
        {from_address, token} => -(amount + fee_total),
        {to_address, token} => amount,
        {validator_address, token} => fee_total
      }
    )

    tx = %{
      id: txid,
      fee: fee_total,
      refundable: refundable,
      token_value: Map.put(Map.new(), token, amount),
      out_count: length(outputs),
      memo: memo
    }

    multi
    |> multi_insert(tx, channel)
    |> Txo.multi_insert_all(:txo, outputs, channel)
    |> Balance.multi_upsert(:balances, outputs, timestamp, channel)
  end

  def coinbase!(
        multi,
        channel,
        txid,
        timestamp,
        token_id,
        from_address,
        init_outputs,
        memo
      ) do
    {outputs, keys_entries, entries, token_value, amount} =
      outputs_extract_coinbase!(txid, init_outputs, token_id)

    if Token.owner?(token_id, from_address, channel) != false,
      do: throw("Invalid owner")

    Balance.update!(keys_entries, entries)

    tx = %{
      id: txid,
      fee: 0,
      token_value: token_value,
      refundable: false,
      memo: memo,
      out_count: length(outputs)
    }

    multi
    |> multi_insert(tx, channel)
    |> Txo.multi_insert_all(:txo, outputs, channel)
    |> Token.multi_update_stats(:token, token_id, amount, timestamp, channel)
    |> Balance.multi_upsert_coinbase(:balances, outputs, timestamp, channel)
  end

  def send_fee!(multi, channel, txid, timestamp, event_size, from_address, validator_address) do
    validator = Validator.fetch!(validator_address)
    fee_total = calc_fees(0, 1, 0, event_size)

    Balance.update!(
      [{from_address, @token}, {validator_address, @token}],
      %{
        {from_address, @token} => -fee_total,
        {validator_address, @token} => fee_total
      }
    )

    outputs = [
      %{
        id: txid,
        ix: 0,
        from: from_address,
        to: validator_address,
        token: @token,
        value: fee_total,
        reason: @output_reason_fee
      }
    ]

    tx = %{
      id: txid,
      fee: fee_total,
      refundable: false,
      out_count: length(outputs),
      amount: 0
    }

    multi
    |> multi_insert(tx, channel)
    |> Txo.multi_insert_all(:txo, outputs, channel)
    |> Balance.multi_upsert(:balances, outputs, timestamp, channel)
  end

  defp outputs_extract_coinbase!(txid, txos, token) do
    {txos, key_entries, entries, amount, _ix} =
      Enum.reduce(txos, {[], [], %{}, 0, 0}, fn [address, value],
                                                {acc_txos, acc_keys, acc_entries, acc_amount,
                                                 acc_ix} ->
        if value <= 0, do: throw("Output has value zero")
        bin_address = Address.from_text(address)

        output = %{
          id: txid,
          ix: acc_ix,
          token: token,
          to: bin_address,
          reason: @output_reason_coinbase,
          value: value
        }

        entry = {bin_address, token}
        acc_entries = Map.put(acc_entries, entry, value)

        {acc_txos ++ [output], acc_keys ++ [entry], acc_entries, acc_amount + value, acc_ix + 1}
      end)

    token_value = Map.new() |> Map.put(token, amount)

    {txos, key_entries, entries, token_value, amount}
  end

  @doc """
  0 -> by size
  1 -> by percent
  2 -> fixed price
  """
  defp calc_fees(0, fee_amount, _tx_amount, size),
    do: trunc(fee_amount) * size

  defp calc_fees(1, fee_amount, tx_amount, _size),
    do: :math.ceil(tx_amount * (fee_amount / 100)) |> trunc()

  defp calc_fees(2, fee_amount, _tx_amount, _size), do: trunc(fee_amount)

  defp calc_fees(_, _, _, _), do: throw("Wrong fee type")

  defp multi_insert(multi, tx, channel) do
    Ecto.Multi.insert_all(multi, :tx, Tx, [tx],
      prefix: channel,
      returning: false
    )
  end

  def one(txid, params) do
    from(tx in Tx,
      join: ev in Event,
      on: ev.id == tx.id,
      where: tx.id == ^txid,
      select: map_select(),
      limit: 1
    )
    |> Repo.one(prefix: filter_channel(params, Default.channel()))
    |> transform()
  end

  def one_by_hash(hash, params) do
    from(tx in Tx,
      join: ev in Event,
      on: ev.id == tx.id,
      where: ev.hash == ^hash,
      select: map_select(),
      limit: 1
    )
    |> Repo.one(prefix: filter_channel(params, Default.channel()))
    |> transform()
  end

  def all(params) do
    from(tx in Tx, join: ev in Event, on: ev.id == tx.id)
    |> where([_tx, ev], ev.status == @status_complete)
    |> filter_index(params)
    |> filter_select(params)
    |> filter_offset(params)
    |> filter_status(params)
    |> filter_date(params)
    |> filter_limit(params, 50, 100)
    |> sort(params)
    |> Repo.all(prefix: filter_channel(params, Default.channel()))
    |> filter_map()
  end

  defp filter_index(query, %{"hash" => hash}) do
    where(query, [_tx, ev], ev.hash == ^hash)
  end

  defp filter_index(query, %{"block_index" => block_index}) do
    where(query, [_tx, ev], ev.block_index == ^block_index)
  end

  defp filter_index(query, %{"block_height" => block_height}) do
    query
    |> join(:inner, [_tx, ev], b in Block, on: b.index == ev.block_index)
    |> where([_tx, ev, b], b.height == ^block_height)
  end

  defp filter_index(query, %{"q" => q}) do
    binq = Utils.decode16(q)

    where(query, [tx], tx.hash == ^binq)
  end

  defp filter_index(query, _), do: query

  defp filter_status(query, %{"status" => status}) do
    where(query, [_tx, ev], ev.status == ^status)
  end

  defp filter_status(query, _), do: query

  def filter_date(query, %{"date_from" => from_date, "date_to" => to_date}) do
    date_start = Utils.from_date_to_time(from_date, :start, @unit_time)

    date_end = Utils.from_date_to_time(to_date, :end, @unit_time)

    where(query, [_tx, ev], ev.time >= ^date_start and ev.time <= ^date_end)
  end

  def filter_date(query, %{"date_from" => from_date}) do
    date_start = Utils.from_date_to_time(from_date, :start, @unit_time)

    where(query, [_tx, ev], ev.time >= ^date_start)
  end

  def filter_date(query, %{"date_to" => to_date}) do
    date_end = Utils.from_date_to_time(to_date, :end, @unit_time)

    where(query, [_tx, ev], ev.time <= ^date_end)
  end

  def filter_date(query, _), do: query

  defp filter_select(query, _), do: select(query, [tx, ev], map_select())

  defp sort(query, params) do
    case Map.get(params, "sort") do
      "oldest" ->
        order_by(query, [tx], asc: fragment("length(?)", tx.id), asc: tx.id)

      "most_value" ->
        order_by(query, [tx], desc: tx.amount)

      "less_value" ->
        order_by(query, [tx], asc: tx.amount)

      _ ->
        order_by(query, [tx], desc: fragment("length(?)", tx.id), desc: tx.id)
    end
  end

  defp filter_map(data) do
    Enum.map(data, fn x -> transform(x) end)
  end

  defp transform(x) do
    x
  end
end
