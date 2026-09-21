defmodule Cuckoding.Adapters.OutputParser do
  @moduledoc "Reads one bounded structured result from a provider-owned JSONL artifact."

  alias Cuckoding.Adapters.Types

  @maximum_bytes 1_048_576
  @maximum_rows 2_000
  @maximum_activity_rows 50_000
  @maximum_messages 5_000

  @doc "Reads public agent messages from the complete redacted process log."
  def activity_events("fake", _result), do: {:ok, []}

  def activity_events(adapter, %{artifact_path: path})
      when adapter in ~w(codex claude_code cursor_agent) and is_binary(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular}} -> read_activity(path, adapter)
      _other -> error(:activity_log_missing)
    end
  rescue
    File.Error -> error(:activity_log_missing)
    _error -> error(:malformed_activity_log)
  end

  def activity_events(_adapter, _result), do: {:ok, []}

  defp read_activity(path, adapter) do
    path
    |> File.stream!()
    |> Stream.with_index(1)
    |> Enum.reduce_while({:ok, [], 0}, &activity_line(&1, &2, adapter))
    |> case do
      {:ok, events, _count} -> {:ok, Enum.reverse(events)}
      error -> error
    end
  end

  defp activity_line({line, sequence}, {:ok, events, count} = state, adapter) do
    cond do
      sequence > @maximum_activity_rows or count >= @maximum_messages or
          byte_size(line) > @maximum_bytes ->
        {:halt, error(:activity_capture_limit)}

      String.trim(line) == "" or
          (adapter == "codex" and sequence == 1 and
             String.trim(line) == "Reading additional input from stdin...") ->
        {:cont, state}

      true ->
        decode_activity_line(line, sequence, adapter, events, count)
    end
  end

  defp decode_activity_line(line, sequence, adapter, events, count) do
    case Jason.decode(line) do
      {:ok, row} when is_map(row) ->
        case decode_activity(adapter, row, sequence) do
          nil -> {:cont, {:ok, events, count}}
          event -> {:cont, {:ok, [event | events], count + 1}}
        end

      _other ->
        {:halt, error(:malformed_activity_log)}
    end
  end

  defp decode_activity(adapter, row, sequence) do
    module =
      case adapter do
        "codex" -> Cuckoding.Adapters.Codex
        "claude_code" -> Cuckoding.Adapters.ClaudeCode
        "cursor_agent" -> Cuckoding.Adapters.CursorAgent
      end

    case module.decode_event(row, sequence: sequence) do
      {:ok, %Types.Event{type: "activity.summary", public_summary: summary} = event}
      when is_binary(summary) and summary != "" ->
        summary = event.public_summary

        summary =
          if String.length(summary) > 10_000,
            do: String.slice(summary, 0, 10_000) <> "… [see full process log]",
            else: summary

        %{event | event_id: "#{event.event_id}:#{sequence}", public_summary: summary}

      _other ->
        nil
    end
  end

  def extract("fake", %{structured_output: output}) when is_map(output), do: {:ok, output}

  def extract(adapter, %{artifact_path: path})
      when adapter in ~w(codex claude_code cursor_agent) and is_binary(path) do
    with {:ok, rows} <- rows(path, adapter) do
      extract_rows(adapter, rows)
    end
  end

  def extract(_adapter, _result), do: error(:structured_output_missing)

  defp rows(path, adapter) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} when size <= @maximum_bytes ->
        with {:ok, contents} <- File.read(path),
             lines = contents |> String.split("\n", trim: true) |> drop_known_prelude(adapter),
             true <- length(lines) <= @maximum_rows,
             {:ok, rows} <- decode_rows(lines) do
          {:ok, rows}
        else
          false -> error(:structured_output_too_large)
          {:error, %Types.Error{} = reason} -> {:error, reason}
          {:error, _reason} -> error(:malformed_output)
        end

      {:ok, %{type: :regular}} ->
        error(:structured_output_too_large)

      _other ->
        error(:structured_output_missing)
    end
  end

  defp drop_known_prelude(["Reading additional input from stdin..." | lines], "codex"),
    do: lines

  defp drop_known_prelude(lines, _adapter), do: lines

  defp decode_rows(lines) do
    Enum.reduce_while(lines, {:ok, []}, fn line, {:ok, rows} ->
      case Jason.decode(line) do
        {:ok, row} when is_map(row) -> {:cont, {:ok, [row | rows]}}
        _other -> {:halt, error(:malformed_output)}
      end
    end)
    |> case do
      {:ok, rows} -> {:ok, Enum.reverse(rows)}
      error -> error
    end
  end

  defp extract_rows("codex", rows) do
    rows
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "item.completed", "item" => %{"type" => "agent_message", "text" => text}}
      when is_binary(text) ->
        Jason.decode(text)

      _other ->
        nil
    end)
    |> decoded()
  end

  defp extract_rows("claude_code", rows) do
    rows
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "result", "subtype" => "success", "structured_output" => output}
      when is_map(output) ->
        {:ok, output}

      _other ->
        nil
    end)
    |> decoded()
  end

  defp extract_rows("cursor_agent", rows) do
    rows
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{"type" => "result", "subtype" => "success", "structured_output" => output}
      when is_map(output) ->
        {:ok, output}

      %{"type" => "result", "subtype" => "success", "result" => output}
      when is_binary(output) ->
        Jason.decode(output)

      _other ->
        nil
    end)
    |> decoded()
  end

  defp decoded({:ok, output}) when is_map(output), do: {:ok, output}
  defp decoded(_other), do: error(:malformed_output)

  defp error(code), do: {:error, Types.Error.new(code, :malformed_output, false)}
end
