defmodule Boss.Agents.Cursor do
  @moduledoc false

  def implement_args(selection \\ %{}) do
    ["--print", "--force", "--output-format", "json", "--trust"] ++ model_flags(selection)
  end

  def args(selection \\ %{}) do
    [
      "--print",
      "--output-format",
      "json",
      "--mode",
      "ask",
      "--sandbox",
      "enabled",
      "--trust"
    ] ++ model_flags(selection)
  end

  defp model_flags(%{model_id: model}) when is_binary(model) and model != "",
    do: ["--model", model]

  defp model_flags(%{"model_id" => model}) when is_binary(model) and model != "",
    do: ["--model", model]

  defp model_flags(_), do: ["--model", "auto"]

  def report(output) when is_binary(output) do
    with true <- String.valid?(output),
         {:ok, envelope} when is_map(envelope) <- Jason.decode(output),
         true <- envelope["type"] == "result",
         true <- envelope["subtype"] == "success",
         true <- envelope["is_error"] == false,
         text when is_binary(text) <- envelope["result"] do
      {:ok, json_object(text), summary(envelope)}
    else
      _ -> :error
    end
  end

  def report(_), do: :error

  def notice(stderr, stdout \\ "") do
    line = safe_line(stderr) || stdout_error_line(stdout)

    class =
      cond do
        line && String.contains?(String.downcase(line), "authentication required") ->
          "auth"

        line && String.contains?(String.downcase(line), "model unavailable") ->
          "model_unavailable"

        line && String.contains?(String.downcase(line), "switch to an included model") ->
          "model_unavailable"

        line && String.contains?(String.downcase(line), "rate limit") ->
          "rate_limit"

        line && String.contains?(String.downcase(line), "quota") ->
          "rate_limit"

        true ->
          nil
      end

    reason =
      if line do
        "Cursor Agent: #{line}"
      else
        "Cursor did not finish with a valid result and clean exit. No fallback was started."
      end

    %{reason: reason, class: class}
  end

  defp stdout_error_line(stdout) when is_binary(stdout) do
    trimmed = String.trim(stdout)

    case Jason.decode(trimmed) do
      {:ok, %{"type" => "result", "is_error" => true, "result" => msg}} when is_binary(msg) ->
        safe_line(msg)

      {:ok, %{"type" => "result"}} ->
        nil

      _ ->
        safe_line(stdout)
    end
  end

  defp stdout_error_line(_), do: nil

  defp safe_line(text) when is_binary(text) do
    if String.valid?(text) do
      text
      |> String.split(~r/\R/u, parts: 4)
      |> Enum.map(&redact/1)
      |> Enum.find(&(String.trim(&1) != ""))
      |> case do
        nil -> nil
        line -> line |> String.replace(~r/[\p{Cc}]+/u, " ") |> String.trim() |> clip(240)
      end
    end
  end

  defp safe_line(_), do: nil

  defp redact(line) do
    Regex.replace(
      ~r/(?i)(api[_-]?key|token|secret|bearer|authorization)(\s*[:=]\s*)\S+/,
      line,
      "\\1\\2[redacted]"
    )
  end

  defp clip(line, max) do
    if byte_size(line) <= max, do: line, else: binary_part(line, 0, max) <> "…"
  end

  defp json_object(text) do
    trimmed = String.trim(text)

    case Jason.decode(trimmed) do
      {:ok, map} when is_map(map) ->
        trimmed

      _ ->
        case extract_last_json_object(trimmed) do
          nil -> trimmed
          found -> found
        end
    end
  end

  defp extract_last_json_object(bin) do
    scan_json_objects(bin, 0, byte_size(bin), false, false, 0, nil, [])
    |> List.last()
  end

  defp scan_json_objects(_bin, idx, len, _in_str, _esc, _depth, _start, acc) when idx >= len,
    do: Enum.reverse(acc)

  defp scan_json_objects(bin, idx, len, true, true, depth, start, acc) do
    scan_json_objects(bin, idx + 1, len, true, false, depth, start, acc)
  end

  defp scan_json_objects(bin, idx, len, true, false, depth, start, acc) do
    case :binary.at(bin, idx) do
      ?\\ -> scan_json_objects(bin, idx + 1, len, true, true, depth, start, acc)
      ?" -> scan_json_objects(bin, idx + 1, len, false, false, depth, start, acc)
      _ -> scan_json_objects(bin, idx + 1, len, true, false, depth, start, acc)
    end
  end

  defp scan_json_objects(bin, idx, len, false, _esc, depth, start, acc) do
    case :binary.at(bin, idx) do
      ?" when depth > 0 ->
        scan_json_objects(bin, idx + 1, len, true, false, depth, start, acc)

      ?{ when depth == 0 ->
        scan_json_objects(bin, idx + 1, len, false, false, 1, idx, acc)

      ?{ ->
        scan_json_objects(bin, idx + 1, len, false, false, depth + 1, start, acc)

      ?} when depth == 1 and is_integer(start) ->
        slice = binary_part(bin, start, idx - start + 1)

        next_acc =
          case Jason.decode(slice) do
            {:ok, map} when is_map(map) -> [slice | acc]
            _ -> acc
          end

        scan_json_objects(bin, idx + 1, len, false, false, 0, nil, next_acc)

      ?} when depth > 1 ->
        scan_json_objects(bin, idx + 1, len, false, false, depth - 1, start, acc)

      _ ->
        scan_json_objects(bin, idx + 1, len, false, false, depth, start, acc)
    end
  end

  defp summary(envelope) do
    duration = envelope["duration_ms"]

    %{
      "type" => "result",
      "subtype" => "success",
      "is_error" => false,
      "duration_ms" => if(is_integer(duration) and duration >= 0, do: duration)
    }
  end
end
