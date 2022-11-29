defmodule Ipncore.DNSS do
  @moduledoc """
  DNS.Server
  """
  @behaviour Ipncore.DNS.Server
  use Ipncore.DNS.Server
  #   alias Ipncore.DnsRecord
  require Logger

  def handle(record, _cl) do
    Logger.info(fn -> "#{inspect(record)}" end)
    query = hd(record.qdlist)
    IO.inspect(query)

    result =
      case query.type do
        :a -> {150, 0, 0, 1}
        :aaaa -> {127, 0, 0, 0, 0, 0, 0, 1}
        :cname -> 'your.domain.com'
        :txt -> ['your txt value']
        # :ptr -> '150.0.0.in-addr.arpa'
        _ -> ''
      end

    # {value, ttl} = DnsRecord.lookup(query.domain, query.type)

    resource = %DNS.Resource{
      domain: query.domain,
      class: query.class,
      type: query.type,
      ttl: 0,
      data: result
    }

    IO.inspect(resource)

    %{record | anlist: [resource], header: %{record.header | qr: true}}
  end
end
