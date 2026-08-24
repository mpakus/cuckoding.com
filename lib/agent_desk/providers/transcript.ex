defmodule AgentDesk.Providers.Transcript do
  @moduledoc """
  Append-only JSONL transcripts stored under the application-data directory.
  """

  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.Redactor
  alias AgentDesk.Storage

  @spec path(Ecto.UUID.t(), Ecto.UUID.t()) :: String.t()
  def path(project_id, session_id) do
    Path.join([Storage.session_dir(project_id, session_id), "transcript.jsonl"])
  end

  @spec append(Ecto.UUID.t(), Ecto.UUID.t(), Event.t()) :: :ok | {:error, term()}
  def append(project_id, session_id, %Event{} = event) do
    if persist?(event.type) do
      dir = Storage.session_dir(project_id, session_id)
      File.mkdir_p!(dir)

      line =
        Jason.encode!(%{
          "type" => Atom.to_string(event.type),
          "payload" => Redactor.redact(event.payload),
          "occurred_at" => event.occurred_at && DateTime.to_iso8601(event.occurred_at)
        })

      File.write(path(project_id, session_id), line <> "\n", [:append])
    else
      :ok
    end
  end

  @spec read(Ecto.UUID.t(), Ecto.UUID.t()) :: [map()]
  def read(project_id, session_id) do
    case File.read(path(project_id, session_id)) do
      {:ok, contents} -> decode_lines(contents)
      {:error, _} -> []
    end
  end

  @spec window(Ecto.UUID.t(), Ecto.UUID.t(), keyword()) :: %{
          rows: [map()],
          older?: boolean(),
          total: non_neg_integer()
        }
  def window(project_id, session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 200)
    rows = read(project_id, session_id)
    total = length(rows)
    start = max(0, total - limit)

    %{
      rows: Enum.slice(rows, start, limit),
      older?: start > 0,
      total: total
    }
  end

  defp decode_lines(contents) do
    contents
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&decode_line/1)
  end

  defp decode_line(line) do
    case Jason.decode(line) do
      {:ok, map} -> [map]
      {:error, _} -> []
    end
  end

  defp persist?(:message_delta), do: false
  defp persist?(:reasoning_delta), do: false
  defp persist?(:command_output), do: false
  defp persist?(_type), do: true
end
