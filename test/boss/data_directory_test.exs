defmodule Boss.DataDirectoryTest do
  use ExUnit.Case, async: true

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  @tag :tmp_dir
  test "only one owner can open a data directory, and shutdown releases it", %{tmp_dir: dir} do
    start_supervised!({Boss.DataDirectory, directory: dir, name: nil})
    assert {:error, reason} = Boss.DataDirectory.start_link(directory: dir, name: nil)
    assert reason =~ "already in use"
    assert :ok = stop_supervised(Boss.DataDirectory)
    assert {:ok, owner} = Boss.DataDirectory.start_link(directory: dir, name: nil)
    GenServer.stop(owner)
  end

  @tag :tmp_dir
  test "an unusable path returns a clear error without deleting it", %{tmp_dir: dir} do
    path = Path.join(dir, "existing-file")
    File.write!(path, "keep me")
    assert {:error, reason} = Boss.DataDirectory.start_link(directory: path, name: nil)
    assert reason =~ "Cannot open BOSS data directory"
    assert File.read!(path) == "keep me"
  end
end
