defmodule AgentDesk.SyncTest do
  use AgentDesk.DataCase

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Graph
  alias AgentDesk.A2A.Workflows
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Supervisor, as: ProjectSupervisor
  alias AgentDesk.Roles
  alias AgentDesk.Scope
  alias AgentDesk.Sync

  @origin "https://example.test/acme/app.git"

  setup do
    source_repo = GitRepo.tmp_repo!() |> GitRepo.set_origin!(@origin)
    dest_repo = GitRepo.tmp_repo!() |> GitRepo.set_origin!(@origin)
    other_repo = GitRepo.tmp_repo!() |> GitRepo.set_origin!("https://example.test/other/app.git")

    {:ok, source} = Projects.open_project(source_repo)
    {:ok, dest} = Projects.open_project(dest_repo)
    {:ok, other} = Projects.open_project(other_repo)

    on_exit(fn ->
      ProjectSupervisor.stop_runtime(source.id)
      ProjectSupervisor.stop_runtime(dest.id)
      ProjectSupervisor.stop_runtime(other.id)
    end)

    %{source: source, dest: dest, other: other}
  end

  test "exports a redacted bundle and imports tasks, graphs, workflows, and roles", %{
    source: source,
    dest: dest
  } do
    scope = Scope.for_project(source)
    {:ok, context} = A2A.ensure_working_context(scope)

    {:ok, prereq} =
      A2A.create_task(scope, context, %{title: "Schema", description: "token: leaked-secret"})

    {:ok, task} = A2A.create_task(scope, context, %{title: "API"})
    assert {:ok, _} = Graph.add_dependency(scope, task.id, prereq.id)

    assert {:ok, _} =
             Workflows.save(scope, %{
               name: "ship-it",
               description: "Ship the API",
               steps: ["Plan", "Implement"]
             })

    assert {:ok, _} =
             Roles.upsert(source, %{
               name: "planner",
               description: "Plans work",
               permission_profile: "observer",
               prompt: "You plan. token: also-secret"
             })

    assert {:ok, path} = Sync.export(source)
    assert File.exists?(path)

    bundle = path |> File.read!() |> Jason.decode!()
    assert bundle["format"] == "agentdesk.sync.v1"
    refute bundle["origin"] in [nil, ""]
    refute inspect(bundle) =~ "leaked-secret"
    refute inspect(bundle) =~ "also-secret"
    assert inspect(bundle) =~ "[REDACTED]"
    refute Map.has_key?(bundle, "sessions")
    refute Map.has_key?(bundle, "tokens")

    {:ok, reloaded} = Projects.get_project(source.id)
    assert reloaded.settings["sync_id"] == bundle["sync_id"]

    assert {:ok, counts} = Sync.import_bundle(dest, path)
    assert counts["tasks"] == 2

    dest_scope = Scope.for_project(dest)
    titles = dest_scope |> A2A.list_tasks() |> Enum.map(& &1.title) |> Enum.sort()
    assert titles == ["API", "Schema"]

    imported = Enum.find(A2A.list_tasks(dest_scope), &(&1.title == "API"))
    blockers = Graph.blockers(dest.id, imported.id)
    assert Enum.any?(blockers, &(&1.title == "Schema"))

    names = dest_scope |> Workflows.list() |> Enum.map(& &1.name)
    assert "ship-it" in names

    role_names = dest |> Roles.list() |> Enum.map(& &1.name)
    assert "planner" in role_names

    assert {:ok, again} = Sync.import_bundle(dest, path)
    assert again["tasks"] == 2
    assert length(A2A.list_tasks(dest_scope)) == 2
  end

  test "rejects a bundle from a different Git origin", %{source: source, other: other} do
    scope = Scope.for_project(source)
    {:ok, context} = A2A.ensure_working_context(scope)
    {:ok, _} = A2A.create_task(scope, context, %{title: "Only here"})

    assert {:ok, path} = Sync.export(source)
    assert {:error, :sync_mismatch} = Sync.import_bundle(other, path)
    assert A2A.list_tasks(Scope.for_project(other)) == []
  end
end
