defmodule CuckodingWeb.CorrelationId do
  @moduledoc false

  import Plug.Conn
  require Logger

  def init(options), do: options

  def call(conn, _options) do
    correlation_id = conn |> get_resp_header("x-request-id") |> List.first()
    Logger.metadata(correlation_id: correlation_id)
    put_resp_header(conn, "x-correlation-id", correlation_id)
  end
end
