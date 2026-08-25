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
    [Event.new(:tool_started, tool_payload(update), provider)]
  end

  defp event_from_kind("tool_call_update", update, provider) do
    type = if tool_done?(update), do: :tool_completed, else: :tool_started
    [Event.new(type, tool_payload(update), provider)]
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
    tool = stringify(Map.get(params, "toolCall") || %{})
    action = present(Map.get(params, "action")) || present(tool["title"]) || "permission"

    Event.new(
      :approval_requested,
      %{
        "request_id" => to_string(id),
        "action" => action,
        "summary" => permission_summary(params, tool, action),
        "title" => present(tool["title"]) || action,
        "permissions" => Map.get(params, "permissions", [])
      },
      provider
    )
  end

  defp tool_payload(update) when is_map(update) do
    raw = stringify(update)
    nested = stringify(raw["toolCall"] || %{})
    title = present(raw["title"]) || present(nested["title"])
    kind = present(raw["kind"]) || present(nested["kind"])
    status = present(raw["status"]) || present(nested["status"])
    reason = present(raw["reason"]) || present(nested["reason"]) || content_reason(raw)

    %{
      "toolCallId" => raw["toolCallId"] || nested["toolCallId"],
      "title" => title,
      "kind" => kind,
      "status" => status,
      "tool" => title || kind,
      "reason" => reason,
      "path" => location_path(raw) || location_path(nested),
      "content" => raw["content"] || nested["content"]
    }
    |> reject_blank()
  end

  defp tool_done?(update) when is_map(update) do
    status =
      update["status"] || get_in(update, ["toolCall", "status"]) ||
        update[:status]

    status in ["completed", "failed", "cancelled", "error"]
  end

  defp permission_summary(params, tool, action) do
    cond do
      dump?(params["summary"]) -> present(tool["title"]) || action
      present(params["summary"]) -> params["summary"]
      present(tool["title"]) -> tool["title"]
      true -> "The agent asked for permission to #{action}."
    end
  end

  defp content_reason(payload) do
    payload
    |> Map.get("content")
    |> List.wrap()
    |> Enum.map(&piece_text/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
    |> present()
  end

  defp piece_text(text) when is_binary(text), do: present(text)
  defp piece_text(%{"text" => text}) when is_binary(text), do: present(text)
  defp piece_text(%{"content" => %{"text" => text}}) when is_binary(text), do: present(text)
  defp piece_text(%{"content" => content}) when is_binary(content), do: present(content)
  defp piece_text(_), do: nil

  defp location_path(%{"locations" => [%{"path" => path} | _]}) when is_binary(path), do: path
  defp location_path(%{"path" => path}) when is_binary(path), do: path
  defp location_path(_), do: nil

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

  defp stringify(_), do: %{}

  defp reject_blank(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) or value == "" end)
  end

  defp present(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp present(_), do: nil

  defp dump?(text) when is_binary(text) do
    trimmed = String.trim(text)
    String.starts_with?(trimmed, ["%{", "{", "#"])
  end

  defp dump?(_), do: false
end
