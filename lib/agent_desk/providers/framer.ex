defmodule AgentDesk.Providers.Framer do
  @moduledoc """
  Newline-delimited JSON framing with partial-line buffering and a size cap.
  """

  defstruct buffer: "", max_line: 1_048_576

  @type t :: %__MODULE__{buffer: String.t(), max_line: pos_integer()}

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{max_line: Keyword.get(opts, :max_line, 1_048_576)}
  end

  @spec push(t(), binary()) :: {:ok, [String.t()], t()} | {:error, :line_too_large}
  def push(%__MODULE__{} = framer, data) when is_binary(data) do
    combined = framer.buffer <> data

    if byte_size(combined) > framer.max_line and not String.contains?(combined, "\n") do
      {:error, :line_too_large}
    else
      split_lines(combined, framer, [])
    end
  end

  defp split_lines(buffer, framer, acc) do
    case String.split(buffer, "\n", parts: 2) do
      [complete, rest] ->
        if byte_size(complete) > framer.max_line do
          {:error, :line_too_large}
        else
          split_lines(rest, framer, [complete | acc])
        end

      [rest] ->
        if byte_size(rest) > framer.max_line do
          {:error, :line_too_large}
        else
          {:ok, Enum.reverse(acc), %{framer | buffer: rest}}
        end
    end
  end
end
