defmodule Cuckoding.Knowledge.StoreTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Knowledge
  alias Cuckoding.Knowledge.Item
  alias Cuckoding.Knowledge.Parser
  alias Cuckoding.Projects
  alias Cuckoding.Repo

  @fixture_root Path.expand("../../fixtures/knowledge", __DIR__)
  @item_id "019b0000-0000-7000-8000-000000000701"
  @global_id "019b0000-0000-7000-8000-000000000702"

  setup do
    root =
      Path.join(System.tmp_dir!(), "cuckoding-knowledge-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    %{root: root, project: project(root, "a")}
  end

  test "parser preserves valid Markdown bytes and rejects invalid front matter" do
    valid = fixture("valid.md")
    raw = File.read!(valid)

    assert {:ok, document} = Parser.parse_file(valid)
    assert document.raw == raw

    assert document.body ==
             "# Durable workflow state\n\nSQLite is authoritative; workers reconstruct from durable identifiers.\n"

    assert document.metadata.id == @item_id
    assert document.metadata.scope == "project"
    assert byte_size(document.hash) == 64

    assert {:error, :invalid_knowledge_id} = Parser.parse_file(fixture("invalid.md"))

    duplicate = String.replace(raw, "kind: fact", "kind: fact\nkind: recipe")
    assert {:error, :duplicate_knowledge_field} = Parser.parse(duplicate)
  end

  test "sync mirrors front matter, flags edits, and accepts only an explicit newer user revision",
       %{
         project: project
       } do
    assert {:ok, root} = Knowledge.ensure_project_layout(project)
    path = Path.join(root, "facts/durable-state.md")
    File.cp!(fixture("valid.md"), path)

    assert {:ok, %{inserted: [@item_id], errors: []}} = Knowledge.sync_project(project)
    indexed = Repo.get!(Item, @item_id)
    assert indexed.title == "Use durable workflow state"
    assert indexed.version == 1
    assert indexed.sync_state == "synced"

    assert {:ok, %{document: document}} = Knowledge.read_for_project(project.id, @item_id)
    assert document.raw == File.read!(fixture("valid.md"))

    assert {:ok, %{unchanged: [@item_id], errors: []}} = Knowledge.sync_project(project)

    File.cp!(fixture("hand-edited.md"), path)
    assert {:ok, %{modified: [@item_id], errors: []}} = Knowledge.sync_project(project)

    flagged = Repo.get!(Item, @item_id)
    assert flagged.title == "Use durable workflow state"
    assert flagged.version == 1
    assert flagged.sync_state == "modified"
    assert flagged.observed_hash != flagged.content_hash

    assert {:error, :knowledge_content_hash_mismatch} =
             Knowledge.read_for_project(project.id, @item_id)

    assert {:ok, accepted} = Knowledge.accept_user_edit(project, @item_id)
    assert accepted.title == "Use durable workflow state after restart"
    assert accepted.version == 2
    assert accepted.revision_source == "user"
    assert accepted.sync_state == "synced"
    assert accepted.observed_hash == accepted.content_hash

    assert {:ok, %{document: revised}} = Knowledge.read_for_project(project.id, @item_id)
    assert revised.raw == File.read!(fixture("hand-edited.md"))

    File.rm!(path)
    assert {:ok, %{missing: [@item_id]}} = Knowledge.sync_project(project)
    assert Repo.get!(Item, @item_id).sync_state == "missing"
  end

  test "same-version edits remain flagged and cannot be silently accepted", %{project: project} do
    assert {:ok, root} = Knowledge.ensure_project_layout(project)
    path = Path.join(root, "facts/durable-state.md")
    File.cp!(fixture("valid.md"), path)
    assert {:ok, _result} = Knowledge.sync_project(project)

    File.write!(path, File.read!(fixture("valid.md")) <> "\nHand edit without a version bump.\n")
    assert {:ok, %{modified: [@item_id]}} = Knowledge.sync_project(project)

    assert {:error, :knowledge_version_must_increase} =
             Knowledge.accept_user_edit(project, @item_id)

    assert Repo.get!(Item, @item_id).version == 1
  end

  test "invalid and symlinked files never enter the index", %{root: temp, project: project} do
    assert {:ok, root} = Knowledge.ensure_project_layout(project)
    invalid = Path.join(root, "facts/invalid.md")
    linked = Path.join(root, "facts/linked.md")
    outside = Path.join(temp, "outside.md")
    File.cp!(fixture("invalid.md"), invalid)
    File.cp!(fixture("valid.md"), outside)
    File.ln_s!(outside, linked)

    assert {:ok, result} = Knowledge.sync_project(project)
    assert Enum.any?(result.errors, &(&1.path == "facts/invalid.md"))
    assert Enum.any?(result.errors, &(&1 == %{path: "facts/linked.md", reason: :file_symlink}))
    refute Repo.get(Item, @item_id)
  end

  test "replacing an indexed file with a symlink marks the mirror invalid", %{
    root: temp,
    project: project
  } do
    assert {:ok, root} = Knowledge.ensure_project_layout(project)
    path = Path.join(root, "facts/durable-state.md")
    outside = Path.join(temp, "outside.md")
    File.cp!(fixture("valid.md"), path)
    File.cp!(fixture("valid.md"), outside)
    assert {:ok, _result} = Knowledge.sync_project(project)

    File.rm!(path)
    File.ln_s!(outside, path)
    assert {:ok, %{invalid: [@item_id]} = result} = Knowledge.sync_project(project)

    assert Enum.any?(
             result.errors,
             &(&1 == %{path: "facts/durable-state.md", reason: :file_symlink})
           )

    assert Repo.get!(Item, @item_id).sync_state == "invalid"
    assert {:error, :knowledge_file_symlink} = Knowledge.read_for_project(project.id, @item_id)
  end

  test "project items never cross project boundaries and global reads require opt-in", %{
    root: temp,
    project: project_a
  } do
    project_b = project(temp, "b")
    assert {:ok, project_root} = Knowledge.ensure_project_layout(project_a)
    File.cp!(fixture("valid.md"), Path.join(project_root, "facts/durable-state.md"))
    assert {:ok, _result} = Knowledge.sync_project(project_a)

    assert {:error, :knowledge_scope_refused} =
             Knowledge.read_for_project(project_b.id, @item_id)

    global_root = Path.join(temp, "global")
    assert {:ok, ^global_root} = Knowledge.ensure_global_layout(global_root: global_root)
    File.cp!(fixture("global.md"), Path.join(global_root, "patterns/persist-first.md"))

    assert {:ok, %{inserted: [@global_id], errors: []}} =
             Knowledge.sync_global(global_root: global_root)

    assert {:error, :global_knowledge_not_enabled} =
             Knowledge.read_for_project(project_b.id, @global_id, global_root: global_root)

    assert {:ok, %{document: global}} =
             Knowledge.read_for_project(project_b.id, @global_id,
               global_root: global_root,
               include_global: true
             )

    assert global.raw == File.read!(fixture("global.md"))
  end

  defp project(root, suffix) do
    repo = Path.join(root, "repo-#{suffix}")
    workspace = Path.join(root, "workspace-#{suffix}")
    File.mkdir_p!(repo)
    File.mkdir_p!(workspace)

    {:ok, project} =
      Projects.register(%{
        name: "Knowledge #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: 48_000,
        port_range_end: 48_100
      })

    project
  end

  defp fixture(name), do: Path.join(@fixture_root, name)
end
