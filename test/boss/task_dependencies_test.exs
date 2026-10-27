defmodule Boss.Tasks.DependenciesTest do
  use Boss.DataCase
  alias Boss.Projects
  alias Boss.Projects.Spec
  alias Boss.Tasks.{Dependencies, Task}

  setup do
    %{project: project("dependencies")}
  end

  test "no dependencies are ready and checks are read only", %{project: project} do
    task = task(project, "root")
    before = Repo.get!(Task, task.id)

    assert {:ok, %{ready?: true, dependencies: [], issues: []}} = snapshot(project, task)
    assert :ok = check(project, task)
    assert Repo.get!(Task, task.id) == before
    assert Repo.all(Boss.Tasks.Event) == []
    assert {:error, :not_found} = Dependencies.snapshot(project.id, task.id + 1000)
    assert {:error, :not_found} = Dependencies.check("bad", task.id)
  end

  test "only Done satisfies direct edges and declaration order is retained", %{project: project} do
    done = task(project, "done", [], "done")
    ready = task(project, "ready", [], "ready")
    cancelled = task(project, "cancelled", [], "cancelled")
    blocked = task(project, "blocked", [], "blocked")
    root = task(project, "root", ["done", "ready", "cancelled", "blocked"])

    assert {:ok, result} = snapshot(project, root)
    refute result.ready?

    assert Enum.map(result.dependencies, & &1.task_id) == [
             done.id,
             ready.id,
             cancelled.id,
             blocked.id
           ]

    assert Enum.map(result.dependencies, & &1.satisfied?) == [true, false, false, false]

    assert Enum.map(result.issues, &{&1.kind, &1.reference}) == [
             waiting: "ready",
             waiting: "cancelled",
             waiting: "blocked"
           ]

    assert {:error, {:dependencies_blocked, ^result}} = check(project, root)
  end

  test "references use explicit IDs in the same project and never filename aliases", %{
    project: project
  } do
    target = task(project, "target", [], "done")
    other = project("other")
    foreign = task(other, "foreign", [], "done")

    {:ok, _} =
      Projects.record_spec(project.id, %{
        relative_path: "path-only.md",
        original_text: "# Path",
        title: "Path"
      })

    root = task(project, "root", ["target", "target.md", "path-only", "foreign"])
    assert {:ok, result} = snapshot(project, root)
    assert Enum.map(result.dependencies, & &1.task_id) == [target.id, nil, nil, nil]

    assert Enum.map(result.issues, &{&1.kind, &1.reference}) == [
             missing: "target.md",
             missing: "path-only",
             missing: "foreign"
           ]

    assert {:error, :not_found} = Dependencies.snapshot(project.id, foreign.id)
  end

  test "root and dependency declarations remain pinned after later revisions", %{project: project} do
    dependency = task(project, "dependency", [], "done")
    root = task(project, "root", ["dependency"])
    record(project, "dependency", ["root"])
    record(project, "root", ["unknown"])

    assert {:ok, %{ready?: true, issues: [], dependencies: [entry]}} = snapshot(project, root)
    assert entry.task_id == dependency.id
    assert entry.satisfied?
  end

  test "a diamond visits shared nodes once and ignores unrelated invalid graphs", %{
    project: project
  } do
    task(project, "shared")
    task(project, "left", ["shared"], "done")
    task(project, "right", ["shared"], "done")
    task(project, "unrelated", ["unrelated"])
    root = task(project, "root", ["left", "right"])

    assert {:ok, %{ready?: true, issues: [], dependencies: [_, _]}} = snapshot(project, root)
  end

  test "self cycles and transitive cycles through Done tasks block", %{project: project} do
    self_cycle = task(project, "self", ["self"])
    assert {:ok, %{ready?: false, issues: issues}} = snapshot(project, self_cycle)
    assert Enum.any?(issues, &(&1.kind == :cycle and &1.task_id == self_cycle.id))

    task(project, "one", ["two"], "done")
    task(project, "two", ["one"], "done")
    root = task(project, "root", ["one"])

    assert {:ok, %{ready?: false, issues: [%{kind: :cycle}], dependencies: [entry]}} =
             snapshot(project, root)

    assert entry.satisfied?
  end

  test "missing source is allowed only for Done and nested missing source blocks", %{
    project: project
  } do
    completed = task(project, "completed", [], "done")
    missing(completed)
    root = task(project, "root", ["completed"])

    assert {:ok, %{ready?: true, dependencies: [%{missing: true, satisfied?: true}]}} =
             snapshot(project, root)

    unfinished = task(project, "unfinished")
    missing(unfinished)
    task(project, "parent", ["unfinished"], "done")
    root = task(project, "nested-root", ["parent"])

    assert {:ok, %{ready?: false, issues: [%{kind: :missing, task_id: task_id}]}} =
             snapshot(project, root)

    assert task_id == unfinished.id
  end

  test "malformed pinned source and unknown nested IDs block even through Done", %{
    project: project
  } do
    {:ok, malformed} =
      Projects.record_spec(project.id, %{
        relative_path: "malformed.md",
        explicit_id: "malformed",
        original_text: "---\ndepends_on: {}\n---",
        title: "Malformed"
      })

    set_state(malformed.task, "done")
    root = task(project, "root", ["malformed"])
    assert {:ok, %{ready?: false, issues: [%{kind: :invalid}]}} = snapshot(project, root)

    assert {:ok, %{ready?: false, dependencies: [], issues: [%{kind: :invalid}]}} =
             snapshot(project, malformed.task)

    task(project, "parent", ["absent"], "done")
    nested = task(project, "nested", ["parent"])

    assert {:ok, %{ready?: false, issues: [%{kind: :missing, reference: "absent"}]}} =
             snapshot(project, nested)
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

  defp task(project, id, dependencies \\ [], state \\ "new") do
    task = record(project, id, dependencies).task
    set_state(task, state)
    task
  end

  defp record(project, id, dependencies) do
    source =
      "---\nid: #{Jason.encode!(id)}\ndepends_on: #{Jason.encode!(dependencies)}\n---\n# #{id}"

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "#{id}.md",
        explicit_id: id,
        original_text: source,
        title: id
      })

    record
  end

  # These read-model fixtures represent persisted states; they do not produce delivery evidence.
  defp set_state(task, state),
    do: Repo.update_all(from(task in Task, where: task.id == ^task.id), set: [state: state])

  defp missing(task),
    do: Repo.update_all(from(spec in Spec, where: spec.id == ^task.spec_id), set: [missing: true])

  defp snapshot(project, task) do
    {:ok, result} = Repo.transaction(fn -> Dependencies.snapshot(project.id, task.id) end)
    result
  end

  defp check(project, task) do
    {:ok, result} = Repo.transaction(fn -> Dependencies.check(project.id, task.id) end)
    result
  end
end
