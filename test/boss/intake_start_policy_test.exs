defmodule Boss.IntakeStartPolicyTest do
  use Boss.DataCase, async: false
  alias Boss.Repo
  alias Boss.Projects.{ImplementerPoolItem, Intake, Project}

  setup do
    project =
      Repo.insert!(%Project{
        name: "Policy",
        root_path: "/policy",
        git_common_dir: "/policy/.git",
        specs_path: "/policy/docs",
        base_branch: "main",
        intake_mode: "documentation"
      })

    %{project: project}
  end

  for parallel <- [false, true], loop <- [false, true] do
    @parallel parallel
    @loop loop
    test "first Start pins loop #{loop} with parallel pool #{parallel} and verifies replay", %{
      project: project
    } do
      if @parallel do
        for {model, position} <- [{"first", 0}, {"second", 1}] do
          Repo.insert!(%ImplementerPoolItem{
            project_id: project.id,
            agent_id: "codex",
            model_id: model,
            binding_tag: model,
            position: position
          })
        end
      end

      id = Ecto.UUID.generate()
      assert {:ok, {:new, r}} = Intake.admit(project.id, id, "true", "codex", false, @loop)
      assert Intake.policy(r.id) == %{version: 1, spec_loop: @loop, parallel: @parallel}
      assert Intake.latest(project.id).start_policy == r.start_policy
      Repo.delete_all(ImplementerPoolItem)

      assert {:ok, {:existing, replay}} =
               Intake.admit(project.id, id, "true", "codex", true, @loop)

      assert replay.start_policy == r.start_policy

      assert {:error, :idempotency_conflict} =
               Intake.admit(project.id, id, "true", "codex", true, !@loop)

      assert {:error, _} =
               Repo.query("UPDATE project_intakes SET start_policy=NULL WHERE id=?", [r.id])
    end
  end

  test "replan requires a completed previous brief and fresh Start cannot replay a replan UUID",
       %{project: project} do
    id = Ecto.UUID.generate()
    previous = Ecto.UUID.generate()

    assert {:error, :replan_unavailable} =
             Intake.admit(project.id, id, "true", "codex", false, false, previous)

    assert Intake.latest(project.id) == nil
    assert {:ok, {:new, _request}} = Intake.admit(project.id, id, "true", "codex", false, false)

    assert {:error, :idempotency_conflict} =
             Intake.admit(project.id, id, "true", "codex", false, false, previous)
  end

  test "conflicting task and batch requests for the whole brief save no new intent", %{project: p} do
    assert {:ok, {:new, request}} =
             Intake.admit(p.id, Ecto.UUID.generate(), "mix test", "claude", false, false)

    assert {:ok, %{task: task, revision: revision}} =
             Boss.Projects.record_spec(p.id, %{
               relative_path: "gate.md",
               title: "Gate",
               original_text: "# Gate"
             })

    Repo.query!(
      "INSERT INTO project_brief_tasks(task_id,intake_id,source_revision_id,documents) VALUES (?,?,?,?)",
      [task.id, request.id, revision.id, JSON.encode!(%{"brief.md" => "# Gate"})]
    )

    for {command, reviewer} <- [{"", "claude"}, {"mix test", "codex"}] do
      assert {:error, :brief_policy_mismatch} =
               Boss.Deliveries.Queue.admit(p.id, task.id, Ecto.UUID.generate(), command, reviewer)

      assert {:error, :brief_policy_mismatch} =
               Boss.Deliveries.Autopilot.admit(
                 p.id,
                 Ecto.UUID.generate(),
                 [task.id],
                 command,
                 reviewer
               )
    end

    assert Boss.Deliveries.Queue.list(p.id, task.id) == []
    assert {:ok, nil} = Boss.Deliveries.Autopilot.current(p.id)
  end

  test "fresh documentation Start requires a real command and saves no intent on refusal", %{
    project: project
  } do
    id = Ecto.UUID.generate()

    assert {:error, :brief_check_required} =
             Intake.admit(project.id, id, " ", "codex", false, false)

    assert Intake.latest(project.id) == nil
  end
end
