defmodule Boss.ChecksTest do
  use Boss.DataCase
  alias Boss.{Projects, Runs, Tasks}
  alias Boss.Checks.Command

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Checks",
        root_path: "/checks",
        git_common_dir: "/checks/.git",
        specs_path: "/checks/specs",
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(
        project.id,
        %{relative_path: "one.md", title: "Pinned", original_text: "# Pinned"}
      )

    {:ok, {:new, parent}} = Runs.admit(project.id, record.task.id, Ecto.UUID.generate())

    {:ok, parent} =
      Runs.update(parent.id,
        workspace: %{"path" => "/retained"},
        status: "finished",
        cleanup: "group_empty"
      )

    %{project: project, task: record.task, parent: parent}
  end

  test "commands preserve argv literally and reject empty, multiline or malformed input" do
    assert {:ok, config, hash} = Command.parse(~s(printf "$HOME && echo unsafe"))
    assert config["argv"] == ["printf", "$HOME && echo unsafe"]
    assert {:ok, ^config, ^hash} = Command.parse(~s(  printf   '$HOME && echo unsafe'  ))

    for bad <- [
          nil,
          " ",
          "echo\nother",
          <<0>>,
          <<255>>,
          "echo 'unfinished",
          String.duplicate("x", 4097)
        ] do
      assert {:error, :invalid_command} = Command.parse(bad)
    end
  end

  test "checks pin parent/revision/config and share global admission with Codex", ctx do
    id = Ecto.UUID.generate()
    assert {:ok, {:new, check}} = Runs.admit_check(ctx.project.id, ctx.parent.id, id, "mix test")

    assert check.parent_run_id == ctx.parent.id and
             check.spec_revision_id == ctx.task.spec_revision_id

    assert check.check_config["argv"] == ["mix", "test"]

    assert {:ok, {:existing, ^check}} =
             Runs.admit_check(ctx.project.id, ctx.parent.id, id, "mix   test", true)

    assert {:error, :idempotency_conflict} =
             Runs.admit_check(ctx.project.id, ctx.parent.id, id, "mix compile", true)

    assert {:error, :idempotency_conflict} = Runs.admit(ctx.project.id, ctx.task.id, id)
    assert {:error, :idempotency_conflict} = Runs.replay(ctx.project.id, ctx.task.id, id)

    assert {:error, :idempotency_conflict} =
             Runs.admit_check(ctx.project.id, ctx.parent.id, ctx.parent.command_id, "mix test")

    assert {:error, :busy} = Runs.admit(ctx.project.id, ctx.task.id, Ecto.UUID.generate())
    assert Tasks.get_task!(ctx.task.id) == ctx.task
    assert Tasks.list_events(ctx.task.id) == []
  end

  test "cross-project, unfinished and nested sources cannot start checks", ctx do
    assert {:error, :not_found} =
             Runs.admit_check(ctx.project.id + 1, ctx.parent.id, Ecto.UUID.generate(), "mix test")

    {:ok, {:new, active}} = Runs.admit(ctx.project.id, ctx.task.id, Ecto.UUID.generate())

    assert {:error, :source_unavailable} =
             Runs.admit_check(ctx.project.id, active.id, Ecto.UUID.generate(), "mix test")

    {:ok, _} = Runs.update(active.id, status: "failed", cleanup: "group_empty")

    {:ok, {:new, check}} =
      Runs.admit_check(ctx.project.id, ctx.parent.id, Ecto.UUID.generate(), "mix test")

    {:ok, _} = Runs.update(check.id, status: "finished", cleanup: "group_empty")

    assert {:error, :source_unavailable} =
             Runs.admit_check(ctx.project.id, check.id, Ecto.UUID.generate(), "mix test")
  end

  test "database provenance and candidate commit are immutable; incomplete checks quarantine",
       ctx do
    {:ok, {:new, check}} =
      Runs.admit_check(ctx.project.id, ctx.parent.id, Ecto.UUID.generate(), "mix test")

    assert {:error, :storage_error} = Runs.update(check.id, parent_run_id: nil)
    assert {:error, :storage_error} = Runs.update(check.id, config_hash: nil)
    assert {:error, :storage_error} = Runs.update(check.id, check_config: %{"argv" => ["other"]})
    sha = String.duplicate("a", 40)
    assert {:ok, _} = Runs.update(check.id, candidate_commit: sha)
    assert {:error, :storage_error} = Runs.update(check.id, candidate_commit: nil)
    assert {:ok, {1, _}} = Runs.reconcile()
    saved = Runs.get(ctx.project.id, check.id)
    assert saved.status == "interrupted" and saved.cleanup == "unknown"
    assert saved.candidate_commit == sha

    assert {:error, :busy} =
             Runs.admit_check(ctx.project.id, ctx.parent.id, Ecto.UUID.generate(), "mix test")
  end
end
