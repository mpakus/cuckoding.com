defmodule Cuckoding.StorageToolsTest do
  use ExUnit.Case, async: true
  alias Cuckoding.{Storage, Tools}

  setup do
    root = Path.join("/private/tmp", "ccoding-test-" <> Ecto.UUID.generate())
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "old data is refused unchanged; bootstrap is private and consumed once", %{root: root} do
    old = Path.join(root, "old")
    File.mkdir!(old)
    File.write!(Path.join(old, "foundation.db"), "old-user-data")
    File.chmod!(old, 0o755)
    assert_raise RuntimeError, ~r/unrecognized/, fn -> Storage.prepare!(old) end
    assert File.read!(Path.join(old, "foundation.db")) == "old-user-data"
    assert Bitwise.band(File.stat!(old).mode, 0o777) == 0o755

    fresh = Path.join(root, "fresh")
    Storage.prepare!(fresh)
    boot = Path.join(fresh, "launch-test")
    data = %{"bootstrap" => String.duplicate("a", 64), "signing" => String.duplicate("b", 128)}
    File.write!(boot, Jason.encode!(data))
    File.chmod!(boot, 0o600)
    assert Storage.consume_bootstrap!(fresh, boot) == data
    refute File.exists?(boot)
    assert_raise File.Error, fn -> Storage.consume_bootstrap!(fresh, boot) end
  end

  test "storage and bootstrap refuse links and public credentials", %{root: root} do
    target = Path.join(root, "target")
    Storage.prepare!(target)
    link = Path.join(root, "link")
    File.ln_s!(target, link)
    assert_raise RuntimeError, ~r/symbolic/, fn -> Storage.prepare!(link) end
    boot = Path.join(target, "launch-public")
    File.write!(boot, "{}")
    File.chmod!(boot, 0o644)
    assert_raise RuntimeError, ~r/unsafe/, fn -> Storage.consume_bootstrap!(target, boot) end
  end

  test "discovery checks metadata without executing candidates", %{root: root} do
    executable = Path.join(root, "codex")
    marker = Path.join(root, "executed")
    File.write!(executable, "#!/bin/sh\ntouch #{marker}\n")
    File.chmod!(executable, 0o700)
    File.write!(Path.join(root, "claude"), "not executable")
    File.chmod!(Path.join(root, "claude"), 0o600)
    File.mkdir!(Path.join(root, "rtk"))
    tools = Tools.discover([root])
    assert tools["codex"] == %{"status" => "found", "path" => executable}
    assert tools["claude"]["status"] == "missing"
    assert tools["rtk"]["status"] == "missing"
    refute File.exists?(marker)
  end
end
