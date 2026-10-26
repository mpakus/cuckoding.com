defmodule Boss.TaskDetailsTest do
  use Boss.DataCase
  alias Boss.{Projects, Tasks}

  setup do
    project = project("details")
    source = "---\nid: stable\n---\n# Original\n<script>alert('source')</script> & <b>raw</b>\r\n"
    {:ok, first} = record(project.id, "one.md", source, "Original")
    %{project: project, first: first, source: source}
  end

  test "details default to the pinned revision after source edits", %{
    project: project,
    first: first,
    source: source
  } do
    {:ok, second} = record(project.id, "one.md", "# Second", "Second")
    assert {:ok, detail} = Tasks.get_details(project.id, first.task.id)
    assert detail.task == first.task
    assert detail.spec == second.spec
    assert detail.pinned_revision == first.revision
    assert detail.selected_revision == first.revision
    assert detail.latest_revision == second.revision
    assert detail.selected_revision.original_text == source
    assert detail.events == []

    assert detail.revisions == [
             %{number: 2, inserted_at: second.revision.inserted_at},
             %{number: 1, inserted_at: first.revision.inserted_at}
           ]

    assert Enum.all?(detail.revisions, &(Enum.sort(Map.keys(&1)) == [:inserted_at, :number]))
  end

  test "a selected historical revision belongs to the same spec and does not change the pin", %{
    project: project,
    first: first
  } do
    {:ok, second} = record(project.id, "one.md", "# Second", "Second")
    {:ok, third} = record(project.id, "one.md", "# Latest", "Latest")
    assert {:ok, detail} = Tasks.get_details(project.id, first.task.id, 2)
    assert detail.selected_revision == second.revision
    assert detail.pinned_revision == first.revision
    assert detail.latest_revision == third.revision
    assert detail.task.spec_revision_id == first.revision.id
    assert Tasks.get_task!(first.task.id) == first.task
  end

  test "retained missing specs keep their task details and original source", %{
    project: project,
    first: first,
    source: source
  } do
    {1, _} =
      Repo.update_all(from(s in Projects.Spec, where: s.id == ^first.spec.id),
        set: [missing: true]
      )

    assert {:ok, detail} = Tasks.get_details(project.id, first.task.id)
    assert detail.spec.missing
    assert detail.pinned_revision.original_text == source
    assert detail.selected_revision == detail.pinned_revision
  end

  test "foreign tasks and revisions are indistinguishable from missing records", %{
    project: project,
    first: first
  } do
    other_project = project("foreign")
    {:ok, foreign} = record(other_project.id, "foreign.md", "# Secret", "Secret")
    {:ok, _} = record(other_project.id, "foreign.md", "# Secret version two", "Secret")
    {:ok, _} = record(project.id, "other.md", "# Another spec", "Another")
    {:ok, _} = record(project.id, "other.md", "# Another spec two", "Another")

    assert {:error, :not_found} = Tasks.get_details(project.id, foreign.task.id)
    assert {:error, :not_found} = Tasks.get_details(other_project.id, first.task.id)
    assert {:error, :not_found} = Tasks.get_details(project.id, first.task.id, 2)
    assert {:error, :not_found} = Tasks.get_details(project.id + 10_000, first.task.id)
    assert {:error, :not_found} = Tasks.get_details(project.id, first.task.id + 10_000)
  end

  test "invalid IDs and revision numbers are rejected before storage", %{
    project: project,
    first: first
  } do
    for invalid <- [nil, 0, -1, 1.0, "1", %{}, 9_223_372_036_854_775_808] do
      assert {:error, :not_found} = Tasks.get_details(invalid, first.task.id)
      assert {:error, :not_found} = Tasks.get_details(project.id, invalid)

      unless is_nil(invalid),
        do: assert({:error, :not_found} = Tasks.get_details(project.id, first.task.id, invalid))
    end
  end

  test "details contain only the latest 50 task events in descending version order", %{
    project: project,
    first: first,
    source: source
  } do
    for version <- 0..54 do
      action = if rem(version, 2) == 0, do: "block", else: "resume"
      reason = if action == "block", do: "<script>literal reason #{version}</script>", else: nil

      assert {:ok, _} =
               Tasks.transition(first.task.id, %{
                 command_id: "detail-#{version}",
                 expected_version: version,
                 action: action,
                 reason: reason
               })
    end

    {:ok, other} = record(project.id, "other.md", "# Other", "Other")

    assert {:ok, _} =
             Tasks.transition(other.task.id, %{
               command_id: "other",
               expected_version: 0,
               action: "cancel",
               reason: "Other reason"
             })

    assert {:ok, detail} = Tasks.get_details(project.id, first.task.id)
    assert Enum.map(detail.events, & &1.version) == Enum.to_list(55..6//-1)

    assert Enum.all?(
             detail.events,
             &(&1.task_id == first.task.id and &1.spec_revision_id == first.revision.id)
           )

    assert hd(detail.events).reason == "<script>literal reason 54</script>"
    assert detail.task.state_version == 55
    assert detail.pinned_revision.original_text == source
  end

  test "all detail queries use the pinned Repo PID and restore the caller selector", %{
    project: project,
    first: first
  } do
    selector = Repo.get_dynamic_repo()
    repo = Process.whereis(Repo)
    handler = make_ref()
    owner = self()

    :ok =
      :telemetry.attach(
        handler,
        [:boss, :repo, :query],
        fn _, _, metadata, _ ->
          if self() == owner and String.starts_with?(metadata.query, "SELECT") do
            send(owner, {handler, Repo.get_dynamic_repo()})
          end
        end,
        nil
      )

    on_exit(fn -> :telemetry.detach(handler) end)

    assert {:ok, _} = Tasks.get_details(project.id, first.task.id)
    assert Repo.get_dynamic_repo() == selector
    assert_receive {^handler, ^repo}
    refute_receive {^handler, ^selector}
  end

  test "unavailable storage returns a safe error and restores the selector", %{
    project: project,
    first: first
  } do
    original = Repo.get_dynamic_repo()
    {dead, monitor} = spawn_monitor(fn -> :ok end)
    assert_receive {:DOWN, ^monitor, :process, ^dead, _}

    try do
      for selector <- [Boss.TaskDetailsUnavailableRepo, dead] do
        Repo.put_dynamic_repo(selector)
        assert {:error, :storage_error} = Tasks.get_details(project.id, first.task.id)
        assert Repo.get_dynamic_repo() == selector
        assert {:error, :not_found} = Tasks.get_details(project.id, first.task.id, -1)
      end
    after
      Repo.put_dynamic_repo(original)
    end
  end

  defp project(name) do
    Repo.insert!(%Projects.Project{
      name: name,
      root_path: "/test/#{name}",
      git_common_dir: "/test/#{name}/.git",
      specs_path: "/test/#{name}/specs",
      base_branch: "main"
    })
  end

  defp record(project_id, path, source, title),
    do:
      Projects.record_spec(project_id, %{relative_path: path, original_text: source, title: title})
end
