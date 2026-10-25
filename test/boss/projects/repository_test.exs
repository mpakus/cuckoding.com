defmodule Boss.Projects.RepositoryTest do
  use ExUnit.Case, async: true
  alias Boss.Projects.Repository

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-project-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir_p!(Path.join(root, "specs"))
    git!(root, ["init", "-b", "main"])

    git!(root, [
      "-c",
      "user.name=Boss Test",
      "-c",
      "user.email=test@example.invalid",
      "commit",
      "--allow-empty",
      "-m",
      "base"
    ])

    {physical, 0} = System.cmd("/bin/pwd", ["-P"], cd: root)
    root = String.trim(physical)
    %{root: root}
  end

  test "resolves a committed repository and its local base", %{root: root} do
    assert {:ok, info} = Repository.inspect(root, "specs")
    assert info.root_path == Path.expand(root)
    assert info.git_common_dir == Path.join(Path.expand(root), ".git")
    assert info.base_branch == "main"
    assert info.base_commit == git!(root, ["rev-parse", "HEAD"])
    assert info.specs_path == Path.join(info.root_path, "specs")
  end

  test "a linked worktree resolves to the same repository identity", %{root: root} do
    linked = Path.join(root, "linked")
    git!(root, ["worktree", "add", "-b", "linked", linked])
    File.mkdir!(Path.join(linked, "specs"))
    assert {:ok, first} = Repository.inspect(root, "specs")
    assert {:ok, second} = Repository.inspect(linked, "specs")
    assert first.git_common_dir == second.git_common_dir
    assert first.root_path != second.root_path
  end

  test "rejects specs outside the repository and symlink escapes", %{root: root} do
    assert {:error, :specs_outside_project} = Repository.inspect(root, "../specs")
    File.ln_s!(System.tmp_dir!(), Path.join(root, "outside"))
    assert {:error, :specs_symlink} = Repository.inspect(root, "outside")
    File.ln_s!("specs", Path.join(root, "inside"))
    assert {:error, :specs_symlink} = Repository.inspect(root, "inside")
  end

  test "rejects missing specs, missing root and unborn repository", %{root: root} do
    assert {:error, :specs_missing} = Repository.inspect(root, "missing")
    assert {:error, :invalid_repository} = Repository.inspect(root <> "-missing", "specs")
    unborn = Path.join(root, "unborn")
    File.mkdir_p!(Path.join(unborn, "specs"))
    git!(unborn, ["init", "-b", "main"])
    assert {:error, :invalid_base_branch} = Repository.inspect(unborn, "specs")
  end

  test "rejects option injection and remote or absent base branches", %{root: root} do
    for base <- ["--help", "not-present", "origin/main", "HEAD", "main\n"] do
      assert {:error, :invalid_base_branch} = Repository.inspect(root, "specs", base)
    end
  end

  defp git!(root, args) do
    {output, 0} = System.cmd("git", ["-C", root | args], stderr_to_stdout: true)
    String.trim(output)
  end
end
