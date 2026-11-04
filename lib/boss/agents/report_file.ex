defmodule Boss.Agents.ReportFile do
  @moduledoc false
  # Keep the exclusively created file descriptor: a replaced path is never read.
  def read(path, file) do
    case read_checked(path, file) do
      {:ok, bytes, _} -> {:ok, bytes}
      _ -> {:error, :invalid_review}
    end
  end

  def size(file) do
    with {:ok, info} <- :file.read_file_info(file),
         %{type: :regular, size: bytes} <- File.Stat.from_record(info),
         true <- bytes in 0..9_007_199_254_740_991 do
      bytes
    else
      _ -> nil
    end
  end

  def read_checked(path, file) do
    bytes = size(file)

    with {:ok, info} <- :file.read_file_info(file),
         original = File.Stat.from_record(info),
         :ok <- same_file(path, original),
         :ok <- bounded_size(original.size),
         {:ok, 0} <- :file.position(file, :bof),
         {:ok, text} <- :file.read(file, 32_769),
         :ok <- bounded_size(byte_size(text)),
         true <- byte_size(text) == original.size,
         :ok <- same_file(path, original) do
      {:ok, text, byte_size(text)}
    else
      {:error, code} when code in [:report_empty, :report_too_large, :report_replaced] ->
        {:error, code, bytes}

      _ ->
        {:error, :report_unavailable, bytes}
    end
  end

  defp bounded_size(0), do: {:error, :report_empty}
  defp bounded_size(bytes) when bytes > 32_768, do: {:error, :report_too_large}
  defp bounded_size(bytes) when bytes > 0, do: :ok

  defp same_file(path, original) do
    with {:ok, current} <- File.lstat(path),
         true <-
           original.type == :regular and current.type == :regular and
             current.inode == original.inode and current.major_device == original.major_device and
             current.size == original.size do
      :ok
    else
      _ -> {:error, :report_replaced}
    end
  end

  def with_file(fun) do
    directory = Path.join(System.tmp_dir!(), "boss-review-" <> Ecto.UUID.generate())

    case File.mkdir(directory) do
      :ok ->
        path = Path.join(directory, "report.json")
        owner = self()

        cleanup =
          spawn(fn ->
            ref = Process.monitor(owner)

            receive do
              {:DOWN, ^ref, :process, ^owner, _} -> :ok
              {:finished, ^owner} -> :ok
            end

            remove_report(directory)
            send(owner, {:report_removed, self()})
          end)

        try do
          with :ok <- File.chmod(directory, 0o700),
               {:ok, file} <- File.open(path, [:read, :write, :binary, :raw, :exclusive]) do
            try do
              with :ok <- File.chmod(path, 0o600), do: fun.(path, file)
            after
              File.close(file)
            end
          end
        after
          send(cleanup, {:finished, self()})

          receive do
            {:report_removed, ^cleanup} -> :ok
          after
            1_000 -> :ok
          end
        end

      _ ->
        {:error, :report_unavailable}
    end
  end

  defp remove_report(directory) do
    closing = directory <> ".closing"

    # Invalidate the CLI's pathname atomically before unlinking its output.
    with :ok <- File.mkdir(closing) do
      case File.rename(directory, closing) do
        :ok ->
          File.rm(Path.join(closing, "report.json"))
          File.rmdir(closing)

        _ ->
          File.rmdir(closing)
      end
    end
  end
end
