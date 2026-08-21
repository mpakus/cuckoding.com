defmodule AgentDesk.MCP.Stdio do
  @moduledoc false

  alias AgentDesk.MCP.Protocol
  alias AgentDesk.Security.Capability

  def main(_args) do
    :ok = :io.setopts(:standard_io, binary: true, encoding: :latin1)

    case Capability.authenticate(System.get_env("AGENTDESK_CAPABILITY_TOKEN")) do
      {:ok, session} -> loop(session)
      {:error, _} -> System.halt(1)
    end
  end

  defp loop(session) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line ->
        respond(session, String.trim_trailing(to_string(line), "\n"))
        loop(session)
    end
  end

  defp respond(_session, ""), do: :ok

  defp respond(session, line) do
    case Jason.decode(line) do
      {:ok, msg} ->
        payload =
          case Protocol.handle(session, msg) do
            {:ok, result} -> result
            {:error, error} -> error
          end

        IO.binwrite(:stdio, Jason.encode!(payload) <> "\n")

      {:error, _} ->
        :ok
    end
  end
end
