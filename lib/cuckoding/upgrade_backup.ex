defmodule Cuckoding.UpgradeBackup do
  @moduledoc "Verified database-only copies before startup migration; never automatic restoration."
  import Bitwise

  @max_bytes 1_073_741_824
  @budget_ms 20_000
  @versions "SELECT version FROM schema_migrations ORDER BY version LIMIT 257"

  # Paths derive only from the recognized private root and a fresh UUID, never browser input.
  # sobelow_skip ["Traversal.FileModule"]
  def create!(repo, from, target) do
    true = valid_versions?(from) and valid_versions?(target)
    true = from != target and Enum.all?(from, &(&1 in target))
    source = repo.config()[:database]
    root = Path.dirname(source)
    root_stat = root!(root)
    true = source == Path.join(root, "foundation.db")
    source_stat = private_source!(source)
    deadline = System.monotonic_time(:millisecond) + @budget_ms
    backups = Path.join(root, "backups")
    directory!(backups)
    pointer!(backups)
    id = Ecto.UUID.generate()
    directory = Path.join(backups, id)
    File.mkdir!(directory)
    File.chmod!(directory, 0o700)
    copy = Path.join(directory, "foundation.db")
    write_new!(copy, "")

    repo.checkout(
      fn ->
        query = fn sql -> repo.query!(sql, [], timeout: remaining!(deadline), log: false).rows end
        [[sync]] = query.("PRAGMA synchronous")
        true = sync in 1..3
        [[pages]] = query.("PRAGMA page_count")
        [[page_size]] = query.("PRAGMA page_size")
        true = (pages * page_size) in 1..@max_bytes
        valid_database!(query, from)
        before = query.("PRAGMA data_version")
        repo.query!("VACUUM INTO ?", [copy], timeout: remaining!(deadline), log: false)
        true = before == query.("PRAGMA data_version")
        true = from == List.flatten(query.(@versions))
        true = identity(source_stat) == identity(File.lstat!(source))
        verify_copy!(copy, from, deadline)
      end,
      timeout: remaining!(deadline)
    )

    {bytes, hash} = hash!(copy, deadline)
    true = identity(root_stat) == identity(root!(root))

    receipt = %{
      "format" => 1,
      "backup_id" => id,
      "verified_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "from_versions" => from,
      "target_versions" => target,
      "bytes" => bytes,
      "sha256" => hash,
      "root_device" => root_stat.major_device,
      "root_inode" => root_stat.inode
    }

    remaining!(deadline)
    write_new!(Path.join(directory, "receipt.json"), Jason.encode!(receipt))
    sync!(directory, [:read, :raw, :directory])
    pointer!(backups)
    temporary = Path.join(backups, id <> ".json")
    write_new!(temporary, Jason.encode!(%{"format" => 1, "backup_id" => id}))
    File.rename!(temporary, Path.join(backups, "latest.json"))
    sync!(backups, [:read, :raw, :directory])
    sync!(root, [:read, :raw, :directory])
    :ok
  rescue
    _ ->
      raise "pre-migration backup could not be verified; migration refused, retained files preserved"
  catch
    :exit, _ ->
      raise "pre-migration backup could not finish; migration refused, retained files preserved"
  end

  @doc "Dated metadata only. It does not revalidate database contents or authorize a restore."
  def observation(root) do
    root_stat = root!(root)
    backups = Path.join(root, "backups")

    case File.lstat(backups) do
      {:error, :enoent} -> %{"status" => "none"}
      {:ok, _} -> recorded!(backups, root_stat)
      _ -> %{"status" => "unavailable"}
    end
  rescue
    _ -> %{"status" => "unavailable"}
  end

  defp recorded!(backups, root_stat) do
    private!(backups, :directory)

    case pointer!(backups) do
      nil ->
        %{"status" => "none"}

      id ->
        directory = Path.join(backups, id)
        private!(directory, :directory)
        receipt = Path.join(directory, "receipt.json") |> read_bytes!(8192) |> Jason.decode!()
        validate_receipt!(receipt, id, root_stat)
        copy = private!(Path.join(directory, "foundation.db"), :regular)
        true = copy.size == receipt["bytes"]

        receipt
        |> Map.take(~w(verified_at from_versions target_versions bytes sha256))
        |> Map.merge(%{
          "status" => "recorded",
          "relative_path" => Path.join(["backups", id, "foundation.db"])
        })
    end
  end

  defp validate_receipt!(receipt, id, root_stat) do
    true = map_size(receipt) == 9
    true = receipt["format"] == 1 and receipt["backup_id"] == id
    true = receipt["root_device"] == root_stat.major_device
    true = receipt["root_inode"] == root_stat.inode
    {:ok, _, 0} = DateTime.from_iso8601(receipt["verified_at"])
    true = valid_versions?(receipt["from_versions"])
    true = valid_versions?(receipt["target_versions"])
    true = is_integer(receipt["bytes"]) and receipt["bytes"] in 1..@max_bytes
    true = is_binary(receipt["sha256"]) and Regex.match?(~r/\A[0-9a-f]{64}\z/, receipt["sha256"])
  end

  defp valid_versions?(versions) do
    is_list(versions) and length(versions) in 1..256 and
      Enum.all?(versions, &(is_integer(&1) and &1 > 0)) and
      versions == Enum.sort(Enum.uniq(versions))
  end

  defp verify_copy!(copy, from, deadline) do
    # DBConnection cancellation bounds the readonly checks using the same startup budget.
    {:ok, connection} = Exqlite.start_link(database: copy, mode: :readonly, backoff_type: :stop)

    try do
      valid_database!(
        fn sql -> Exqlite.query!(connection, sql, [], timeout: remaining!(deadline)).rows end,
        from
      )
    after
      GenServer.stop(connection, :normal, 1000)
    end

    sync!(copy, [:read, :raw])
  end

  defp valid_database!(query, versions) do
    true = valid_versions?(versions)
    [["ok"]] = query.("PRAGMA integrity_check(1)")
    [] = query.("SELECT 1 FROM pragma_foreign_key_check LIMIT 1")
    true = versions == List.flatten(query.(@versions))
  end

  # Streaming avoids loading the database into a LiveView or startup process heap.
  # sobelow_skip ["Traversal.FileModule"]
  defp hash!(path, deadline) do
    stat = private!(path, :regular)
    true = stat.size in 1..@max_bytes
    {:ok, file} = File.open(path, [:read, :raw, :binary])

    try do
      {:ok, info} = :file.read_file_info(file)
      true = identity(stat) == identity(File.Stat.from_record(info))
      {bytes, context} = hash_chunks!(file, deadline, 0, :crypto.hash_init(:sha256))
      true = bytes == stat.size
      true = unchanged?(stat, private!(path, :regular))
      {bytes, Base.encode16(:crypto.hash_final(context), case: :lower)}
    after
      File.close(file)
    end
  end

  defp hash_chunks!(file, deadline, bytes, context) do
    remaining!(deadline)

    case IO.binread(file, 65_536) do
      :eof ->
        {bytes, context}

      data when is_binary(data) ->
        true = bytes + byte_size(data) <= @max_bytes
        hash_chunks!(file, deadline, bytes + byte_size(data), :crypto.hash_update(context, data))
    end
  end

  # Refuse links before chmod, including the source database created by Repo.
  # sobelow_skip ["Traversal.FileModule"]
  defp private_source!(source) do
    stat = File.lstat!(source)
    true = stat.type == :regular and stat.links == 1
    File.chmod!(source, 0o600)
    private!(source, :regular)
  end

  defp root!(root) do
    true = Path.type(root) == :absolute and Path.expand(root) == root
    reject_links!(root)
    stat = private!(root, :directory)
    marker = Path.join(root, ".ccoding-rebuild-v1")
    true = read_bytes!(marker, 32) == "ccoding-rebuild-v1\n"
    stat
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp directory!(path) do
    case File.lstat(path) do
      {:error, :enoent} ->
        File.mkdir!(path)
        File.chmod!(path, 0o700)

      {:ok, _} ->
        private!(path, :directory)
    end
  end

  defp pointer!(backups) do
    path = Path.join(backups, "latest.json")

    case File.lstat(path) do
      {:error, :enoent} ->
        nil

      {:ok, _} ->
        %{"format" => 1, "backup_id" => id} =
          pointer = path |> read_bytes!(128) |> Jason.decode!()

        true = map_size(pointer) == 2
        {:ok, ^id} = Ecto.UUID.cast(id)
        id
    end
  end

  # Bounded, descriptor-checked fixed metadata; never deserialize database rows.
  # sobelow_skip ["Traversal.FileModule"]
  defp read_bytes!(path, limit) do
    stat = private!(path, :regular)
    true = stat.size in 1..limit
    {:ok, file} = File.open(path, [:read, :raw, :binary])

    try do
      {:ok, info} = :file.read_file_info(file)
      descriptor = File.Stat.from_record(info)
      true = identity(stat) == identity(descriptor)
      data = IO.binread(file, limit + 1)
      true = is_binary(data) and byte_size(data) == stat.size
      true = unchanged?(stat, private!(path, :regular))
      data
    after
      File.close(file)
    end
  end

  # sobelow_skip ["Traversal.FileModule"]
  defp write_new!(path, data) do
    {:ok, file} = File.open(path, [:write, :raw, :binary, :exclusive])

    try do
      File.chmod!(path, 0o600)
      :ok = IO.binwrite(file, data)
      :ok = :file.sync(file)
    after
      File.close(file)
    end
  end

  defp private!(path, type) do
    stat = File.lstat!(path)
    true = stat.type == type and band(stat.mode, 0o077) == 0
    true = type != :regular or stat.links == 1
    stat
  end

  defp reject_links!(path) do
    path
    |> Path.split()
    |> Enum.scan(&Path.join(&2, &1))
    |> Enum.each(fn current -> true = File.lstat!(current).type != :symlink end)
  end

  defp sync!(path, modes) do
    {:ok, file} = :file.open(String.to_charlist(path), modes)

    try do
      :ok = :file.sync(file)
    after
      :file.close(file)
    end
  end

  defp identity(stat), do: {stat.major_device, stat.inode, stat.type}

  defp unchanged?(before, after_read),
    do:
      Map.delete(Map.from_struct(before), :atime) ==
        Map.delete(Map.from_struct(after_read), :atime)

  defp remaining!(deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)
    true = remaining > 0
    remaining
  end
end
