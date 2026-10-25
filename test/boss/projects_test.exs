defmodule Boss.ProjectsTest do
  use Boss.DataCase
  alias Boss.Projects

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-create-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir_p!(Path.join(root, "specs"))
    {_, 0} = System.cmd("git", ["-C", root, "init", "-b", "main"])

    {_, 0} =
      System.cmd("git", [
        "-C",
        root,
        "-c",
        "user.name=Test",
        "-c",
        "user.email=test@example.invalid",
        "commit",
        "--allow-empty",
        "-m",
        "base"
      ])

    %{root: root}
  end

  test "registers canonical repository fields and persists a project", %{root: root} do
    assert {:ok, project} = Projects.create_project(%{root_path: root})
    assert project.name == Path.basename(root)
    assert project.base_branch == "main"
    assert project.specs_path == Path.join(project.root_path, "specs")
    assert Projects.get_project!(project.id) == project
    assert Projects.list_projects() == [project]
  end

  test "same Git common directory cannot register twice", %{root: root} do
    assert {:ok, _} = Projects.create_project(%{root_path: root})
    assert {:error, changeset} = Projects.create_project(%{root_path: root, name: "other"})
    assert %{git_common_dir: [_]} = errors_on(changeset)

    linked = Path.join(root, "linked")

    {_, 0} =
      System.cmd("git", ["-C", root, "worktree", "add", "-b", "linked", linked],
        stderr_to_stdout: true
      )

    File.mkdir!(Path.join(linked, "specs"))
    assert {:error, linked_error} = Projects.create_project(%{root_path: linked})
    assert %{git_common_dir: [_]} = errors_on(linked_error)
    assert length(Projects.list_projects()) == 1
  end

  test "invalid project input leaves no partially registered project", %{root: root} do
    assert {:error, changeset} =
             Projects.create_project(%{root_path: root, specs_path: "../escape"})

    assert %{root_path: [_]} = errors_on(changeset)
    assert Projects.list_projects() == []
    assert {:error, _} = Projects.create_project(%{})
  end
end
