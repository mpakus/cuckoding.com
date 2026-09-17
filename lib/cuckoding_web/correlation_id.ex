defmodule CuckodingWeb.CorrelationId do
  @moduledoc false

  import Plug.Conn

  def init(options), do: options

  def call(conn, _options) do
    correlation_id = conn |> get_resp_header("x-request-id") |> List.first()
    Cuckoding.Correlation.put(correlation_id)
    put_resp_header(conn, "x-correlation-id", correlation_id)
  end
end
