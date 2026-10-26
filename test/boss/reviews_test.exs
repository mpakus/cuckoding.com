defmodule Boss.ReviewsTest do
  use Boss.DataCase
  alias Boss.{Projects, Runs, Tasks}

  setup do
    project =
      Repo.insert!(%Projects.Project{
        name: "Reviews",
        root_path: "/reviews",
        git_common_dir: "/reviews/.git",
        specs_path: "/reviews/specs",
        base_branch: "main"
      })

    {:ok, record} =
      Projects.record_spec(project.id, %{
        relative_path: "one.md",
        title: "One",
        original_text: "# One"
      })

    {:ok, {:new, source}} = Runs.admit(project.id, record.task.id, Ecto.UUID.generate())

    {:ok, source} =
      Runs.update(source.id,
        status: "finished",
        cleanup: "group_empty",
        workspace: %{"path" => "/source"}
      )

    {:ok, {:new, check}} =
      Runs.admit_check(project.id, source.id, Ecto.UUID.generate(), "mix test")

    {:ok, check} =
      Runs.update(check.id,
        status: "finished",
        cleanup: "group_empty",
        exit_kind: "exit",
        exit_code: 0,
        candidate_commit: String.duplicate("a", 40),
        workspace: %{"path" => "/candidate"}
      )

    %{project: project, task: record.task, source: source, check: check}
  end

  test "admission pins checked input and replays the same review even while another attempt runs",
       ctx do
    command = Ecto.UUID.generate()
    assert {:ok, {:new, review}} = Runs.admit_review(ctx.project.id, ctx.check.id, command)
    assert review.adapter == "review"
    assert review.parent_run_id == ctx.check.id
    assert review.spec_revision_id == ctx.check.spec_revision_id
    assert review.candidate_commit == ctx.check.candidate_commit
    assert review.check_config == ctx.check.check_config
    assert review.config_hash == ctx.check.config_hash
    assert review.workspace == ctx.check.workspace

    assert {:ok, {:existing, ^review}} =
             Runs.admit_review(ctx.project.id, ctx.check.id, command, true)

    assert {:error, :idempotency_conflict} =
             Runs.admit_review(ctx.project.id, ctx.source.id, command)

    assert {:error, :idempotency_conflict} =
             Runs.admit_check(ctx.project.id, ctx.source.id, command, "mix test")

    assert {:error, :idempotency_conflict} = Runs.admit(ctx.project.id, ctx.task.id, command)
    assert {:error, :busy} = Runs.admit_review(ctx.project.id, ctx.check.id, Ecto.UUID.generate())
    {:ok, finished} = Runs.update(review.id, status: "failed", cleanup: "group_empty")
    {:ok, {:new, _}} = Runs.admit(ctx.project.id, ctx.task.id, Ecto.UUID.generate())

    assert {:ok, {:existing, ^finished}} =
             Runs.admit_review(ctx.project.id, ctx.check.id, command, true)

    assert Tasks.get_task!(ctx.task.id) == ctx.task
    assert Tasks.list_events(ctx.task.id) == []
  end

  test "unknown, foreign, unpassed and nested parents cannot authorize review", ctx do
    assert {:error, :not_found} =
             Runs.admit_review(ctx.project.id + 1, ctx.check.id, Ecto.UUID.generate())

    assert {:error, :invalid_command} =
             Runs.admit_review(ctx.project.id, nil, Ecto.UUID.generate())

    assert {:error, :source_unavailable} =
             Runs.admit_review(ctx.project.id, ctx.source.id, Ecto.UUID.generate())

    {:ok, {:new, check}} =
      Runs.admit_check(ctx.project.id, ctx.source.id, Ecto.UUID.generate(), "mix test")

    assert {:error, :source_unavailable} =
             Runs.admit_review(ctx.project.id, check.id, Ecto.UUID.generate())

    {:ok, _} = Runs.update(check.id, status: "failed", cleanup: "group_empty")
    {:ok, {:new, review}} = Runs.admit_review(ctx.project.id, ctx.check.id, Ecto.UUID.generate())

    assert {:error, :source_unavailable} =
             Runs.admit_review(ctx.project.id, review.id, Ecto.UUID.generate())
  end

  test "database rejects missing report/exit and altered provenance, then keeps terminal report immutable",
       ctx do
    {:ok, {:new, review}} = Runs.admit_review(ctx.project.id, ctx.check.id, Ecto.UUID.generate())

    assert {:error, :storage_error} =
             Runs.update(review.id, candidate_commit: String.duplicate("b", 40))

    assert {:error, :storage_error} = Runs.update(review.id, config_hash: "other")
    assert {:error, :storage_error} = Runs.update(review.id, parent_run_id: ctx.source.id)

    assert {:error, :storage_error} =
             Runs.update(review.id,
               status: "finished",
               cleanup: "group_empty",
               exit_kind: "exit",
               exit_code: 0
             )

    report = %{
      "verdict" => "approved",
      "summary" => "Checked",
      "acceptance" => [%{"criterion" => "One", "status" => "passed", "evidence" => "result.txt"}],
      "issues" => []
    }

    assert {:error, :storage_error} = Runs.update(review.id, review_report: report)

    assert {:error, :storage_error} =
             Runs.update(review.id,
               status: "finished",
               cleanup: "group_empty",
               review_report: report
             )

    assert {:ok, _} =
             Runs.update(review.id,
               status: "finished",
               cleanup: "group_empty",
               exit_kind: "exit",
               exit_code: 0,
               review_report: report
             )

    assert_raise Exqlite.Error, fn ->
      Repo.query!("UPDATE agent_runs SET review_report='{}' WHERE id=?", [review.id])
    end
  end

  test "latest reviews retain the full source chain once", ctx do
    for _ <- 1..12 do
      {:ok, {:new, review}} =
        Runs.admit_review(ctx.project.id, ctx.check.id, Ecto.UUID.generate())

      {:ok, _} = Runs.update(review.id, status: "failed", cleanup: "group_empty")
    end

    runs = Runs.list(ctx.project.id, ctx.task.id)
    assert length(runs) == 12
    assert Enum.count(runs, &(&1.id == ctx.check.id)) == 1
    assert Enum.count(runs, &(&1.id == ctx.source.id)) == 1
    assert Enum.count(runs, &(&1.adapter == "review")) == 10
  end
end
