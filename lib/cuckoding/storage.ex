defmodule Cuckoding.Storage do
  @moduledoc "Private rebuild storage, explicitly separate from historical application data."
  import Bitwise
  @marker ".ccoding-rebuild-v1"

  # App-owned absolute path; symlinks and unknown existing data fail closed.
  # sobelow_skip ["Traversal.FileModule"]
  def prepare!(root) do
    if Path.type(root) != :absolute, do: raise("data directory must be absolute")
    reject_symlinks!(root)
    File.mkdir_p!(root)
    marker = Path.join(root, @marker)
    reject_symlinks!(marker)

    case File.read(marker) do
      {:ok, "ccoding-rebuild-v1\n"} ->
        :ok

      {:error, :enoent} ->
        if Enum.any?(
             File.ls!(root),
             &(&1 != "shell.lock" and not String.starts_with?(&1, "launch-"))
           ) do
          raise "unrecognized data directory; preserve it and select a new rebuild directory"
        end

        File.write!(marker, "ccoding-rebuild-v1\n", [:exclusive])
        File.chmod!(marker, 0o600)

      _ ->
        raise "invalid rebuild data marker"
    end

    File.chmod!(root, 0o700)

    for name <- [@marker, "foundation.db", "foundation.db-wal", "foundation.db-shm"] do
      path = Path.join(root, name)
      reject_symlinks!(path)
      if File.exists?(path), do: File.chmod!(path, 0o600)
    end

    :ok
  end

  # Only a private, bounded, regular launch file inside the validated data root.
  # sobelow_skip ["Traversal.FileModule"]
  def consume_bootstrap!(root, path) do
    unless Path.dirname(path) == root and String.starts_with?(Path.basename(path), "launch-") do
      raise "invalid bootstrap location"
    end

    reject_symlinks!(path)
    stat = File.stat!(path)

    unless stat.type == :regular and band(stat.mode, 0o077) == 0 and stat.size <= 1024 do
      raise "unsafe bootstrap file"
    end

    data = path |> File.read!() |> Jason.decode!()

    unless match?(
             %{"bootstrap" => b, "signing" => s} when byte_size(b) == 64 and byte_size(s) == 128,
             data
           ) do
      raise "invalid bootstrap data"
    end

    File.rm!(path)
    data
  end

  defp reject_symlinks!(path) do
    path
    |> Path.expand()
    |> Path.split()
    |> Enum.scan(&Path.join(&2, &1))
    |> Enum.each(fn current ->
      case File.lstat(current) do
        {:ok, %{type: :symlink}} -> raise "symbolic links are not allowed in app storage"
        {:ok, _} -> :ok
        {:error, :enoent} -> :ok
        _ -> raise "cannot inspect app storage"
      end
    end)
  end
end
