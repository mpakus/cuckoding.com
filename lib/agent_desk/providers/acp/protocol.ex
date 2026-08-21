defmodule AgentDesk.Providers.ACP.Protocol do
  @moduledoc """
  Maps ACP session updates and permission requests into normalized events.
  """

  alias AgentDesk.Providers.Event

  @spec from_update(map(), String.t()) :: [Event.t()]
  def from_update(params, provider) when is_map(params) do
    update = Map.get(params, "update") || params
    kind = Map.get(update, "sessionUpdate") || Map.get(update, "type")
    event_from_kind(kind, update, provider)
  end

  defp event_from_kind("agent_message_chunk", update, provider) do
    [Event.new(:message_delta, %{"text" => text_from(update)}, provider)]
  end

  defp event_from_kind("agent_message", update, provider) do
    [Event.new(:message_completed, %{"text" => text_from(update)}, provider)]
  end

  defp event_from_kind("tool_call", update, provider) do
    [Event.new(:tool_started, stringify(update), provider)]
  end

  defp event_from_kind("tool_call_update", update, provider) do
    [Event.new(:tool_completed, stringify(update), provider)]
  end

  defp event_from_kind("file_edit", update, provider) do
    [Event.new(:file_change, stringify(update), provider)]
  end

  defp event_from_kind("usage", update, provider) do
    [Event.new(:usage, stringify(update), provider)]
  end

  defp event_from_kind(_kind, _update, _provider), do: []

  @spec from_permission(term(), map(), String.t()) :: Event.t()
  def from_permission(id, params, provider) do
    Event.new(
      :approval_requested,
      %{
        "request_id" => to_string(id),
        "action" =>
          Map.get(params, "action") || get_in(params, ["toolCall", "title"]) || "permission",
        "summary" => Map.get(params, "summary") || inspect(Map.get(params, "toolCall")),
        "permissions" => Map.get(params, "permissions", [])
      },
      provider
    )
  end

  defp text_from(update) do
    cond do
      is_binary(update["text"]) ->
        update["text"]

      is_map(update["content"]) ->
        update["content"]["text"] || ""

      true ->
        ""
    end
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
