defmodule WalletVerifierChannel do
  use Channel,
    server: :verifiers,
    channel: "wallet"

  def init(args) do
    PubSub.subscribe(@pubsub_server, @channel)
    {:ok, args}
  end

  @impl true
  def handle_info({"new", account}, state) do
    AccountStore.insert(account)
    {:noreply, state}
  end

  def handle_info({"sub", %{id: account_id, validator: validator_id}}, state) do
    WalletStore.update(%{validator: validator_id}, id: account_id)
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end