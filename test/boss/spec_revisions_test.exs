defmodule Boss.SpecRevisionsTest do
  use Boss.DataCase
  alias Boss.Projects

  setup do
    project =
      Repo.insert!(%Boss.Projects.Project{
        name: "Specs",
        root_path: "/test/repo",
        git_common_dir: "/test/repo/.git",
        specs_path: "/test/repo/specs",
        base_branch: "main"
      })

    %{project: project}
  end

  test "records exact source, revision and a pinned task atomically", %{project: project} do
    text = "  # Original ü\r\n\nKeep whitespace.\n"
    assert {:ok, result} = Projects.record_spec(project.id, observation(text))
    assert result.change == :created
    assert result.spec.identity_key == "path:auth.md"
    assert result.revision.number == 1
    assert result.revision.original_text == text

    assert result.revision.content_hash ==
             Base.encode16(:crypto.hash(:sha256, text), case: :lower)

    assert result.task.spec_id == result.spec.id
    assert result.task.spec_revision_id == result.revision.id
    assert result.task.state == "new"
    assert result.task.title == "Authentication"
    assert Projects.list_spec_revisions(result.spec.id) == [result.revision]
  end

  test "repeat is a no-op but A to B to A creates three revisions without repinning", %{
    project: project
  } do
    {:ok, first} = Projects.record_spec(project.id, observation("A"))
    assert {:ok, same} = Projects.record_spec(project.id, observation("A"))
    assert same.change == :unchanged
    assert same.revision == first.revision
    assert same.task == first.task
    {:ok, second} = Projects.record_spec(project.id, observation("B"))
    {:ok, third} = Projects.record_spec(project.id, observation("A"))
    assert second.change == :revised
    assert third.change == :revised
    assert Enum.map(Projects.list_spec_revisions(first.spec.id), & &1.number) == [1, 2, 3]
    assert third.revision.content_hash == first.revision.content_hash
    assert third.revision.id != first.revision.id
    assert third.task == first.task
    assert Repo.aggregate(Boss.Tasks.Task, :count) == 1
  end

  test "explicit identity is project-scoped and cannot merge two paths", %{project: project} do
    attrs = Map.put(observation("A"), :explicit_id, "auth-login")
    {:ok, first} = Projects.record_spec(project.id, attrs)
    assert first.spec.identity_key == "id:auth-login"

    assert {:error, conflict} =
             Projects.record_spec(project.id, %{attrs | relative_path: "other.md"})

    assert %{relative_path: [_]} = errors_on(conflict)

    other =
      Repo.insert!(%Boss.Projects.Project{
        name: "Other",
        root_path: "/test/other",
        git_common_dir: "/test/other/.git",
        specs_path: "/test/other/specs",
        base_branch: "main"
      })

    assert {:ok, separate} = Projects.record_spec(other.id, attrs)
    assert separate.spec.id != first.spec.id
    assert Projects.list_spec_revisions(first.spec.id) == [first.revision]
  end

  test "changing identity at an occupied path cannot create a second task", %{project: project} do
    {:ok, first} = Projects.record_spec(project.id, observation("A"))

    assert {:error, conflict} =
             Projects.record_spec(project.id, Map.put(observation("B"), :explicit_id, "new-id"))

    assert %{relative_path: [_]} = errors_on(conflict)
    assert Repo.aggregate(Boss.Tasks.Task, :count) == 1
    assert Projects.list_spec_revisions(first.spec.id) == [first.revision]
  end

  test "invalid task rolls back the already inserted spec and revision", %{project: project} do
    assert {:error, changeset} = Projects.record_spec(project.id, %{observation("A") | title: ""})
    assert %{title: [_]} = errors_on(changeset)
    assert Repo.aggregate("specs", :count) == 0
    assert Repo.aggregate("spec_revisions", :count) == 0
    assert Repo.aggregate("tasks", :count) == 0
  end

  test "rejects unsafe paths, invalid text and absent projects without partial writes", %{
    project: project
  } do
    for path <- [
          "../outside.md",
          "/absolute.md",
          "a/../auth.md",
          "./auth.md",
          "a//auth.md",
          "bad\n.md",
          "not-markdown.txt"
        ] do
      assert {:error, _} =
               Projects.record_spec(project.id, %{observation("A") | relative_path: path})
    end

    for text <- [nil, <<255>>, String.duplicate("x", 1_048_577)] do
      assert {:error, _} =
               Projects.record_spec(project.id, %{observation("A") | original_text: text})
    end

    assert {:error, _} = Projects.record_spec(-1, observation("A"))
    assert Repo.aggregate("specs", :count) == 0
  end

  test "database rejects editing history and cross-spec task revision references", %{
    project: project
  } do
    {:ok, first} = Projects.record_spec(project.id, observation("A"))
    {:ok, unpinned} = Projects.record_spec(project.id, observation("A revised"))

    {:ok, other} =
      Projects.record_spec(project.id, %{observation("B") | relative_path: "other.md"})

    assert {:error, _} =
             Ecto.Adapters.SQL.query(
               Repo,
               "UPDATE spec_revisions SET original_text = 'changed' WHERE id = ?",
               [first.revision.id]
             )

    assert {:error, _} =
             Ecto.Adapters.SQL.query(Repo, "DELETE FROM spec_revisions WHERE id = ?", [
               unpinned.revision.id
             ])

    assert {:error, _} =
             Ecto.Adapters.SQL.query(Repo, "UPDATE tasks SET spec_revision_id = ? WHERE id = ?", [
               other.revision.id,
               first.task.id
             ])

    assert Projects.list_spec_revisions(first.spec.id) == [first.revision, unpinned.revision]
    assert Repo.get!(Boss.Tasks.Task, first.task.id).spec_revision_id == first.revision.id
  end

  test "input cannot supply database identity, hash, sequence, task state or snapshot", %{
    project: project
  } do
    attrs =
      observation("A")
      |> Map.merge(%{
        project_id: -1,
        id: 999,
        spec_id: 999,
        identity_key: "forged",
        content_hash: "forged",
        number: 99,
        spec_revision_id: 999,
        state: "done"
      })

    {:ok, first} = Projects.record_spec(project.id, attrs)
    assert first.spec.project_id == project.id
    assert first.spec.identity_key == "path:auth.md"
    assert first.revision.number == 1
    assert first.revision.content_hash != "forged"
    assert first.task.state == "new"
    assert first.task.spec_revision_id == first.revision.id
    {:ok, changed} = Projects.record_spec(project.id, %{observation("B") | title: "New title"})
    assert changed.task == first.task
  end

  test "string attributes and exact empty or whitespace source are supported", %{project: project} do
    attrs = %{"relative_path" => "nested/ü notes.md", "title" => "Notes", "original_text" => ""}
    {:ok, empty} = Projects.record_spec(project.id, attrs)
    {:ok, whitespace} = Projects.record_spec(project.id, %{attrs | "original_text" => "  \n\t"})
    assert empty.revision.original_text == ""
    assert whitespace.revision.original_text == "  \n\t"
    assert whitespace.revision.number == 2
  end

  test "invalid explicit IDs do not fall back to a path identity", %{project: project} do
    for id <- ["", "  ", " ID", "ID\n", <<255>>, String.duplicate("x", 201)] do
      assert {:error, changeset} =
               Projects.record_spec(project.id, Map.put(observation("A"), :explicit_id, id))

      assert %{explicit_id: [_]} = errors_on(changeset)
    end

    assert Repo.aggregate("specs", :count) == 0
  end

  defp observation(text),
    do: %{relative_path: "auth.md", original_text: text, title: "Authentication"}
end
