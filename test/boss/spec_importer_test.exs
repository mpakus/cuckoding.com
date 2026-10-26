defmodule Boss.SpecImporterTest do
  use Boss.DataCase
  alias Boss.Projects
  alias Boss.Projects.SpecImporter

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-import-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    File.mkdir!(Path.join(root, "specs"))
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

    {:ok, project} = Projects.create_project(%{root_path: root})
    %{project: project, specs: project.specs_path, root: root}
  end

  test "three Markdown files create three tasks; repeated sync is a no-op", %{
    project: project,
    specs: specs
  } do
    File.mkdir!(Path.join(specs, "nested"))

    for file <- ["one.md", "two.MD", "nested/три.md"],
        do: File.write!(Path.join(specs, file), "# #{file}\n")

    File.write!(Path.join(specs, "ignored.txt"), "not a spec")
    assert {:ok, %{created: 3, revised: 0, missing: 0}} = SpecImporter.sync(project.id)
    first = Projects.list_spec_entries(project.id)
    assert length(first) == 3
    assert {:ok, %{created: 0, revised: 0, unchanged: 3}} = SpecImporter.sync(project.id)
    assert Projects.list_spec_entries(project.id) == first
    assert Repo.aggregate("spec_revisions", :count) == 3
  end

  test "unchanged polls do not write timestamps or retained missing rows", %{
    project: project,
    specs: specs
  } do
    File.write!(Path.join(specs, "keep.md"), "# Keep")
    File.write!(Path.join(specs, "gone.md"), "# Gone")
    assert {:ok, _} = SpecImporter.sync(project.id)
    File.rm!(Path.join(specs, "gone.md"))
    assert {:ok, %{missing: 1}} = SpecImporter.sync(project.id)
    before = Repo.all(Boss.Projects.Spec)
    observer = self()
    handler = make_ref()

    :telemetry.attach(
      handler,
      [:boss, :repo, :query],
      fn _, _, metadata, _ ->
        if Regex.match?(~r/^(UPDATE|INSERT|DELETE) /, metadata.query),
          do: send(observer, :database_write)
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, %{created: 0, revised: 0, unchanged: 1, missing: 1}} =
             SpecImporter.sync(project.id)

    assert Repo.all(Boss.Projects.Spec) == before
    refute_receive :database_write, 20
  end

  test "changed observations must settle before a revision is imported", %{
    project: project,
    specs: specs
  } do
    path = Path.join(specs, "one.md")
    File.write!(path, "# Initial")
    assert {:ok, _} = SpecImporter.sync(project.id)
    previous = Projects.list_spec_entries(project.id)
    File.write!(path, "# Intermediate")
    observer = self()
    handler = make_ref()

    :telemetry.attach(
      handler,
      [:boss, :repo, :query],
      fn _, _, metadata, _ ->
        if metadata.source == "specs" and String.contains?(metadata.query, "original_text") and
             not Process.get(handler, false) do
          Process.put(handler, true)
          send(observer, {:observed, self()})

          receive do
            :continue_scan -> :ok
          end
        end
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)
    pending = Task.async(fn -> SpecImporter.sync(project.id, settle_ms: 20) end)
    assert_receive {:observed, worker}, 1000
    File.write!(path, "# Final")
    send(worker, :continue_scan)
    assert {:error, [%{message: message}]} = Task.await(pending)
    assert message =~ "changed during sync"
    :telemetry.detach(handler)
    assert Projects.list_spec_entries(project.id) == previous
    assert {:ok, %{revised: 1}} = SpecImporter.sync(project.id, settle_ms: 20)
    assert [entry] = Projects.list_spec_entries(project.id)
    assert entry.latest_revision == 2 and entry.task_revision == 1
    assert List.last(Projects.list_spec_revisions(entry.id)).original_text == "# Final"
  end

  test "edits and A to B to A append history without changing task snapshot", %{
    project: project,
    specs: specs
  } do
    path = Path.join(specs, "one.md")

    for text <- ["# A\n", "# B\n", "# A\n"] do
      File.write!(path, text)
      assert {:ok, _} = SpecImporter.sync(project.id)
    end

    assert [entry] = Projects.list_spec_entries(project.id)
    assert entry.latest_revision == 3
    assert entry.task_revision == 1
    assert entry.title == "A"

    assert Enum.map(Projects.list_spec_revisions(entry.id), & &1.original_text) == [
             "# A\n",
             "# B\n",
             "# A\n"
           ]
  end

  test "deletion marks missing and reappearance preserves identity and history", %{
    project: project,
    specs: specs
  } do
    path = Path.join(specs, "one.md")
    File.write!(path, "# A")
    {:ok, _} = SpecImporter.sync(project.id)
    [first] = Projects.list_spec_entries(project.id)
    File.rm!(path)
    assert {:ok, %{missing: 1}} = SpecImporter.sync(project.id)
    assert [%{id: id, missing: true}] = Projects.list_spec_entries(project.id)
    assert id == first.id
    File.write!(path, "# A")
    assert {:ok, %{created: 0, revised: 0, missing: 0}} = SpecImporter.sync(project.id)
    assert Projects.list_spec_entries(project.id) == [first]
    assert length(Projects.list_spec_revisions(id)) == 1
  end

  test "rename without ID creates a new identity and retains missing history", %{
    project: project,
    specs: specs
  } do
    File.write!(Path.join(specs, "old.md"), "# A")
    {:ok, _} = SpecImporter.sync(project.id)
    [first] = Projects.list_spec_entries(project.id)
    File.rename!(Path.join(specs, "old.md"), Path.join(specs, "new.md"))
    assert {:ok, %{created: 1, missing: 1}} = SpecImporter.sync(project.id)
    assert [old, new] = Projects.list_spec_entries(project.id)
    assert old.id == first.id and old.missing
    assert new.id != old.id and not new.missing
  end

  test "explicit IDs retain identities through path swaps and old-path reuse", %{
    project: project,
    specs: specs
  } do
    a = "---\nid: alpha\n---\n# A"
    b = "---\nid: beta\n---\n# B"
    File.write!(Path.join(specs, "a.md"), a)
    File.write!(Path.join(specs, "b.md"), b)
    {:ok, _} = SpecImporter.sync(project.id)
    [first_a, first_b] = Projects.list_spec_entries(project.id)
    File.write!(Path.join(specs, "a.md"), b)
    File.write!(Path.join(specs, "b.md"), a)
    assert {:ok, %{created: 0, missing: 0}} = SpecImporter.sync(project.id)
    assert [next_a, next_b] = Projects.list_spec_entries(project.id)
    assert next_a.id == first_a.id and next_a.task_id == first_a.task_id
    assert next_a.relative_path == "b.md"
    assert next_b.id == first_b.id and next_b.relative_path == "a.md"
    assert next_a.task_revision == 1 and next_b.task_revision == 1
    File.rename!(Path.join(specs, "b.md"), Path.join(specs, "moved.md"))
    File.write!(Path.join(specs, "b.md"), "# Replacement")
    assert {:ok, %{created: 1, missing: 0}} = SpecImporter.sync(project.id)
    assert length(Projects.list_spec_entries(project.id)) == 3
  end

  test "adding an explicit ID at an occupied path preserves the former identity as missing", %{
    project: project,
    specs: specs
  } do
    path = Path.join(specs, "a.md")
    File.write!(path, "# A")
    {:ok, _} = SpecImporter.sync(project.id)
    File.write!(path, "---\nid: explicit\n---\n# A")
    assert {:ok, %{created: 1, missing: 1}} = SpecImporter.sync(project.id)
    assert [old, new] = Projects.list_spec_entries(project.id)
    assert old.missing and not new.missing
    assert old.relative_path == new.relative_path
    assert old.id != new.id
  end

  test "duplicate IDs or invalid files abort all changes including missing flags", %{
    project: project,
    specs: specs
  } do
    File.write!(Path.join(specs, "keep.md"), "# Keep")
    {:ok, _} = SpecImporter.sync(project.id)
    previous = Projects.list_spec_entries(project.id)
    File.rm!(Path.join(specs, "keep.md"))

    for bad <- ["---\nid: [not-scalar]\n---\n# Bad", <<255>>, "---\nid: [broken\n---\n# Bad"] do
      File.write!(Path.join(specs, "bad.md"), bad)
      assert {:error, [%{path: "bad.md", message: message}]} = SpecImporter.sync(project.id)
      assert is_binary(message)
      assert Projects.list_spec_entries(project.id) == previous
    end

    File.rm!(Path.join(specs, "bad.md"))

    for file <- ["a.md", "b.md"],
        do: File.write!(Path.join(specs, file), "---\nid: duplicate\n---\n# Spec")

    assert {:error, [_ | _]} = SpecImporter.sync(project.id)
    assert Projects.list_spec_entries(project.id) == previous
    assert Repo.aggregate("spec_revisions", :count) == 1
  end

  test "missing or symlinked root is an error, not a mass deletion", %{
    project: project,
    specs: specs
  } do
    File.write!(Path.join(specs, "keep.md"), "# Keep")
    {:ok, _} = SpecImporter.sync(project.id)
    previous = Projects.list_spec_entries(project.id)
    saved = specs <> "-saved"
    File.rename!(specs, saved)
    assert {:error, [_ | _]} = SpecImporter.sync(project.id)
    File.ln_s!(saved, specs)
    assert {:error, [_ | _]} = SpecImporter.sync(project.id)
    assert Projects.list_spec_entries(project.id) == previous
  end

  test "symlink files and directories and named pipes fail without following or blocking", %{
    project: project,
    specs: specs,
    root: root
  } do
    File.write!(Path.join(root, "outside.md"), "# Outside")
    path = Path.join(specs, "unsafe.md")
    File.ln_s!(Path.join(root, "outside.md"), path)
    assert {:error, [_ | _]} = SpecImporter.sync(project.id)
    File.rm!(path)
    File.ln_s!(root, Path.join(specs, "linked"))
    assert {:error, [_ | _]} = SpecImporter.sync(project.id)
    File.rm!(Path.join(specs, "linked"))
    {_, 0} = System.cmd("mkfifo", [path])
    assert {:error, [_ | _]} = SpecImporter.sync(project.id)
    assert Projects.list_spec_entries(project.id) == []
  end

  test "unreadable file preserves the existing snapshot", %{project: project, specs: specs} do
    path = Path.join(specs, "one.md")
    File.write!(path, "# A")
    {:ok, _} = SpecImporter.sync(project.id)
    previous = Projects.list_spec_entries(project.id)
    File.chmod!(path, 0o000)
    on_exit(fn -> File.chmod(path, 0o600) end)
    assert {:error, [_ | _]} = SpecImporter.sync(project.id)
    assert Projects.list_spec_entries(project.id) == previous
  end

  test "oversized files are rejected before any source is persisted", %{
    project: project,
    specs: specs
  } do
    File.write!(Path.join(specs, "large.md"), String.duplicate("x", 1_048_577))
    assert {:error, [%{path: "large.md"}]} = SpecImporter.sync(project.id)
    assert Projects.list_spec_entries(project.id) == []
  end

  test "scan bounds preserve the previous snapshot even when its source was removed", %{
    project: project,
    specs: specs
  } do
    File.write!(Path.join(specs, "keep.md"), "# Keep")
    assert {:ok, _} = SpecImporter.sync(project.id)
    previous = Projects.list_spec_entries(project.id)
    File.rm!(Path.join(specs, "keep.md"))

    for {limit, populate} <- [
          {"8 MiB",
           fn ->
             for i <- 1..9,
                 do:
                   File.write!(
                     Path.join(specs, "#{i}.md"),
                     "# Spec\n" <> String.duplicate("x", 1_048_569)
                   )
           end},
          {"1000 directory entries",
           fn ->
             for i <- 1..1001, do: File.write!(Path.join(specs, "#{i}.txt"), "")
           end},
          {"256 Markdown files",
           fn ->
             for i <- 1..257, do: File.write!(Path.join(specs, "#{i}.md"), "# Spec")
           end},
          {"directory depth of 16",
           fn ->
             File.mkdir_p!(Path.join([specs | List.duplicate("nested", 17)]))
           end}
        ] do
      populate.()
      assert {:error, [%{message: message}]} = SpecImporter.sync(project.id)
      assert message =~ limit
      assert Projects.list_spec_entries(project.id) == previous
      assert Repo.aggregate("spec_revisions", :count) == 1
      for name <- File.ls!(specs), do: File.rm_rf!(Path.join(specs, name))
    end
  end

  test "worker capacity is bounded and returns a retryable error", %{project: project} do
    workers =
      for _ <- 1..4 do
        {:ok, pid} =
          Task.Supervisor.start_child(Boss.SpecImportSupervisor, fn ->
            receive do
              :finish -> :ok
            end
          end)

        pid
      end

    on_exit(fn ->
      Enum.each(workers, &Task.Supervisor.terminate_child(Boss.SpecImportSupervisor, &1))
    end)

    assert {:error, [%{message: "Sync is busy. Try again shortly."}]} =
             SpecImporter.sync(project.id)

    assert Projects.list_spec_entries(project.id) == []
  end

  @tag skip: :os.type() != {:unix, :linux}
  test "raw Linux filenames reject the scan rather than silently marking history missing", %{
    project: project,
    specs: specs
  } do
    File.write!(Path.join(specs, "keep.md"), "# Keep")
    assert {:ok, _} = SpecImporter.sync(project.id)
    previous = Projects.list_spec_entries(project.id)
    File.rm!(Path.join(specs, "keep.md"))
    raw_path = Path.join(specs, <<255>> <> ".md")
    File.write!(raw_path, "# Raw")
    on_exit(fn -> File.rm(raw_path) end)
    assert {:error, [%{message: message}]} = SpecImporter.sync(project.id)
    assert message =~ "UTF-8"
    assert Projects.list_spec_entries(project.id) == previous
  end

  test "unknown project returns an error" do
    assert {:error, [%{message: "Project not found."}]} = SpecImporter.sync(-1)
  end
end
