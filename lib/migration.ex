defmodule Ipncore.Migration do
  alias Ipncore.{Channel, Repo}
  import Ecto.Query

  alias Ipncore.Migration.{
    Blockchain,
    System
  }

  @prefix "sys"
  @otp_app :ipncore
  @channel Application.get_env(@otp_app, :channel)

  def start do
    migration_version = Application.get_env(@otp_app, :migration_version)

    if not Repo.schema_exists?(@prefix) do
      System.build(%{"version" => migration_version})
    end

    Channel.all()
    |> cond do
      [] ->
        Channel.new(%{
          "id" => @channel,
          "pubkey" => PlatformOwner.pubkey(),
          "time" => :erlang.system_time(:millisecond)
        })
        |> Repo.insert(prefix: @prefix)

        if not Repo.schema_exists?(@channel) do
          Blockchain.build(%{"channel" => @channel, "version" => migration_version})
        end

      channels ->
        for channel <- channels do
          if not Repo.schema_exists?(channel.id) do
            Blockchain.build(%{"channel" => channel.id, "version" => migration_version})
          end
        end
    end
  end

  # def start do
  #   migration_version = Application.get_env(@otp_app, :migration_version)

  #   if not Repo.schema_exists?("sys") do
  #     System.build(%{"version" => migration_version})
  #   else
  #     current_version =
  #       from(env in "env", where: env.key == "version", select: env.value, limit: 1)
  #       |> Repo.one(prefix: "sys")
  #       |> String.to_integer()

  #     if migration_version > current_version do
  #       System.build(%{"version" => migration_version})
  #     end

  #     channels = Channel.all()

  #     for channel <- channels do
  #       if Repo.schema_exists?(channel.id) do
  #         if migration_version > channel.vsn do
  #           Blockchain.build(%{"channel" => channel.id, "version" => migration_version})
  #         end
  #       else
  #         Blockchain.build(%{"channel" => channel.id, "version" => migration_version})
  #       end
  #     end
  #   end
  # end
end
