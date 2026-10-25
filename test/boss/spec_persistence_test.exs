defmodule Boss.SpecPersistenceTest do
  use ExUnit.Case, async: false
  alias Boss.{Projects, Repo}

  @migrations [
    {20_261_025_180_000, Boss.Repo.Migrations.CreateProjects},
    {20_261_025_220_000, Boss.Repo.Migrations.CreateSpecRevisions}
  ]

  setup do
    directory =
      Path.join(
        System.tmp_dir!(),
        "boss-spec-db-#{Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)}"
      )

    File.mkdir!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    {:ok, lock} = Boss.DataDirectory.acquire(directory)
    on_exit(fn -> Boss.DataDirectory.release(lock) end)

    opts = [
      name: nil,
      database: Path.join(directory, "boss.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 2
    ]

    repo = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(repo)
    Ecto.Migrator.run(Repo, @migrations, :up, to: 20_261_025_180_000, log: false)

    project =
      Repo.insert!(%Boss.Projects.Project{
        name: "Before migration",
        root_path: "/test/repo",
        git_common_dir: "/test/repo/.git",
        specs_path: "/test/repo/specs",
        base_branch: "main"
      })

    Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    %{repo: repo, opts: opts, project: project}
  end

  test "upgrade preserves projects and committed revisions survive a Repo restart", %{
    opts: opts,
    project: project
  } do
    {:ok, first} = Projects.record_spec(project.id, observation("A"))
    {:ok, second} = Projects.record_spec(project.id, observation("B"))
    assert :ok = stop_supervised(Repo)
    restarted = start_supervised!({Repo, opts})
    Repo.put_dynamic_repo(restarted)
    assert Projects.get_project!(project.id) == project
    assert Projects.list_spec_revisions(first.spec.id) == [first.revision, second.revision]
    assert Repo.get!(Boss.Tasks.Task, first.task.id) == first.task

    assert {:ok, %{change: :unchanged, task: task}} =
             Projects.record_spec(project.id, observation("B"))

    assert task.spec_revision_id == first.revision.id
  end

  test "concurrent observations produce one identity, one revision and one task", %{
    repo: repo,
    project: project
  } do
    results =
      1..8
      |> Task.async_stream(
        fn _ ->
          Repo.put_dynamic_repo(repo)
          Projects.record_spec(project.id, observation("same"))
        end,
        max_concurrency: 4,
        timeout: 10_000
      )
      |> Enum.to_list()

    assert Enum.all?(results, &match?({:ok, {:ok, _}}, &1))
    changes = Enum.map(results, fn {:ok, {:ok, result}} -> result.change end)
    assert Enum.count(changes, &(&1 == :created)) == 1
    assert Enum.count(changes, &(&1 == :unchanged)) == 7
    assert Repo.aggregate("specs", :count) == 1
    assert Repo.aggregate("spec_revisions", :count) == 1
    assert Repo.aggregate("tasks", :count) == 1
  end

  test "migration rollback and reapply preserve the pre-existing project", %{project: project} do
    {:ok, _} = Projects.record_spec(project.id, observation("A"))
    assert [20_261_025_220_000] = Ecto.Migrator.run(Repo, @migrations, :down, step: 1, log: false)
    assert Projects.get_project!(project.id) == project
    assert [20_261_025_220_000] = Ecto.Migrator.run(Repo, @migrations, :up, all: true, log: false)
    assert {:ok, %{change: :created}} = Projects.record_spec(project.id, observation("A"))
  end

  defp observation(text), do: %{relative_path: "spec.md", original_text: text, title: "Spec"}
end
