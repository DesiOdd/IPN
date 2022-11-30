defmodule Ipncore.Explorer.Router do
  use Plug.Router

  import Ipncore.WebTools, only: [json: 2, send_error: 2, send_result: 2]
  import Ipnutils.Filters
  import Ipncore.PostDeliver, only: [serve_video: 3]
  alias Ipncore.{Block, Channel, Event, Tx, Txo, Token, Balance, Chain, Validator}

  if Mix.env() == :dev do
    use Plug.Debugger
  end

  use Plug.ErrorHandler

  plug(:match)
  plug(:dispatch)

  get "/blocks" do
    params = conn.params

    resp = Block.all(params)

    send_result(conn, resp)
  end

  get "/channel" do
    params = conn.params
    resp = Block.all(params)
    send_result(conn, resp)
  end

  get "/txs" do
    params = conn.params
    resp = Tx.all(params)
    send_result(conn, resp)
  end

  get "/txo" do
    params = conn.params
    resp = Txo.all(params)
    send_result(conn, resp)
  end

  # get "/txi" do
  #   params = conn.params
  #   resp = Txi.all(params)
  #   send_result(conn, resp)
  # end

  get "/tokens" do
    params = conn.params
    resp = Token.all(params)
    send_result(conn, resp)
  end

  get "/token/:token/:channel" do
    resp = Token.one(token, channel, conn.params)
    send_result(conn, resp)
  end

  get "/validators" do
    params = conn.params
    resp = Validator.all(params)
    send_result(conn, resp)
  end

  get "/validators/:hostname/:channel" do
    resp = Validator.one(hostname, channel, conn.params)
    send_result(conn, resp)
  end

  get "/search" do
    params = conn.params

    case params do
      %{"q" => query} ->
        resp =
          cond do
            Regex.match?(Const.Regex.only_digits(), query) ->
              case Block.get(%{"height" => query}) do
                nil ->
                  nil

                b ->
                  %{"id" => b.height, "type" => "block"}
              end

            Regex.match?(Const.Regex.hash256(), query) ->
              hash = Base.decode16!(query, case: :mixed)

              case Block.get(%{"hash" => hash}) do
                nil ->
                  case Tx.one_by_hash(hash, params) do
                    nil ->
                      nil

                    tx ->
                      %{"id" => tx.index, "type" => "tx"}
                  end

                block ->
                  %{"id" => block.height, "type" => "block"}
              end

            Regex.match?(Const.Regex.address(), query) ->
              address = Base58Check.decode(query)

              case Balance.fetch_balance(address, Default.token(), Default.channel()) do
                nil ->
                  index = Event.decode_id(query)
                  Tx.one(index, params)

                x ->
                  %{"id" => x.address, "type" => "balance"}
              end

            Regex.match?(Const.Regex.base62(), query) ->
              index = Event.decode_id(query)

              case Tx.one(index, params) do
                nil ->
                  nil

                tx ->
                  %{"id" => tx.index, "type" => "tx"}
              end

            true ->
              nil
          end

        send_result(conn, resp)

      _ ->
        send_resp(conn, 400, "")
    end
  end

  get "/balance/:address58/:token" do
    address = Base58Check.decode(address58)
    resp = Balance.fetch_balance(address, token, Default.channel())
    send_result(conn, resp)
  end

  get "/balance/:address58" do
    address = Base58Check.decode(address58)
    resp = Balance.all_balance(address, conn.params)
    send_result(conn, resp)
  end

  get "/activity/:address58" do
    resp = Balance.activity(address58, conn.params)

    send_result(conn, resp)
  end

  get "/channel/:channel_id" do
    resp =
      case Channel.get(channel_id) do
        nil ->
          send_error(conn, 404)

        channel ->
          json(conn, channel)
      end

    send_result(conn, resp)
  end

  get "/status/:channel_id" do
    genesis_time = Chain.genesis_time()
    channel = Channel.get(channel_id)
    token = Token.one(Default.token(), channel_id)

    resp = %{
      blocks: channel.block_count,
      genesis_time: genesis_time,
      iit: Chain.get_time(),
      coins: token.supply,
      tx_count: channel.tx_count,
      next_index: Chain.next_index()
    }

    send_result(conn, resp)
  end

  get "/block/:hash16" when byte_size(hash16) == 64 do
    hash = Base.decode16!(hash16, case: :mixed)

    resp = Block.get(%{"hash" => hash})

    send_result(conn, resp)
  end

  get "/block/height/:height" do
    resp = Block.get(%{"height" => height})

    send_result(conn, resp)
  end

  get "/tx/:hash16" when byte_size(hash16) == 64 do
    hash = Base.decode16!(hash16, case: :mixed)

    resp = Tx.one(hash, conn.params)

    send_result(conn, resp)
  end

  get "/events" do
    resp = Event.all(conn.params)
    send_result(conn, resp)
  end

  get "/event/:evid" do
    id = Event.decode_id(evid)

    resp = Event.one(id, filter_channel(conn.params, Default.channel()))

    send_result(conn, resp)
  end

  # get "/tx/:txid" do
  #   id = Event.decode_id(txid)

  #   resp = Tx.one(id, conn.params)

  #   send_result(conn, resp)
  # end

  # post "/utxo" do
  #   params = conn.params

  #   case params do
  #     %{"address" => address, "channel" => channel, "token" => token, "total" => total} = params ->
  #       IO.inspect(params)

  #       x =
  #         if(is_list(address),
  #           do: Enum.map(address, &Base58Check.decode(&1)),
  #           else: [Base58Check.decode(address)]
  #         )

  #       result = Utxo.fetch_by_address_multi(x, token, total, channel)
  #       json(conn, result)

  #     %{"address" => address, "token" => token, "total" => total} = params ->
  #       IO.inspect(params)

  #       x =
  #         if(is_list(address),
  #           do: Enum.map(address, &Base58Check.decode(&1)),
  #           else: [Base58Check.decode(address)]
  #         )

  #       result = Utxo.fetch_by_address(x, token, total, Default.channel())
  #       json(conn, result)

  #     _ ->
  #       send_error(conn, 400)
  #   end
  # end

  # post "/tx" do
  #   # IO.puts(inspect(conn))
  #   params = conn.params
  #   IO.inspect(params)

  #   case Tx.begin_processing(params) do
  #     {:ok, tx} ->
  #       # Ipncore.IMP.Client.publish("tx:" <> tx.index, params)
  #       json(conn, %{"index" => Tx.encode_index(tx.index)})

  #     err ->
  #       send_error(conn, err)
  #   end
  # end

  post "/event" do
    IO.inspect(conn)
    %{"_json" => body} = conn.params
    # IO.inspect(body)
    case body do
      [version, type_name, time, event_body, address, sig64] ->
        Event.check(version, type_name, time, event_body, address, sig64)

      [version, type_name, time, event_body, sig64] ->
        Event.check(version, type_name, time, event_body, sig64)
    end
    |> case do
      {:ok, event_id} ->
        # Ipncore.IMP.Client.publish("tx:" <> tx.index, params)
        json(conn, %{"id" => Base.encode16(event_id, case: :lower)})

      {:error, err_message} ->
        send_resp(conn, 400, err_message)

      err_message ->
        # send_error(conn, err_message)
        send_resp(conn, 400, err_message)
    end
  end

  # serve posts
  get "/p/:id/:stream/:segment" do
    base = ["http://", Application.get_env(:ipncore, :central)] |> IO.iodata_to_binary()

    url =
      [base, "p", id, stream, segment]
      |> Path.join()

    headers = [
      {"cache-control", "private, max-age=21600"},
      {"content-type", "video/iso.segment"},
      {"address", Default.address58()}
    ]

    serve_video(conn, url, headers)
  end

  get "/p/:id/:manifest" do
    base = ["http://", Application.get_env(:ipncore, :central)] |> IO.iodata_to_binary()

    url =
      [base, "p", id, manifest]
      |> Path.join()

    headers = [
      {"cache-control", "private, max-age=21600"},
      {"content-type", "application/dash+xml"},
      {"address", Default.address58()}
    ]

    serve_video(conn, url, headers)
  end

  match _ do
    send_resp(conn, 404, "oops")
  end

  defp handle_errors(conn, %{kind: _kind, reason: _reason, stack: _stack}) do
    send_resp(conn, conn.status, "Something went wrong")
  end
end
