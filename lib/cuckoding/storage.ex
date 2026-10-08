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

  # A new private scratch directory per consented check; no account profile is imported.
  # sobelow_skip ["Traversal.FileModule"]
  def probe_directory!(id, attempt) do
    {:ok, ^id} = Ecto.UUID.cast(id)
    true = is_integer(attempt) and attempt in 1..3
    root = Application.fetch_env!(:cuckoding, :data_dir)
    prepare!(root)
    path = Path.join([root, "probes", id <> "-" <> Integer.to_string(attempt)])
    reject_symlinks!(path)
    File.mkdir_p!(path)
    File.chmod!(Path.dirname(path), 0o700)
    File.chmod!(path, 0o700)
    path
  end

  # Stable provider-owned profile; only metadata is inspected by Cuckoding.
  # sobelow_skip ["Traversal.FileModule"]
  def codex_profile! do
    root = Application.fetch_env!(:cuckoding, :data_dir)
    prepare!(root)
    path = Path.join([root, "agents", "codex"])
    reject_symlinks!(path)
    File.mkdir_p!(path)
    File.chmod!(Path.dirname(path), 0o700)
    File.chmod!(path, 0o700)
    path
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

  # Fixed app-owned UUID paths only; never overwrite an earlier or partial artifact.
  # sobelow_skip ["Traversal.FileModule"]
  def write_spec(id, text) when is_binary(text) and byte_size(text) <= 262_144 do
    path = spec_path!(id)
    File.mkdir_p!(Path.dirname(path))
    File.chmod!(Path.dirname(path), 0o700)
    reject_symlinks!(path)

    case File.open(path, [:write, :binary, :exclusive]) do
      {:ok, file} ->
        try do
          File.chmod!(path, 0o600)
          with :ok <- IO.binwrite(file, text), do: :file.sync(file)
        after
          File.close(file)
        end

      _ ->
        {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  def write_spec(_, _), do: {:error, :unavailable}

  # Hash-check bounded regular single-link files; never serve arbitrary paths or raw Markdown as HTML.
  # sobelow_skip ["Traversal.FileModule"]
  def read_spec(id, hash) do
    path = spec_path!(id)

    with {:ok, stat} <- File.lstat(path),
         true <-
           stat.type == :regular and stat.links == 1 and stat.size <= 262_144 and
             band(stat.mode, 0o077) == 0,
         {:ok, text} <- File.open(path, [:read, :binary], &IO.binread(&1, 262_145)),
         true <- is_binary(text) and byte_size(text) == stat.size,
         {:ok, after_read} <- File.lstat(path),
         true <-
           Map.delete(Map.from_struct(stat), :atime) ==
             Map.delete(Map.from_struct(after_read), :atime),
         true <- Base.encode16(:crypto.hash(:sha256, text), case: :lower) == hash do
      {:ok, text}
    else
      _ -> {:error, :unavailable}
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp spec_path!(id) do
    {:ok, ^id} = Ecto.UUID.cast(id)
    root = Application.fetch_env!(:cuckoding, :data_dir)
    path = Path.join([root, "specifications", id <> ".md"])
    reject_symlinks!(path)
    path
  end
end
