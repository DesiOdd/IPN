defmodule Ipncore.DNS.Worker do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, nil)

  @impl true
  def init(_), do: {:ok, nil}

  @impl true
  def handle_call({:udp, socket, ip, port, data, state}, _from, local_state) do
    result =
      case Ipncore.DNS.handle(data, socket) do
        nil ->
          :ok

        response ->
          :gen_udp.send(state.socket, ip, port, response)
      end

    {:reply, result, local_state}
  end

  def handle_call({:tls, socket, rest}, _from, state) do
    result = Ipncore.DNS.handle(rest, 0)
    ThousandIsland.Socket.send(socket, <<byte_size(result)::16>> <> result)

    {:reply, result, state}
  end
end