defmodule AgentDesk.Providers.Framer do
  @moduledoc """
  Newline-delimited JSON framing with partial-line buffering and a size cap.

  Oversized frames are skipped so a single huge provider line cannot desync
  the rest of the stream or fail the session.
  """

  defstruct buffer: "", max_line: 33_554_432, skipping: false, dropped: 0

  @type t :: %__MODULE__{
          buffer: binary(),
          max_line: pos_integer(),
          skipping: boolean(),
          dropped: non_neg_integer()
        }

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{max_line: Keyword.get(opts, :max_line, 33_554_432)}
  end

  @spec push(t(), binary()) :: {:ok, [String.t()], t()}
  def push(%__MODULE__{} = framer, data) when is_binary(data) do
    cond do
      framer.skipping ->
        skip_until_newline(framer, data)

      true ->
        split_lines(framer.buffer <> data, %{framer | buffer: ""}, [])
    end
  end

  defp skip_until_newline(framer, data) do
    case :binary.split(data, "\n") do
      [_chunk] ->
        {:ok, [], framer}

      [_prefix, rest] ->
        split_lines(rest, %{framer | skipping: false, dropped: framer.dropped + 1}, [])
    end
  end

  defp split_lines(buffer, framer, acc) do
    case :binary.split(buffer, "\n") do
      [complete, rest] ->
        if byte_size(complete) > framer.max_line do
          split_lines(rest, %{framer | dropped: framer.dropped + 1}, acc)
        else
          split_lines(rest, framer, [complete | acc])
        end

      [rest] ->
        cond do
          byte_size(rest) > framer.max_line ->
            {:ok, Enum.reverse(acc),
             %{framer | buffer: "", skipping: true, dropped: framer.dropped + 1}}

          true ->
            {:ok, Enum.reverse(acc), %{framer | buffer: rest}}
        end
    end
  end
end
