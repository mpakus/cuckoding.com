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

  defp model_flags(_), do: []

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
    line = safe_line(stderr) || safe_line(stdout)

    class =
      cond do
        line && String.contains?(String.downcase(line), "authentication required") -> "auth"
        line && String.contains?(String.downcase(line), "rate limit") -> "rate_limit"
        line && String.contains?(String.downcase(line), "quota") -> "rate_limit"
        true -> nil
      end

    reason =
      if line do
        "Cursor Agent: #{line}"
      else
        "Cursor did not finish with a valid result and clean exit. No fallback was started."
      end

    %{reason: reason, class: class}
  end

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

    case Regex.run(~r/```(?:json)?\s*(\{[\s\S]*\})\s*```/, trimmed) do
      [_, object] ->
        String.trim(object)

      _ ->
        with {first, 1} <- :binary.match(trimmed, "{"),
             true <- not String.starts_with?(trimmed, "{"),
             last when is_integer(last) and last > first <- last_brace(trimmed) do
          binary_part(trimmed, first, last - first + 1)
        else
          _ -> trimmed
        end
    end
  end

  defp last_brace(bin) do
    case :binary.matches(bin, "}") do
      [] -> nil
      matches -> matches |> List.last() |> elem(0)
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
