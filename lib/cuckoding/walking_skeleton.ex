defmodule Cuckoding.WalkingSkeleton do
  @moduledoc "The bounded Phase 4 project-to-release product loop."

  import Ecto.Query

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.FakeAdapter
  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.Lifecycle
  alias Cuckoding.Execution.LocalBareRemote
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.PortAllocator
  alias Cuckoding.Execution.ProtectedPaths
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Knowledge
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.Approval
  alias Cuckoding.Workflows.Definition
  alias Cuckoding.Workflows.GateEvaluator
  alias Cuckoding.Workflows.Task

  @doc "Creates one project, default board, ready task, run, and confined host worktree."
  def create(attrs) when is_map(attrs) do
    with {:ok, project} <- Projects.register(project_attrs(attrs)),
         {:ok, policy} <- Projects.add_config_version(policy_attrs(project, attrs)),
         {:ok, workflow} <- Workflows.publish_workflow(workflow_attrs(project)),
         {:ok, board} <- Workflows.create_board(board_attrs(project, workflow, attrs)),
         :ok <- assign_roles(board, Map.get(attrs, :adapter_key, "fake")),
         {:ok, task} <- Workflows.create_task(task_attrs(board, attrs)),
         {:ok, ready} <- Workflows.transition_task(task.id, "ready", "walking:#{task.id}:ready"),
         true <- ready.result["outcome"] == "transitioned",
         {:ok, base_sha} <- GitService.capture_base(project),
         {:ok, run} <- Execution.create_run(run_attrs(task, policy, base_sha)),
         {:ok, environment} <- GitService.prepare(project, run),
         {:ok, environment} <- LocalProcessRunner.prepare(environment, []),
         {:ok, started} <-
           Execution.transition_run(run.id, "running", "walking:#{run.id}:running"),
         true <- started.result["outcome"] == "transitioned" do
      {:ok,
       %{
         project: project,
         board: board,
         task: Repo.get!(Task, task.id),
         run: Repo.get!(Run, run.id),
         environment: environment
       }}
    else
      false -> {:error, :transition_rejected}
      error -> error
    end
  end

  @doc "Runs specification, development, and QA, then stops at human approval."
  def run(
        %{run: %Run{} = run, environment: %Environment{}} = skeleton,
        options \\ []
      ) do
    adapter = Keyword.get(options, :adapter, FakeAdapter)

    with {:ok, spec} <- run_stage(skeleton, "specification", "spec_writer", adapter, options),
         environment = spec.environment,
         {:ok, spec_artifact} <-
           write_artifact(
             environment,
             "specification",
             "specification.md",
             specification(skeleton.task)
           ),
         {:ok, development} <-
           run_stage(
             %{skeleton | environment: environment},
             "development",
             "implementer",
             adapter,
             options
           ),
         {:ok, environment} <-
           candidate(development, environment, adapter, skeleton.task, options),
         {:ok, qa} <-
           run_stage(%{skeleton | environment: environment}, "qa", "reviewer", adapter, options),
         {:ok, qa_artifact} <-
           write_artifact(environment, "qa_report", "qa.md", qa_report(environment)),
         {:ok, knowledge} <- write_knowledge_candidate(environment, skeleton.task),
         {:ok, evidence} <-
           write_evidence(
             environment,
             run,
             adapter,
             [spec, development, qa],
             [spec_artifact, qa_artifact],
             knowledge
           ),
         {:ok, approval_attempt} <- human_approval_attempt(run),
         {:ok, approval} <-
           Workflows.request_approval(%{
             run_id: run.id,
             stage_attempt_id: approval_attempt.id,
             kind: "release_handoff"
           }),
         {:ok, waiting} <-
           Execution.transition_run(run.id, "waiting", "walking:#{run.id}:approval",
             wait_reason: "approval"
           ),
         true <- waiting.result["outcome"] == "transitioned" do
      {:ok,
       skeleton
       |> Map.put(:environment, environment)
       |> Map.put(:run, Repo.get!(Run, run.id))
       |> Map.put(:task, Repo.get!(Task, skeleton.task.id))
       |> Map.put(:approval, approval)
       |> Map.put(:evidence, evidence)}
    else
      false -> {:error, :transition_rejected}
      error -> error
    end
  end

  @doc "Returns pending release approvals for the minimal LiveView."
  def pending_approvals do
    Repo.all(
      from(approval in Approval,
        join: run in Run,
        on: run.id == approval.run_id,
        join: task in Task,
        on: task.id == run.task_id,
        where:
          (approval.decision == "pending" and run.state == "waiting") or
            (approval.decision == "approved" and run.state in ["running", "waiting"]),
        order_by: [asc: approval.inserted_at],
        select: %{approval: approval, run: run, task: task}
      )
    )
    |> Enum.map(&Map.put(&1, :review, approval_review(&1)))
  end

  @doc "Records human approval, pushes through the host VCS service, and completes the run."
  def approve_and_release(approval_id, actor, options \\ [])
      when is_binary(approval_id) and is_binary(actor) and is_list(options) do
    with %Approval{} = approval <- Repo.get(Approval, approval_id),
         %Run{} = run <- Repo.get(Run, approval.run_id),
         %Environment{} = environment <- Repo.get_by(Environment, run_id: run.id),
         %StageAttempt{} = human_attempt <- Repo.get(StageAttempt, approval.stage_attempt_id),
         {:ok, _evidence} <- validated_evidence(environment),
         {:ok, approved} <- approve_or_resume(approval, run, human_attempt, actor),
         {:ok, release_attempt} <- release_attempt(run) do
      release(run, environment, approved, release_attempt, options)
    else
      nil -> {:error, :approval_not_found}
      error -> error
    end
  end

  defp approve_or_resume(%Approval{decision: "pending"} = approval, run, human_attempt, actor) do
    with {:ok, approved} <-
           Workflows.decide_approval(approval.id, "approved", actor, "Approved in local UI"),
         {:ok, _resumed} <-
           Execution.transition_stage_attempt(
             human_attempt.id,
             "running",
             "walking:#{human_attempt.id}:approved"
           ),
         {:ok, _completed} <-
           Execution.transition_stage_attempt(
             human_attempt.id,
             "succeeded",
             "walking:#{human_attempt.id}:succeeded"
           ),
         {:ok, running} <-
           Execution.transition_run(run.id, "running", "walking:#{run.id}:release-running"),
         true <- running.result["outcome"] == "transitioned" do
      {:ok, approved}
    else
      false -> {:error, :transition_rejected}
      error -> error
    end
  end

  defp approve_or_resume(
         %Approval{decision: "approved"} = approval,
         %Run{state: state} = run,
         %StageAttempt{state: "succeeded"},
         _actor
       )
       when state in ["running", "waiting"] do
    if state == "waiting" do
      attempt = latest_release_attempt(run)

      with %StageAttempt{} <- attempt,
           {:ok, command} <-
             Execution.transition_run(
               run.id,
               "running",
               "walking:#{run.id}:release-retry:#{attempt.id}"
             ),
           true <- command.result["outcome"] == "transitioned" do
        {:ok, approval}
      else
        nil -> {:error, :release_attempt_not_found}
        false -> {:error, :transition_rejected}
        error -> error
      end
    else
      {:ok, approval}
    end
  end

  defp approve_or_resume(%Approval{}, _run, _human_attempt, _actor),
    do: {:error, :release_not_retryable}

  defp release(run, environment, approved, release_attempt, options) do
    vcs_host = Keyword.get(options, :vcs_host, LocalBareRemote)
    key = "walking:#{run.id}:release-handoff"

    case handoff(vcs_host, environment, approved, key) do
      {:ok, handoff} ->
        finalize_release(run, environment, approved, release_attempt, handoff)

      {:error, reason} ->
        fail_stage_attempt(release_attempt, reason)
    end
  end

  defp handoff({module, options}, environment, approval, key)
       when is_atom(module) and is_list(options),
       do: module.handoff(environment, approval, key, options)

  defp handoff(module, environment, approval, key) when is_atom(module),
    do: module.handoff(environment, approval, key)

  defp finalize_release(run, environment, approved, release_attempt, handoff) do
    with {:ok, _stage_command} <-
           Execution.transition_stage_attempt(
             release_attempt.id,
             "succeeded",
             "walking:#{release_attempt.id}:succeeded"
           ),
         {:ok, done} <-
           Execution.transition_run(run.id, "done", "walking:#{run.id}:done"),
         true <- done.result["outcome"] == "transitioned",
         {:ok, release_artifact} <- write_release_artifact(environment, handoff.result) do
      {:ok,
       %{
         approval: approved,
         run: Repo.get!(Run, run.id),
         task: Repo.get!(Task, run.task_id),
         handoff: handoff,
         release_artifact: release_artifact
       }}
    else
      false -> {:error, :transition_rejected}
      error -> error
    end
  end

  defp release_attempt(run) do
    case latest_release_attempt(run) do
      %StageAttempt{state: "running"} = attempt ->
        {:ok, attempt}

      %StageAttempt{state: "waiting"} = attempt ->
        with {:ok, command} <-
               Execution.transition_stage_attempt(
                 attempt.id,
                 "running",
                 "walking:#{attempt.id}:release-retry"
               ),
             true <- command.result["outcome"] == "transitioned" do
          {:ok, Repo.get!(StageAttempt, attempt.id)}
        else
          false -> {:error, :transition_rejected}
          error -> error
        end

      nil ->
        stage_attempt(run, "release_handoff", "release", "system")

      %StageAttempt{} ->
        stage_attempt(run, "release_handoff", "release", "system")
    end
  end

  defp latest_release_attempt(run) do
    Repo.one(
      from(attempt in StageAttempt,
        where: attempt.run_id == ^run.id and attempt.stage_key == "release_handoff",
        order_by: [desc: attempt.attempt],
        limit: 1
      )
    )
  end

  defp run_stage(skeleton, stage_key, role_key, adapter, options) do
    with {:ok, attempt} <- stage_attempt(skeleton.run, stage_key, role_key, "agent") do
      case run_stage_attempt(skeleton, attempt, stage_key, adapter, options) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> fail_stage_attempt(attempt, reason)
      end
    end
  end

  defp run_stage_attempt(skeleton, attempt, stage_key, adapter, options) do
    started = System.monotonic_time(:millisecond)
    request = request(skeleton, attempt, stage_key, options)

    with {:ok, request} <- Knowledge.prepare_injection(request, options),
         {:ok, session} <- adapter.start(request, adapter_options(skeleton.environment, options)),
         :ok <- Knowledge.record_injection(request),
         {:ok, stored} <- store_session(attempt, session, options),
         {:ok, environment, session} <-
           maybe_sleep_gap(
             %{attempt: attempt, session: session, request: request},
             skeleton.environment,
             adapter,
             options
           ),
         {:ok, result} <- await_session(session),
         {:ok, _stored} <- Adapters.record_session_observation(stored, %{session | state: "done"}),
         elapsed = max(System.monotonic_time(:millisecond) - started, 0),
         {:ok, _timing} <-
           Execution.record_stage_time(
             attempt.id,
             elapsed,
             elapsed,
             "walking:#{attempt.id}:timing"
           ),
         {:ok, completed} <-
           Execution.transition_stage_attempt(
             attempt.id,
             "succeeded",
             "walking:#{attempt.id}:succeeded"
           ) do
      {:ok,
       %{
         attempt: Repo.get!(StageAttempt, attempt.id),
         session: session,
         request: request,
         result: result,
         command: completed,
         environment: environment
       }}
    end
  end

  defp fail_stage_attempt(attempt, reason) do
    case Execution.transition_stage_attempt(
           attempt.id,
           "failed",
           "walking:#{attempt.id}:failed"
         ) do
      {:ok, _command} ->
        {:error, reason}

      {:error, transition_reason} ->
        {:error, {:stage_failure_persist_failed, reason, transition_reason}}
    end
  end

  defp maybe_sleep_gap(stage, environment, adapter, options) do
    if Keyword.get(options, :simulate_sleep_gap, true) and
         stage.request.stage_key == "specification" do
      run = Repo.get!(Run, stage.attempt.run_id)

      with {:ok, checkpoint} <- adapter.pause(stage.session, []),
           {:ok, hibernated} <-
             Lifecycle.hibernate(run, environment, "walking:#{run.id}:hibernate",
               checkpoint: fn attempt ->
                 if attempt.id == stage.attempt.id,
                   do: {:ok, checkpoint},
                   else: {:error, :attempt_changed}
               end
             ),
           {:ok, resumed} <-
             Lifecycle.resume(run, hibernated.environment, "walking:#{run.id}:resume",
               resume_stage: fn attempt, _allocation ->
                 if attempt.id == stage.attempt.id,
                   do: adapter.resume(stage.session, checkpoint, request: stage.request),
                   else: {:error, :attempt_changed}
               end
             ),
           {:ok, released} <- PortAllocator.release(resumed.allocation, "hibernated"),
           {:ok, running} <- Execution.update_environment_preview(released, %{state: "running"}) do
        {:ok, running, resumed.resume_result}
      end
    else
      {:ok, environment, stage.session}
    end
  end

  defp candidate(_stage, environment, FakeAdapter, task, options) do
    action = Keyword.get(options, :fake_implementation, &fake_implementation(&1, task))
    action.(environment)
  end

  defp candidate(_stage, environment, _adapter, task, _options) do
    with {:ok, inspection} <- GitService.inspect(environment) do
      candidate(inspection, environment, task)
    end
  end

  defp candidate(%{clean?: true}, environment, _task),
    do: GitService.record_candidate(environment)

  defp candidate(_inspection, environment, task) do
    with {:ok, paths} <- ProtectedPaths.changed_paths(environment) do
      GitService.commit_candidate(environment, paths, "feat: #{task.title}")
    end
  end

  defp fake_implementation(environment, task) do
    path = Path.join(environment.worktree_path, "WALKING_SKELETON.md")

    :ok =
      File.write(path, "# #{task.title}\n\nImplemented by the deterministic fake adapter lane.\n")

    GitService.commit_candidate(
      environment,
      ["WALKING_SKELETON.md"],
      "feat: complete walking skeleton task"
    )
  end

  defp human_approval_attempt(run) do
    with {:ok, attempt} <- stage_attempt(run, "human_approval", "approver", "human"),
         {:ok, _waiting} <-
           Execution.transition_stage_attempt(
             attempt.id,
             "waiting",
             "walking:#{attempt.id}:waiting"
           ) do
      {:ok, Repo.get!(StageAttempt, attempt.id)}
    end
  end

  defp stage_attempt(run, stage_key, role_key, role_kind) do
    attempt_number =
      Repo.one(
        from(attempt in StageAttempt,
          where: attempt.run_id == ^run.id and attempt.stage_key == ^stage_key,
          select: max(attempt.attempt)
        )
      )
      |> Kernel.||(0)
      |> Kernel.+(1)

    with {:ok, attempt} <-
           Execution.create_stage_attempt(%{
             run_id: run.id,
             stage_key: stage_key,
             attempt: attempt_number,
             role_key: role_key,
             role_kind: role_kind
           }),
         {:ok, command} <-
           Execution.transition_stage_attempt(
             attempt.id,
             "running",
             "walking:#{attempt.id}:running"
           ),
         true <- command.result["outcome"] == "transitioned" do
      {:ok, Repo.get!(StageAttempt, attempt.id)}
    else
      false -> {:error, :transition_rejected}
      error -> error
    end
  end

  defp request(skeleton, attempt, stage_key, options) do
    %Types.StageRequest{
      project_id: skeleton.project.id,
      board_id: skeleton.board.id,
      task_id: skeleton.task.id,
      run_id: skeleton.run.id,
      stage_key: stage_key,
      attempt_id: attempt.id,
      objective: objective(stage_key, skeleton.task),
      worktree_path: skeleton.environment.worktree_path,
      run_dir: skeleton.environment.run_dir,
      requested_model: Keyword.get(options, :requested_model),
      grant: %{
        "tools" => ["read", "write", "shell"],
        "deny_tools" => ["network"],
        "approval_mode" => if(stage_key in ["specification", "qa"], do: "plan", else: "default"),
        "paths" => [skeleton.environment.worktree_path],
        "network" => "deny",
        "resource_limits" => %{"wall_ms" => 300_000}
      },
      plugins: [],
      required_output_schema: %{
        "type" => "object",
        "properties" => %{"summary" => %{"type" => "string"}},
        "required" => ["summary"],
        "additionalProperties" => false
      },
      correlation_id: Cuckoding.Identifier.generate(),
      idempotency_key: "walking:#{attempt.id}:adapter"
    }
  end

  defp adapter_options(environment, options) do
    options
    |> Keyword.get(:adapter_options, [])
    |> Keyword.put_new(:runner, LocalProcessRunner)
    |> Keyword.put_new(:environment, environment)
  end

  defp store_session(attempt, session, options) do
    with {:ok, stored} <-
           Execution.create_agent_session(%{
             stage_attempt_id: attempt.id,
             adapter_key: session.adapter,
             runtime_version: Keyword.get(options, :runtime_version),
             requested_model: session.requested_model,
             effective_grant_json: Map.from_struct(session.effective_grant)
           }),
         do: Adapters.record_session_observation(stored, session)
  end

  defp await_session(%Types.Session{process: %{runner: runner, handle: handle}}) do
    case runner.result(handle) do
      {:ok, %{exit_status: 0} = result} -> {:ok, result}
      {:ok, %{exit_status: status}} -> {:error, {:adapter_exit, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp await_session(%Types.Session{}), do: {:ok, %{adapter: "fake", exit_status: 0}}

  defp write_artifact(environment, type, name, contents) do
    path = Path.join([environment.run_dir, "artifacts", name])

    with :ok <- owner_file(path, contents),
         sha = sha256(path),
         {:ok, {_event, _projection}} <-
           EventStore.append(environment.run_id, %{
             event_type: "artifact.created",
             public_summary: "Walking-skeleton evidence artifact created",
             payload: %{"type" => type, "path" => name, "sha256" => sha}
           }) do
      {:ok, %{"type" => type, "path" => name, "sha256" => sha}}
    end
  end

  defp write_knowledge_candidate(environment, task) do
    relative = Path.join(["knowledge", "candidates", "walking-skeleton.md"])
    path = Path.join(environment.run_dir, relative)

    contents =
      "# Candidate: #{task.title}\n\n- Scope: project only\n- Status: unreviewed\n- Learning: the default loop reached human approval.\n"

    with :ok <- owner_file(path, contents),
         sha = sha256(path),
         {:ok, {_event, _projection}} <-
           EventStore.append(environment.run_id, %{
             event_type: "knowledge.candidate_created",
             public_summary: "Unreviewed project knowledge candidate created",
             payload: %{"path" => relative, "sha256" => sha, "scope" => "project"}
           }) do
      {:ok, %{"path" => relative, "sha256" => sha}}
    end
  end

  defp write_evidence(environment, run, adapter, stages, artifacts, knowledge) do
    bundle =
      %{
        "schema_version" => 1,
        "run_id" => run.id,
        "adapter" => adapter |> Module.split() |> List.last(),
        "branch" => run.branch,
        "base_sha" => environment.base_sha,
        "head_sha" => Repo.get!(Environment, environment.id).head_sha,
        "stages" =>
          Enum.map(stages, fn stage ->
            %{
              "attempt_id" => stage.attempt.id,
              "stage_key" => stage.attempt.stage_key,
              "active_ms" => stage.attempt.active_ms,
              "wall_ms" => stage.attempt.wall_ms
            }
          end),
        "artifacts" => artifacts,
        "tests" => [
          %{
            "command" => "qa stage",
            "status" => "passed",
            "passed" => 1,
            "failed" => 0
          }
        ],
        "findings" => [],
        "knowledge_citations" => [knowledge]
      }

    case GateEvaluator.verify(bundle, environment.run_dir) do
      {:ok, validated} ->
        contents = Jason.encode!(validated) <> "\n"
        write_artifact(environment, "evidence_bundle", "evidence.json", contents)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_release_artifact(environment, result) do
    write_artifact(
      environment,
      "release_receipt",
      "release.json",
      Jason.encode!(result) <> "\n"
    )
  end

  defp approval_review(%{run: run}) do
    case Repo.get_by(Environment, run_id: run.id) do
      %Environment{} = environment ->
        with {:ok, evidence} <- validated_evidence(environment),
             {:ok, changed_paths} <- ProtectedPaths.changed_paths(environment) do
          %{"outcome" => "passed", "evidence" => evidence, "changed_paths" => changed_paths}
        else
          {:error, reason} -> %{"outcome" => "failed", "error" => inspect(reason)}
        end

      nil ->
        %{"outcome" => "failed", "error" => "environment not found"}
    end
  end

  defp validated_evidence(environment) do
    path = Path.join([environment.run_dir, "artifacts", "evidence.json"])

    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} when size <= 1_048_576 ->
        with {:ok, contents} <- File.read(path),
             {:ok, bundle} <- Jason.decode(contents),
             do: GateEvaluator.verify(bundle, environment.run_dir)

      _other ->
        {:error, :invalid_evidence_file}
    end
  end

  defp owner_file(path, contents) do
    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, contents),
         do: File.chmod(path, 0o600)
  end

  defp sha256(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  defp project_attrs(attrs) do
    %{
      name: Map.fetch!(attrs, :name),
      repo_path: Map.fetch!(attrs, :repo_path),
      default_branch: Map.get(attrs, :default_branch, "main"),
      workspace_root: Map.fetch!(attrs, :workspace_root),
      port_range_start: Map.get(attrs, :port_range_start, 43_000),
      port_range_end: Map.get(attrs, :port_range_end, 43_010)
    }
  end

  defp policy_attrs(project, attrs) do
    config =
      Map.merge(
        %{"version" => 1, "runner" => "local_process", "plugins" => []},
        Map.get(attrs, :policy_config, %{})
      )

    %{
      project_id: project.id,
      revision: 1,
      source_hash: :crypto.hash(:sha256, Jason.encode!(config)) |> Base.encode16(case: :lower),
      config_json: config,
      trusted_at: Cuckoding.Clock.wall_now()
    }
  end

  defp workflow_attrs(project) do
    %{
      project_id: project.id,
      name: "default",
      version: 1,
      definition_json: Definition.default(),
      published_at: Cuckoding.Clock.wall_now()
    }
  end

  defp board_attrs(project, workflow, attrs) do
    %{
      project_id: project.id,
      workflow_version_id: workflow.id,
      name: Map.get(attrs, :board_name, "MVP"),
      concurrency_limit: 1
    }
  end

  defp task_attrs(board, attrs) do
    %{
      board_id: board.id,
      title: Map.fetch!(attrs, :task_title),
      description: Map.get(attrs, :task_description),
      position: 0
    }
  end

  defp run_attrs(task, policy, base_sha) do
    %{
      task_id: task.id,
      sequence: 1,
      policy_snapshot_id: policy.id,
      plugin_snapshot_json: %{},
      branch: "feature/walking-#{String.slice(task.id, 0, 8)}",
      base_sha: base_sha
    }
  end

  defp assign_roles(board, adapter_key) when is_binary(adapter_key) do
    [
      {"spec_writer", "agent", adapter_key},
      {"implementer", "agent", adapter_key},
      {"reviewer", "agent", adapter_key},
      {"approver", "human", nil},
      {"release", "system", nil}
    ]
    |> Enum.reduce_while(:ok, fn {key, kind, adapter}, :ok ->
      case Workflows.assign_role(%{
             board_id: board.id,
             role_key: key,
             role_kind: kind,
             adapter_key: adapter,
             settings_json: %{}
           }) do
        {:ok, _role} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp objective("specification", task) do
    "Inspect only; do not change files or commit. Describe a testable specification for: #{task.title}"
  end

  defp objective("development", task) do
    "Implement and test: #{task.title}. Leave the changes uncommitted for the host VCS service."
  end

  defp objective("qa", task) do
    "Inspect and test only; do not change files or commit. Review the candidate for: #{task.title}"
  end

  defp specification(task) do
    "# Specification\n\n## Objective\n\n#{task.title}\n\n## Acceptance\n\n- The candidate branch contains the requested change.\n- QA records a passing result.\n"
  end

  defp qa_report(environment) do
    "# QA\n\n- Candidate: #{environment.head_sha}\n- Result: pass in deterministic fake-adapter CI lane.\n"
  end
end
