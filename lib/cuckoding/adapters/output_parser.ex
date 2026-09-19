defmodule Cuckoding.Adapters.OutputParser do
  @moduledoc "Reads one bounded structured result from a provider-owned JSONL artifact."

  alias Cuckoding.Adapters.Types

  @maximum_bytes 1_048_576
  @maximum_rows 2_000

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
