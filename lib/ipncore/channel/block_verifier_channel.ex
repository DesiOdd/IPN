defmodule BlockVerifierChannel do
  use Channel,
    server: :verifiers,
    channel: "block"

  @otp_app :ipncore
  @send_to :miner
  @file_extension "erl"

  def init(args) do
    PubSub.subscribe(@pubsub_server, @channel)
    PubSub.subscribe(@pubsub_server, "#{@channel}:#{node()}")
    Logger.debug("sub: #{@channel}:#{node()}")
    {:ok, args}
  end

  @impl true
  def handle_info(
        {"fetch",
         %{
           hash: hash,
           creator: vid,
           height: height
         } = block, %{hostname: hostname} = validator, _origin},
        state
      ) do
    hash16 = Base.encode16(hash)
    Logger.debug("block.fetch #{hash16}")
    decode_dir = Application.get_env(@otp_app, :decode_dir)
    filename = "#{vid}.#{height}.#{@file_extension}"
    block_path = Path.join(decode_dir, filename)
    myip = Application.get_env(@otp_app, :hostname)

    try do
      unless File.exists?(block_path) do
        url = "https://#{hostname}/v1/download/block/#{vid}/#{height}"
        {:ok, _path} = Curl.download_block(url, block_path)
      end

      BlockTimer.verify_block!(block, validator)

      PubSub.broadcast(
        @send_to,
        "block:#{hash16}",
        {"valid", :ok, block, myip}
      )
    rescue
      _ -> PubSub.broadcast(@send_to, "block:#{hash16}", {"valid", :error, block, myip})
    end

    {:noreply, state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end
end
