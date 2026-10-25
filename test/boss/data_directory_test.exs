defmodule Boss.DataDirectoryTest do
  use ExUnit.Case, async: true

  @tag :tmp_dir
  test "refused ownership preserves permissions; release permits reopening", %{tmp_dir: dir} do
    assert {:ok, lock} = Boss.DataDirectory.acquire(dir)
    File.chmod!(dir, 0o755)
    previous_mode = File.stat!(dir).mode
    assert {:error, reason} = Boss.DataDirectory.acquire(dir)
    assert File.stat!(dir).mode == previous_mode
    assert reason =~ "already in use"
    assert :ok = Boss.DataDirectory.release(lock)
    assert {:ok, next_lock} = Boss.DataDirectory.acquire(dir)
    assert :ok = Boss.DataDirectory.release(next_lock)
  end

  @tag :tmp_dir
  test "an unusable path returns a clear error without deleting it", %{tmp_dir: dir} do
    path = Path.join(dir, "existing-file")
    File.write!(path, "keep me")
    assert {:error, reason} = Boss.DataDirectory.acquire(path)
    assert reason =~ "Cannot open BOSS data directory"
    assert File.read!(path) == "keep me"
  end

  @tag :tmp_dir
  test "a corrupt database fails startup and releases the ownership lock", %{tmp_dir: dir} do
    database = Path.join(dir, "boss.db")
    File.write!(database, "not a database")
    assert {:error, reason} = Boss.DataDirectory.acquire(dir)
    assert reason =~ "not a database"
    assert File.read!(database) == "not a database"
    File.rm!(database)
    assert {:ok, lock} = Boss.DataDirectory.acquire(dir)
    Boss.DataDirectory.release(lock)
  end
end
