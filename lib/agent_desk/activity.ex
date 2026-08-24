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
    text = combined_text(current, incoming)

    current
    |> Map.put(:text, text)
    |> Map.put(:type, preferred_type(type_of(current), type_of(incoming)))
    |> Map.put(:payload, put_text(payload_of(current), text))
  end

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
    text = combined_text(current, incoming)
    type = preferred_event_type(current.type, incoming.type)

    %{current | type: type, payload: put_text(current.payload, text)}
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
      true -> nil
    end
  end

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
    type_of(item) in [:message_completed, "message_completed"]
  end

  defp preferred_type(current, incoming) do
    if completed_type?(incoming) or completed_type?(current) do
      stringify(incoming_or(current, incoming, &completed_type?/1))
    else
      stringify(current)
    end
  end

  defp preferred_event_type(current, incoming) do
    if incoming == :message_completed or current == :message_completed do
      :message_completed
    else
      current
    end
  end

  defp incoming_or(current, incoming, pred) do
    cond do
      pred.(incoming) -> incoming
      pred.(current) -> current
      true -> incoming
    end
  end

  defp completed_type?(type), do: type in [:message_completed, "message_completed"]

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
