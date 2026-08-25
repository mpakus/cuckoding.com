defmodule AgentDesk.PathsTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Paths

  test "expands and accepts an existing directory" do
    dir = tmp_dir!("path-canon")
    File.mkdir_p!(dir)

    assert {:ok, canonical} = Paths.canonicalize(Path.join(dir, "."))
    assert File.stat!(canonical).inode == File.stat!(dir).inode
  end

  test "returns not_found for a missing path" do
    assert Paths.canonicalize(
             "/definitely/missing/agentdesk-#{System.unique_integer([:positive])}"
           ) ==
             {:error, :not_found}
  end

  test "returns not_a_directory for a file" do
    dir = tmp_dir!("path-file")
    file = Path.join(dir, "file")
    File.mkdir_p!(dir)
    File.write!(file, "x")

    assert Paths.canonicalize(file) == {:error, :not_a_directory}
  end

  test "within? allows files under the root and rejects escapes" do
    dir = tmp_dir!("path-within")
    File.mkdir_p!(dir)
    file = Path.join(dir, "notes.txt")
    File.write!(file, "ok")

    assert Paths.within?(dir, file)
    refute Paths.within?(dir, Path.join(dir, "../outside.txt"))
  end

  test "within? rejects a file reached through a symlinked ancestor outside the root" do
    base = tmp_dir!("path-symlink")
    root = Path.join(base, "root")
    outside = Path.join(base, "outside")
    File.mkdir_p!(root)
    File.mkdir_p!(outside)
    File.write!(Path.join(outside, "secret.txt"), "secret")
    File.ln_s!(outside, Path.join(root, "linked"))

    refute Paths.within?(root, Path.join([root, "linked", "secret.txt"]))
  end

  test "safe_path returns the canonical file used after containment checks" do
    base = tmp_dir!("path-canonical-safe")
    root = Path.join(base, "root")
    target = Path.join(root, "target")
    File.mkdir_p!(target)
    File.write!(Path.join(target, "notes.txt"), "safe")
    File.ln_s!("target", Path.join(root, "linked"))

    assert {:ok, canonical} = Paths.safe_path(root, "linked/notes.txt")
    assert {:ok, canonical_target} = Paths.canonicalize(target)
    assert canonical == Path.join(canonical_target, "notes.txt")
  end

  test "read_bounded_regular returns only stable regular files" do
    root = tmp_dir!("bounded-regular")
    File.mkdir_p!(root)
    path = Path.join(root, "notes.txt")
    File.write!(path, "safe")

    assert {:ok, canonical, "safe"} = Paths.read_bounded_regular(root, "notes.txt", 10)
    assert File.stat!(canonical).inode == File.stat!(path).inode
    assert {:error, :too_large} = Paths.read_bounded_regular(root, "notes.txt", 3)
  end

  test "read_bounded_regular rejects the final symlink without following it" do
    root = tmp_dir!("bounded-symlink")
    File.mkdir_p!(root)
    File.write!(Path.join(root, "target.txt"), "secret")
    File.ln_s!("target.txt", Path.join(root, "linked.txt"))

    assert {:error, :not_regular} =
             Paths.read_bounded_regular(root, "linked.txt", 1_000)
  end

  test "read_bounded_regular detects a replacement after validation" do
    root = tmp_dir!("bounded-pre-open-swap")
    File.mkdir_p!(root)
    path = Path.join(root, "notes.txt")
    replacement = Path.join(root, "replacement.txt")
    File.write!(path, "original")
    File.write!(replacement, "replacement")

    on_phase = fn
      :validated -> File.rename!(replacement, path)
      _phase -> :ok
    end

    assert {:error, :file_changed} =
             Paths.read_bounded_regular(root, "notes.txt", 1_000, on_phase: on_phase)
  end

  test "read_bounded_regular detects a path replacement after opening" do
    root = tmp_dir!("bounded-post-open-swap")
    File.mkdir_p!(root)
    path = Path.join(root, "notes.txt")
    replacement = Path.join(root, "replacement.txt")
    File.write!(path, "original")
    File.write!(replacement, "replacement")

    on_phase = fn
      :opened -> File.rename!(replacement, path)
      _phase -> :ok
    end

    assert {:error, :file_changed} =
             Paths.read_bounded_regular(root, "notes.txt", 1_000, on_phase: on_phase)
  end

  defp tmp_dir!(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-#{name}-#{System.unique_integer([:positive, :monotonic])}"
      )

    on_exit(fn -> File.rm_rf(dir) end)
    dir
  end
end
