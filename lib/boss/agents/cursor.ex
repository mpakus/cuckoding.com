defmodule Boss.Agents.Cursor do
  @moduledoc false

  def args do
    [
      "--print",
      "--output-format",
      "json",
      "--mode",
      "ask",
      "--sandbox",
      "enabled",
      "--trust"
    ]
  end

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

  defp json_object(text) do
    trimmed = String.trim(text)

    case Regex.run(~r/```(?:json)?\s*(\{.*\})\s*```/s, trimmed) do
      [_, object] -> object
      _ -> trimmed
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
