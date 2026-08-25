defmodule AgentDesk.Providers.CursorTest do
  use ExUnit.Case, async: false

  alias AgentDesk.Providers.Cursor

  test "editor cursor CLI uses agent acp args" do
    path = stub_bin!("cursor")
    assert {:ok, ^path, ["agent", "acp"]} = Cursor.resolve(executable: path)
  end

  test "agent CLI uses acp args" do
    path = stub_bin!("agent")
    assert {:ok, ^path, ["acp"]} = Cursor.resolve(executable: path)
  end

  test "discovers the preferred agent executable from an isolated PATH" do
    path = stub_bin!("agent")
    isolate_path!(Path.dirname(path))

    assert {:ok, ^path, ["acp"]} = Cursor.resolve([])
  end

  defp stub_bin!(name) do
    dir = owned_tmp_dir!("cursor-#{name}")
    path = Path.join(dir, name)
    File.write!(path, "#!/bin/sh\necho ok\n")
    File.chmod!(path, 0o755)
    path
  end

  defp isolate_path!(dir) do
    previous = System.get_env("PATH")
    System.put_env("PATH", dir)
    on_exit(fn -> restore_path(previous) end)
  end

  defp restore_path(nil), do: System.delete_env("PATH")
  defp restore_path(path), do: System.put_env("PATH", path)

  defp owned_tmp_dir!(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-#{name}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(dir)

    on_exit(fn ->
      File.rm_rf!(dir)
      refute File.exists?(dir)
    end)

    dir
  end
end
