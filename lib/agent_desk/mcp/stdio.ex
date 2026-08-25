defmodule AgentDesk.MCP.Stdio do
  @moduledoc false

  alias AgentDesk.MCP.Protocol
  alias AgentDesk.Security.Capability

  def main(_args) do
    :ok = :io.setopts(:standard_io, binary: true, encoding: :latin1)
    token = System.get_env("AGENTDESK_CAPABILITY_TOKEN")

    case Capability.authenticate(token) do
      {:ok, _session} -> loop(token)
      {:error, _} -> System.halt(1)
    end
  end

  defp loop(token) do
    case IO.read(:stdio, :line) do
      :eof ->
        :ok

      {:error, _} ->
        :ok

      line ->
        case Capability.authenticate(token) do
          {:ok, session} ->
            respond(session, String.trim_trailing(to_string(line), "\n"))
            loop(token)

          {:error, _reason} ->
            System.halt(1)
        end
    end
  end

  defp respond(_session, ""), do: :ok

  defp respond(session, line) do
    case Jason.decode(line) do
      {:ok, msg} when is_map(msg) ->
        if Map.has_key?(msg, "id") do
          payload =
            case Protocol.handle(session, msg) do
              {:ok, result} -> result
              {:error, error} -> error
            end

          IO.binwrite(:stdio, Jason.encode!(payload) <> "\n")
        else
          _ = Protocol.handle(session, msg)
          :ok
        end

      {:error, _} ->
        :ok
    end
  end
end
