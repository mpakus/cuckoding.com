defmodule Boss.Agents.ReportFile do
  @moduledoc false
  # Keep the exclusively created file descriptor: a replaced path is never read.
  def read(path, file) do
    with {:ok, info} <- :file.read_file_info(file),
         original = File.Stat.from_record(info),
         true <- original.type == :regular and original.size in 1..32_768,
         {:ok, current} <- File.lstat(path),
         true <-
           current.type == :regular and current.inode == original.inode and
             current.major_device == original.major_device,
         {:ok, 0} <- :file.position(file, :bof),
         {:ok, bytes} when byte_size(bytes) <= 32_768 <- :file.read(file, 32_769) do
      {:ok, bytes}
    else
      _ -> {:error, :invalid_review}
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
