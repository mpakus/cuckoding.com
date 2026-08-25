defmodule AgentDesk.Activity do
  @moduledoc """
  Groups streamed provider tokens into readable activity items.
  """

  alias AgentDesk.Providers.Event

  @agent_types MapSet.new([
                 :message_delta,
                 :message_completed,
                 "message_delta",
                 "message_completed"
               ])
  @reasoning_types MapSet.new([:reasoning_delta, "reasoning_delta"])
  @tool_types MapSet.new([
                :tool_started,
                :tool_completed,
                "tool_started",
                "tool_completed"
              ])

  @spec coalesce([map()]) :: [map()]
  def coalesce(items) when is_list(items) do
    items
    |> Enum.reduce([], &push_item/2)
    |> Enum.reverse()
  end

  @spec coalesce_events([Event.t()]) :: [Event.t()]
  def coalesce_events(events) when is_list(events) do
    events
    |> Enum.reduce([], &push_event/2)
    |> Enum.reverse()
  end

  @spec mergeable?(term(), term()) :: boolean()
  def mergeable?(current, incoming) do
    case {stream_kind(current), stream_kind(incoming)} do
      {nil, _} -> false
      {_, nil} -> false
      {kind, kind} -> not completed?(current)
      _ -> false
    end
  end

  @spec open_stream?(term()) :: boolean()
  def open_stream?(item) do
    type_of(item) in [
      :message_delta,
      :reasoning_delta,
      "message_delta",
      "reasoning_delta"
    ]
  end

  @spec merge(map(), map()) :: map()
  def merge(current, incoming) when is_map(current) and is_map(incoming) do
    if match?({:tool, _}, stream_kind(current)) do
      merge_tool(current, incoming)
    else
      text = combined_text(current, incoming)

      current
      |> Map.put(:text, text)
      |> Map.put(:type, preferred_type(type_of(current), type_of(incoming)))
      |> Map.put(:payload, put_text(payload_of(current), text))
    end
  end

  @spec caption(term()) :: String.t() | nil
  def caption(item) when is_map(item), do: caption(type_of(item), payload_of(item))

  @spec caption(term(), map() | nil) :: String.t() | nil
  def caption(type, payload) when is_atom(type), do: caption(Atom.to_string(type), payload || %{})

  def caption("provider_error", payload) do
    present(payload["message"]) || provider_reason(payload["reason"]) || present(payload["text"]) ||
      "Provider error"
  end

  def caption("stderr", payload) do
    present(payload["text"]) || present(payload["message"]) || present(payload["reason"])
  end

  def caption(type, payload) when type in ["tool_started", "tool_completed"] do
    tool_caption(payload || %{})
  end

  def caption("approval_requested", payload) do
    cond do
      present(payload["summary"]) && not dump?(payload["summary"]) ->
        String.trim(payload["summary"])

      present(payload["title"]) ->
        payload["title"]

      present(payload["action"]) && payload["action"] != "permission" ->
        payload["action"]

      true ->
        "The agent asked for permission."
    end
  end

  def caption(type, payload) when is_binary(type) do
    present(payload["text"]) || present(payload["delta"]) || present(payload["summary"]) ||
      present(payload["message"]) || present(payload["reason"]) || present(payload["title"]) ||
      humanize(type)
  end

  def caption(_, _), do: nil

  @spec meaningful?(term(), map() | nil) :: boolean()
  def meaningful?(type, payload) when type in [:tool_started, :tool_completed] do
    tool_caption(payload || %{}) != nil
  end

  def meaningful?(type, payload) when type in ["tool_started", "tool_completed"] do
    tool_caption(payload || %{}) != nil
  end

  def meaningful?(:provider_error, payload),
    do: present(caption("provider_error", payload)) != nil

  def meaningful?("provider_error", payload),
    do: present(caption("provider_error", payload)) != nil

  def meaningful?(:stderr, payload), do: present(caption("stderr", payload)) != nil
  def meaningful?("stderr", payload), do: present(caption("stderr", payload)) != nil

  def meaningful?(:approval_requested, payload) do
    caption = caption("approval_requested", payload)
    present(caption) != nil and not dump?(caption)
  end

  def meaningful?("approval_requested", payload), do: meaningful?(:approval_requested, payload)

  def meaningful?(_, _), do: true

  @spec join(String.t(), String.t()) :: String.t()
  def join(acc, chunk) when is_binary(acc) and is_binary(chunk) do
    cond do
      chunk == "" -> acc
      acc == "" -> chunk
      glue?(acc, chunk) -> acc <> chunk
      true -> acc <> " " <> chunk
    end
  end

  def join(acc, _), do: acc

  defp push_item(item, []), do: [item]

  defp push_item(item, [head | rest] = acc) do
    if mergeable?(head, item), do: [merge(head, item) | rest], else: [item | acc]
  end

  defp push_event(event, []), do: [event]

  defp push_event(event, [head | rest] = acc) do
    if mergeable?(head, event), do: [merge_event(head, event) | rest], else: [event | acc]
  end

  defp merge_event(%Event{} = current, %Event{} = incoming) do
    if match?({:tool, _}, stream_kind(current)) do
      payload = Map.merge(current.payload || %{}, incoming.payload || %{})
      type = preferred_event_type(current.type, incoming.type)
      %{current | type: type, payload: Map.put(payload, "text", tool_caption(payload))}
    else
      text = combined_text(current, incoming)
      type = preferred_event_type(current.type, incoming.type)

      %{current | type: type, payload: put_text(current.payload, text)}
    end
  end

  defp combined_text(current, incoming) do
    current_text = text_of(current)
    incoming_text = text_of(incoming)

    if completed?(incoming) and String.length(incoming_text) >= String.length(current_text) do
      incoming_text
    else
      join(current_text, incoming_text)
    end
  end

  defp stream_kind(item) do
    type = type_of(item)

    cond do
      type in @agent_types -> :agent
      type in @reasoning_types -> :reasoning
      type in @tool_types -> tool_kind(item)
      true -> nil
    end
  end

  defp tool_kind(item) do
    id = payload_of(item)["toolCallId"]
    if is_binary(id) and id != "", do: {:tool, id}, else: nil
  end

  defp merge_tool(current, incoming) do
    payload = Map.merge(payload_of(current), payload_of(incoming))
    type = preferred_type(type_of(current), type_of(incoming))
    text = tool_caption(payload)

    current
    |> Map.put(:payload, payload)
    |> Map.put(:type, type)
    |> Map.put(:text, text)
  end

  defp tool_caption(payload) when is_map(payload) do
    title = present(payload["title"]) || present(payload["tool"]) || present(payload["kind"])
    reason = present(payload["reason"]) || present(payload["message"])
    status = present(payload["status"])

    cond do
      (failed?(status) and title) && reason -> "#{title}: #{reason}"
      failed?(status) and reason -> reason
      failed?(status) and title -> "#{title} failed"
      title -> title
      reason -> reason
      true -> nil
    end
  end

  defp tool_caption(_), do: nil

  defp failed?(status) when status in ["failed", "error", "cancelled"], do: true
  defp failed?(_), do: false

  defp provider_reason("handshake_timeout"),
    do: "Provider handshake timed out. Use Resume, then send the prompt again."

  defp provider_reason(reason) when is_binary(reason), do: present(reason)
  defp provider_reason(_), do: nil

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

  defp humanize(type) when is_binary(type), do: String.replace(type, "_", " ")
  defp humanize(_), do: nil

  defp type_of(%Event{type: type}), do: type
  defp type_of(%{type: type}), do: type
  defp type_of(%{"type" => type}), do: type
  defp type_of(_), do: nil

  defp payload_of(%Event{payload: payload}) when is_map(payload), do: payload
  defp payload_of(%{payload: payload}) when is_map(payload), do: payload
  defp payload_of(%{"payload" => payload}) when is_map(payload), do: payload
  defp payload_of(_), do: %{}

  defp text_of(item) when is_map(item) do
    payload = payload_of(item)

    cond do
      is_binary(Map.get(item, :text)) -> Map.get(item, :text)
      is_binary(Map.get(item, "text")) -> Map.get(item, "text")
      is_binary(payload["text"]) -> payload["text"]
      is_binary(payload["delta"]) -> payload["delta"]
      is_binary(payload["summary"]) -> payload["summary"]
      true -> ""
    end
  end

  defp text_of(_), do: ""

  defp put_text(payload, text) when is_map(payload), do: Map.put(payload, "text", text)

  defp completed?(item) do
    type_of(item) in [
      :message_completed,
      "message_completed",
      :tool_completed,
      "tool_completed"
    ]
  end

  defp preferred_type(current, incoming) do
    if completed_type?(incoming) or completed_type?(current) do
      stringify(incoming_or(current, incoming, &completed_type?/1))
    else
      stringify(current)
    end
  end

  defp preferred_event_type(current, incoming) do
    cond do
      incoming in [:message_completed, :tool_completed] -> incoming
      current in [:message_completed, :tool_completed] -> current
      true -> current
    end
  end

  defp incoming_or(current, incoming, pred) do
    cond do
      pred.(incoming) -> incoming
      pred.(current) -> current
      true -> incoming
    end
  end

  defp completed_type?(type),
    do: type in [:message_completed, "message_completed", :tool_completed, "tool_completed"]

  defp stringify(type) when is_atom(type), do: Atom.to_string(type)
  defp stringify(type) when is_binary(type), do: type

  defp glue?(acc, chunk) do
    String.starts_with?(chunk, [" ", "\n", "\t"]) or
      String.ends_with?(acc, [" ", "\n", "\t"]) or
      punctuation?(chunk)
  end

  defp punctuation?(<<first::utf8, _::binary>>) do
    first in [?., ?,, ?!, ??, ?;, ?:, ?), ?], ?}, ?', ?", ?%]
  end

  defp punctuation?(_), do: false
end
