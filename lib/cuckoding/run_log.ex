defmodule Cuckoding.RunLog do
  @moduledoc "Bounded public views of a run-owned process log; never serves raw provider output."

  alias Cuckoding.Adapters.{ClaudeCode, Codex, CursorAgent}
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor

  @tail_bytes 8_388_608
  @line_bytes 65_536
  @line_limit 5_000
  @omitted "[Entry omitted: not a supported public event or exceeds the safe line limit]"

  def entries(artifacts) do
    Enum.flat_map(artifacts, fn artifact ->
      case Regex.run(~r/\Aprocess-([0-9a-f-]{36})\.log\z/, artifact.name) do
        [_, id] -> [%{id: id, name: artifact.name}]
        _other -> []
      end
    end)
  end

  def tail(run_id, log_id) do
    with_log(run_id, log_id, fn log ->
      offset = max(log.size - @tail_bytes, 0)

      case :file.pread(log.file, offset, min(log.size, @tail_bytes)) do
        {:ok, bytes} ->
          all_lines = complete_lines(bytes, offset)
          lines = Enum.take(all_lines, -@line_limit)

          {:ok,
           %{
             text: Enum.map_join(lines, "\n", &public_line/1),
             lines: length(lines),
             limited?: offset > 0 or length(all_lines) > @line_limit
           }}

        :eof ->
          {:ok, %{text: "", lines: 0, limited?: false}}

        {:error, _reason} ->
          {:error, :log_unavailable}
      end
    end)
  end

  # The callback owns the read for its entire lifetime, including a streamed download.
  def with_log(run_id, log_id, callback) do
    with {:ok, run_id} <- Ecto.UUID.cast(run_id),
         {:ok, log_id} <- Ecto.UUID.cast(log_id),
         %Environment{} = environment <- Repo.get_by(Environment, run_id: run_id),
         path = Path.join([environment.run_dir, "artifacts", "process-#{log_id}.log"]),
         :ok <- regular_path(path),
         {:ok, file} <- File.open(path, [:read, :binary, :raw]) do
      try do
        with {:ok, info} <- :file.read_file_info(file),
             stat = File.Stat.from_record(info),
             :ok <- regular_path(path),
             {:ok, current} <- File.lstat(path),
             true <- same_file?(stat, current) do
          callback.(%{file: file, size: stat.size})
        else
          _other -> {:error, :log_unavailable}
        end
      after
        File.close(file)
      end
    else
      _other -> {:error, :log_unavailable}
    end
  end

  def stream(log) do
    Stream.unfold({0, "", false}, fn
      {offset, "", false} when offset >= log.size ->
        nil

      {offset, pending, dropping} when offset >= log.size ->
        line = if dropping, do: @omitted, else: public_line(pending)
        {[line, "\n"], {offset, "", false}}

      {offset, pending, dropping} ->
        case :file.pread(log.file, offset, min(@line_bytes, log.size - offset)) do
          {:ok, bytes} ->
            {lines, rest, dropping} = split_chunk(pending, bytes, dropping)
            output = Enum.map(lines, &[public_line(&1), "\n"])
            {output, {offset + byte_size(bytes), rest, dropping}}

          _other ->
            nil
        end
    end)
  end

  defp regular_path(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular, links: 1}} -> directory_path(Path.dirname(path))
      _other -> {:error, :log_unavailable}
    end
  end

  defp directory_path("/"), do: :ok

  defp directory_path(path) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        directory_path(Path.dirname(path))

      {:ok, %{type: :symlink}} when path in ["/var", "/tmp"] ->
        with {:ok, target} <- File.read_link(path),
             true <- Path.expand(target, "/") == "/private" <> path do
          directory_path("/private" <> path)
        else
          _other -> {:error, :log_unavailable}
        end

      _other ->
        {:error, :log_unavailable}
    end
  end

  defp same_file?(left, right) do
    left.type == :regular and left.links == 1 and
      {left.inode, left.major_device, left.minor_device} ==
        {right.inode, right.major_device, right.minor_device}
  end

  defp complete_lines(bytes, offset) do
    lines = :binary.split(bytes, "\n", [:global])
    lines = if offset > 0, do: tl(lines), else: lines
    if List.last(lines) == "", do: Enum.drop(lines, -1), else: lines
  end

  defp split_chunk(pending, bytes, dropping) do
    parts = :binary.split(pending <> bytes, "\n", [:global])
    {lines, [rest]} = Enum.split(parts, -1)
    lines = if dropping and lines != [], do: [@omitted | tl(lines)], else: lines
    dropping = (dropping and lines == []) or byte_size(rest) > @line_bytes
    {lines, if(dropping, do: "", else: rest), dropping}
  end

  defp public_line(line) do
    if byte_size(line) <= @line_bytes and String.valid?(line) do
      normalize_line(line)
    else
      @omitted
    end
  end

  defp normalize_line("Reading additional input from stdin..."),
    do: "Reading additional input from stdin..."

  defp normalize_line(line) do
    with {:ok, row} when is_map(row) <- Jason.decode(line),
         {:ok, event} <- decode_public(Redactor.redact(row)) do
      %{type: event.type, summary: event.public_summary, metadata: event.metadata}
      |> Redactor.redact()
      |> Jason.encode!()
    else
      _other -> @omitted
    end
  rescue
    _error -> @omitted
  end

  defp decode_public(row) do
    Enum.find_value([Codex, ClaudeCode, CursorAgent], {:error, :unsupported}, fn module ->
      case module.decode_event(row, []) do
        {:ok, event} -> {:ok, event}
        _other -> nil
      end
    end)
  end
end
