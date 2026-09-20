defmodule Cuckoding.WalkingSkeletonTest do
  use CuckodingWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.Execution.Command
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.LocalBareRemote
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.FakeSecretStore
  alias Cuckoding.Repo
  alias Cuckoding.Security.SecretAccessAudit
  alias Cuckoding.Security.SecretStore
  alias Cuckoding.WalkingSkeleton
  alias Cuckoding.Workflows

  @git "/usr/bin/git"

  defmodule FailingAdapter do
    def start(_request, _options), do: {:error, :provider_failed}
  end

  defmodule CapturingAdapter do
    def start(request, options) do
      send(Keyword.fetch!(options, :caller), {:stage_request, request})
      {:error, :captured}
    end
  end

  defmodule PatchAdapter do
    alias Cuckoding.Adapters.FakeAdapter

    def start(%{stage_key: "development", worktree_path: worktree} = request, options) do
      File.write!(Path.join(worktree, "PATCH.txt"), "created by adapter\n")
      start_session(request, options)
    end

    def start(request, options), do: start_session(request, options)

    defp start_session(request, options) do
      with {:ok, session} <- FakeAdapter.start(request, options),
           do: {:ok, %{session | adapter: "patch"}}
    end
  end

  defmodule RoleAdapter do
    alias Cuckoding.Adapters.FakeAdapter

    def start(request, options) do
      tag = Keyword.fetch!(options, :tag)

      send(
        Keyword.fetch!(options, :caller),
        {:role_stage, tag, request.stage_key, request.objective}
      )

      send(
        Keyword.fetch!(options, :caller),
        {:role_schema, tag, request.stage_key, request.required_output_schema}
      )

      with {:ok, session} <- FakeAdapter.start(request, options),
           do: {:ok, %{session | adapter: Atom.to_string(tag)}}
    end
  end

  setup do
    root =
      Path.join(System.tmp_dir!(), "cuckoding-walking-#{System.unique_integer([:positive])}")

    bare = Path.join(root, "remote.git")
    seed = Path.join(root, "seed")
    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspaces")
    File.mkdir_p!(root)
    git!(root, ["init", "--bare", bare])
    git!(root, ["init", "-b", "main", seed])
    configure_identity!(seed)
    File.write!(Path.join(seed, "README.md"), "# walking skeleton fixture\n")
    git!(seed, ["add", "README.md"])
    git!(seed, ["commit", "-m", "initial"])
    git!(seed, ["remote", "add", "origin", bare])
    git!(seed, ["push", "-u", "origin", "main"])
    git!(bare, ["symbolic-ref", "HEAD", "refs/heads/main"])
    git!(root, ["clone", bare, repo])
    configure_identity!(repo)
    port = free_port()

    on_exit(fn -> File.rm_rf!(root) end)

    {:ok,
     attrs: %{
       name: "Walking #{System.unique_integer([:positive])}",
       repo_path: repo,
       workspace_root: workspace,
       task_title: "Ship the walking skeleton",
       port_range_start: port,
       port_range_end: port
     },
     bare: bare}
  end

  @tag recovery_drill: true
  test "fake CI lane resumes one attempt and pushes only after approval", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    assert {:ok, pending} = WalkingSkeleton.run(created)

    attempts =
      Repo.all(
        from(attempt in StageAttempt,
          where: attempt.run_id == ^created.run.id,
          order_by: attempt.inserted_at
        )
      )

    assert Enum.map(attempts, &{&1.stage_key, &1.state}) == [
             {"specification", "succeeded"},
             {"development", "succeeded"},
             {"qa", "succeeded"},
             {"human_approval", "waiting"}
           ]

    assert [specification] = Enum.filter(attempts, &(&1.stage_key == "specification"))
    assert specification.checkpoint_json["summary"] == "Fake checkpoint"
    assert Repo.get!(Cuckoding.Execution.Run, created.run.id).state == "waiting"
    assert Repo.get!(Cuckoding.Workflows.Task, created.task.id).state == "waiting"

    assert {:error, :approval_required} =
             LocalBareRemote.handoff(
               pending.environment,
               pending.approval,
               "walking:test:unapproved"
             )

    evidence = Path.join([pending.environment.run_dir, "artifacts", "evidence.json"])

    knowledge =
      Path.join([pending.environment.run_dir, "knowledge", "candidates", "walking-skeleton.md"])

    assert File.exists?(evidence)
    assert File.exists?(knowledge)
    assert Bitwise.band(File.stat!(evidence).mode, 0o777) == 0o600
    assert Bitwise.band(File.stat!(knowledge).mode, 0o777) == 0o600

    bundle = evidence |> File.read!() |> Jason.decode!()
    assert bundle["schema_version"] == 1
    assert bundle["base_sha"] == pending.environment.base_sha
    assert bundle["head_sha"] == pending.environment.head_sha
    assert Enum.map(bundle["artifacts"], & &1["type"]) == ["specification", "qa_report"]
    assert [%{"status" => "passed", "failed" => 0}] = bundle["tests"]

    assert [%{"path" => "knowledge/candidates/walking-skeleton.md"}] =
             bundle["knowledge_citations"]

    assert {:ok, released} = WalkingSkeleton.approve_and_release(pending.approval.id, "tester")
    assert released.run.state == "done"
    assert released.task.state == "done"

    assert {:ok, replayed} =
             LocalBareRemote.handoff(
               pending.environment,
               released.approval,
               "walking:#{released.run.id}:release-handoff"
             )

    assert replayed.id == released.handoff.id

    remote_sha = git!(fixture.bare, ["rev-parse", "refs/heads/#{released.run.branch}"])
    assert remote_sha == pending.environment.head_sha

    event_types =
      Repo.all(
        from(event in RunEvent,
          where: event.run_id == ^created.run.id,
          order_by: event.sequence,
          select: event.event_type
        )
      )

    assert "git.candidate_recorded" in event_types
    assert "approval.requested" in event_types
    assert "approval.decided" in event_types
    assert "release.handoff_completed" in event_types
    assert Enum.count(event_types, &(&1 == "release.handoff_completed")) == 1
  end

  test "guided run stays queued until the user starts the durable workflow", fixture do
    attrs = Map.merge(fixture.attrs, %{adapter_key: "fake", start_run: false})

    assert {:ok, created} = WalkingSkeleton.create(attrs)
    assert created.run.state == "queued"
    assert {:ok, loaded} = WalkingSkeleton.load(created.run.id)
    assert loaded.environment.worktree_path == created.environment.worktree_path

    assert {:ok, pending} = Cuckoding.GuidedRun.start(created.run.id, async: false)
    assert pending.run.state == "waiting"
    assert Repo.get!(Cuckoding.Execution.Run, created.run.id).state == "waiting"
  end

  test "workflow resolves the configured adapter and instructions for each agent role", fixture do
    attrs = Map.merge(fixture.attrs, %{adapter_key: "fake", start_run: true})
    assert {:ok, created} = WalkingSkeleton.create(attrs)

    role_adapters = %{
      "spec_writer" => %{
        adapter: RoleAdapter,
        options: [caller: self(), tag: :spec_agent],
        version: "spec-1",
        requested_model: "spec-model",
        settings: %{"instructions" => "Write a bounded specification."}
      },
      "implementer" => %{
        adapter: Cuckoding.Adapters.FakeAdapter,
        options: [],
        version: "implementation-1",
        settings: %{"instructions" => "Implement only the accepted scope."}
      },
      "reviewer" => %{
        adapter: RoleAdapter,
        options: [caller: self(), tag: :review_agent],
        version: "review-1",
        requested_model: "gpt-6-astra",
        settings: %{"instructions" => "Review independently."}
      }
    }

    assert {:ok, pending} =
             WalkingSkeleton.run(created,
               role_adapters: role_adapters,
               simulate_sleep_gap: false
             )

    assert pending.run.state == "waiting"

    assert_receive {:role_stage, :spec_agent, "specification", specification}
    assert specification =~ "Write a bounded specification."

    assert_receive {:role_stage, :review_agent, "qa", review}
    assert review =~ "Review independently."

    assert_receive {:role_schema, :review_agent, "qa", schema}
    assert schema["required"] == ["summary", "findings"]
    assert schema["additionalProperties"] == false
    assert schema["properties"]["findings"]["maxItems"] == 20

    sessions =
      Repo.all(
        from(session in Cuckoding.Execution.AgentSession,
          join: attempt in StageAttempt,
          on: attempt.id == session.stage_attempt_id,
          where: attempt.run_id == ^created.run.id,
          order_by: attempt.inserted_at,
          select:
            {attempt.role_key, session.adapter_key, session.runtime_version,
             session.requested_model}
        )
      )

    assert sessions == [
             {"spec_writer", "spec_agent", "spec-1", "spec-model"},
             {"implementer", "fake", "implementation-1", nil},
             {"reviewer", "review_agent", "review-1", "gpt-6-astra"}
           ]
  end

  test "review findings rerun the earliest affected stage within the fixed budget", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    changes = :atomics.new(1, [])

    implementation = fn environment ->
      revision = :atomics.add_get(changes, 1, 1)

      File.write!(
        Path.join(environment.worktree_path, "REVIEW_LOOP.txt"),
        "revision #{revision}\n"
      )

      GitService.commit_candidate(
        environment,
        ["REVIEW_LOOP.txt"],
        "fix: address review attempt #{revision}"
      )
    end

    review = fn
      1 ->
        review_output("Clarify intent", "fix_intent", "requirements")

      2 ->
        review_output("Fix implementation", "fix_code", "correctness")

      3 ->
        %{"summary" => "Review passed", "findings" => []}
    end

    assert {:ok, pending} =
             WalkingSkeleton.run(created,
               simulate_sleep_gap: false,
               fake_implementation: implementation,
               fake_review_output: review
             )

    attempts =
      Repo.all(
        from(attempt in StageAttempt,
          where: attempt.run_id == ^created.run.id,
          order_by: [asc: attempt.inserted_at, asc: attempt.id],
          select: {attempt.stage_key, attempt.attempt, attempt.state}
        )
      )

    assert Enum.filter(attempts, &(elem(&1, 0) == "specification")) == [
             {"specification", 1, "succeeded"},
             {"specification", 2, "succeeded"}
           ]

    assert Enum.filter(attempts, &(elem(&1, 0) == "development")) == [
             {"development", 1, "succeeded"},
             {"development", 2, "succeeded"},
             {"development", 3, "succeeded"}
           ]

    assert Enum.filter(attempts, &(elem(&1, 0) == "qa")) == [
             {"qa", 1, "succeeded"},
             {"qa", 2, "succeeded"},
             {"qa", 3, "succeeded"}
           ]

    findings =
      Repo.all(
        from(finding in Cuckoding.Workflows.Finding,
          where: finding.run_id == ^created.run.id,
          order_by: finding.inserted_at
        )
      )

    assert Enum.map(findings, & &1.evidence_json["transition"]) == ["fix_intent", "fix_code"]
    assert pending.run.state == "waiting"
    assert Repo.aggregate(Cuckoding.Workflows.Approval, :count) == 1

    event_types =
      Repo.all(
        from(event in RunEvent,
          where: event.run_id == ^created.run.id,
          select: event.event_type
        )
      )

    assert Enum.count(event_types, &(&1 == "finding.created")) == 2
  end

  test "review attempt budget stops an endless correction loop", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    changes = :atomics.new(1, [])

    implementation = fn environment ->
      revision = :atomics.add_get(changes, 1, 1)
      File.write!(Path.join(environment.worktree_path, "REVIEW_BUDGET.txt"), "#{revision}\n")

      GitService.commit_candidate(
        environment,
        ["REVIEW_BUDGET.txt"],
        "fix: review budget attempt #{revision}"
      )
    end

    assert {:error, :review_attempt_budget_exceeded} =
             WalkingSkeleton.run(created,
               simulate_sleep_gap: false,
               fake_implementation: implementation,
               fake_review_output: fn _attempt ->
                 review_output("Still failing", "fix_code", "correctness")
               end
             )

    assert Repo.aggregate(
             from(attempt in StageAttempt,
               where: attempt.run_id == ^created.run.id and attempt.stage_key == "qa"
             ),
             :count
           ) == 3

    refute Repo.exists?(
             from(approval in Cuckoding.Workflows.Approval,
               where: approval.run_id == ^created.run.id
             )
           )
  end

  test "review rejects untrusted output outside the closed route schema", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)

    invalid =
      review_output("Unsupported route", "fix_code", "correctness")
      |> put_in(["findings", Access.at(0), "transition"], "release")

    assert {:error, :invalid_review_output} =
             WalkingSkeleton.run(created,
               simulate_sleep_gap: false,
               fake_review_output: invalid
             )

    assert %StageAttempt{state: "failed"} =
             Repo.get_by!(StageAttempt, run_id: created.run.id, stage_key: "qa", attempt: 1)

    refute Repo.exists?(
             from(approval in Cuckoding.Workflows.Approval,
               where: approval.run_id == ^created.run.id
             )
           )
  end

  test "guided onboarding validates the repository before creating a queued run", fixture do
    previous = Application.get_env(:cuckoding, :workspace_root)
    Application.put_env(:cuckoding, :workspace_root, fixture.attrs.workspace_root)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :workspace_root, previous),
        else: Application.delete_env(:cuckoding, :workspace_root)
    end)

    assert {:error, :missing_directory} =
             Cuckoding.GuidedRun.create(%{
               "name" => "Missing",
               "repo_path" => Path.join(fixture.attrs.repo_path, "missing"),
               "default_branch" => "main",
               "runtime" => "codex",
               "executable_path" => "/usr/bin/true",
               "task_title" => "Never created"
             })

    assert {:error, :invalid_runtime_executable} =
             Cuckoding.GuidedRun.create(%{
               "name" => "Relative runtime",
               "repo_path" => fixture.attrs.repo_path,
               "default_branch" => "main",
               "runtime" => "codex",
               "executable_path" => "codex",
               "task_title" => "Never created"
             })

    refute Repo.exists?(Cuckoding.Projects.Project)

    assert {:ok, created} =
             Cuckoding.GuidedRun.create(%{
               "name" => "Guided project",
               "repo_path" => fixture.attrs.repo_path,
               "default_branch" => "main",
               "runtime" => "codex",
               "executable_path" => "/usr/bin/true",
               "task_title" => "Guided task",
               "task_description" => "A bounded first run"
             })

    assert created.run.state == "queued"
    assert File.dir?(created.environment.worktree_path)

    assert %Cuckoding.Workflows.RoleAssignment{
             adapter_key: "codex",
             settings_json: %{"executable_path" => "/usr/bin/true"}
           } =
             Repo.get_by!(Cuckoding.Workflows.RoleAssignment,
               board_id: created.board.id,
               role_key: "implementer"
             )

    assert {:error, %Cuckoding.Adapters.Types.Error{code: :invalid_version}} =
             Cuckoding.GuidedRun.start(created.run.id)

    assert Repo.get!(Cuckoding.Execution.Run, created.run.id).state == "queued"
  end

  test "queued run starts from the accessible run control", %{conn: conn} = fixture do
    attrs = Map.merge(fixture.attrs, %{adapter_key: "fake", start_run: false})
    assert {:ok, created} = WalkingSkeleton.create(attrs)
    assert {:ok, view, _html} = live(conn, ~p"/runs/#{created.run.id}")

    assert has_element?(view, "#runtime-setup", "Deterministic test adapter")
    assert has_element?(view, "button", "Check authentication and start workflow")

    view |> element("button", "Check authentication and start workflow") |> render_click()
    assert has_element?(view, "[role=status]", "Workflow started")

    eventually(fn ->
      Repo.get!(Cuckoding.Execution.Run, created.run.id).state == "waiting"
    end)

    send(view.pid, :refresh_run_activity)
    _html = render(view)
    refute has_element?(view, "#runtime-setup")
  end

  test "LiveView requires an explicit confirmation before host-side release",
       %{
         conn: conn
       } = fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    assert {:ok, pending} = WalkingSkeleton.run(created, simulate_sleep_gap: false)
    assert {:ok, view, _html} = live(conn, ~p"/")

    selector = "#approval-#{pending.approval.id}"
    assert has_element?(view, selector, "Ship the walking skeleton")
    assert has_element?(view, selector, "Candidate diff")
    assert has_element?(view, selector, "WALKING_SKELETON.md")
    assert has_element?(view, selector, "qa stage")
    assert has_element?(view, selector, "specification.md")
    assert has_element?(view, selector, "knowledge/candidates/walking-skeleton.md")
    refute has_element?(view, "#{selector} button", "Approve and release")

    view |> element("#{selector} button", "Review release") |> render_click()
    assert has_element?(view, "#{selector} [role=alert]", "Confirm the host-side push")
    assert has_element?(view, "#{selector} button", "Approve and release")
    assert has_element?(view, "#{selector} button", "Cancel")

    view |> element("#{selector} button", "Approve and release") |> render_click()
    assert render(view) =~ "Approved release handoff completed."
    refute has_element?(view, selector)
  end

  test "LiveView explicitly completes a reviewed run without release", %{conn: conn} = fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    assert {:ok, pending} = WalkingSkeleton.run(created, simulate_sleep_gap: false)

    assert {:ok, run_view, _html} = live(conn, ~p"/runs/#{created.run.id}")
    assert has_element?(run_view, "#completion-choice-heading", "Review passed")
    assert has_element?(run_view, "a", "Open completion choices")

    assert {:ok, view, _html} = live(conn, ~p"/")

    selector = "#approval-#{pending.approval.id}"
    assert has_element?(view, "#{selector} button", "Complete locally")

    view |> element("#{selector} button", "Complete locally") |> render_click()
    assert has_element?(view, "#{selector} [role=alert]", "without pushing")
    assert has_element?(view, "#{selector} button", "Confirm local completion")

    view |> element("#{selector} button", "Confirm local completion") |> render_click()
    assert render(view) =~ "Run completed locally. No branch was pushed."
    refute has_element?(view, selector)

    assert Repo.get!(Cuckoding.Execution.Run, created.run.id).state == "done"
    assert Repo.get!(Cuckoding.Workflows.Task, created.task.id).state == "done"
    assert Repo.get!(Cuckoding.Workflows.Approval, pending.approval.id).decision == "rejected"
  end

  test "local completion keeps evidence and never invokes release handoff", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    assert {:ok, pending} = WalkingSkeleton.run(created, simulate_sleep_gap: false)

    assert {:ok, completed} =
             WalkingSkeleton.complete_locally(pending.approval.id, "tester")

    assert completed.run.state == "done"
    assert completed.task.state == "done"
    assert completed.approval.decision == "rejected"
    assert completed.attempt.state == "cancelled"
    assert File.dir?(pending.environment.worktree_path)
    assert File.exists?(Path.join([pending.environment.run_dir, "artifacts", "evidence.json"]))

    {_output, status} =
      System.cmd(@git, ["show-ref", "--verify", "refs/heads/#{created.run.branch}"],
        cd: fixture.bare,
        stderr_to_stdout: true
      )

    assert status != 0

    event_types =
      Repo.all(
        from(event in RunEvent,
          where: event.run_id == ^created.run.id,
          select: event.event_type
        )
      )

    assert "run.completed_locally" in event_types
    refute "release.handoff_completed" in event_types

    refute Repo.exists?(
             from(attempt in StageAttempt,
               where:
                 attempt.run_id == ^created.run.id and
                   attempt.stage_key == "release_handoff"
             )
           )
  end

  test "approved handoff refuses a protected branch", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    assert {:ok, pending} = WalkingSkeleton.run(created, simulate_sleep_gap: false)

    assert {:ok, approved} =
             Workflows.decide_approval(
               pending.approval.id,
               "approved",
               "tester",
               "Protected-branch test"
             )

    created.run |> Ecto.Changeset.change(branch: "main") |> Repo.update!()

    assert {:error, :protected_branch} =
             LocalBareRemote.handoff(
               pending.environment,
               approved,
               "walking:test:protected"
             )
  end

  test "approval fails closed when a referenced artifact changes", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    assert {:ok, pending} = WalkingSkeleton.run(created, simulate_sleep_gap: false)

    File.write!(Path.join([pending.environment.run_dir, "artifacts", "qa.md"]), "tampered\n")

    assert {:error, %{"outcome" => "failed", "findings" => [finding]}} =
             WalkingSkeleton.approve_and_release(pending.approval.id, "tester")

    assert finding["severity"] == "blocker"
    assert finding["category"] == "artifact_schema"
    assert finding["summary"] =~ "artifact integrity check failed"
    assert Repo.get!(Cuckoding.Workflows.Approval, pending.approval.id).decision == "pending"
  end

  test "approval keeps the credential host-side and creates a draft GitHub PR", fixture do
    use_fake_secret_store!()
    token = "github-fixture-token"
    assert {:ok, credential_ref} = SecretStore.put(token)

    attrs =
      Map.put(fixture.attrs, :policy_config, %{
        "vcs" => %{
          "provider" => "github",
          "repository" => "example/cuckoding",
          "credential_ref" => credential_ref
        }
      })

    assert {:ok, created} = WalkingSkeleton.create(attrs)
    assert {:ok, pending} = WalkingSkeleton.run(created, simulate_sleep_gap: false)
    owner = self()

    push = fn environment, run, repository, received_token ->
      send(owner, {:github_push, environment.id, run.branch, repository, received_token})
      {:ok, %{"outcome" => "pushed"}}
    end

    create_pr = fn repository, payload, received_token ->
      send(owner, {:github_pr, repository, payload, received_token})
      {:ok, %{"url" => "https://github.example/pull/1"}}
    end

    assert {:ok, released} =
             WalkingSkeleton.approve_and_release(pending.approval.id, "tester",
               vcs_host: {Cuckoding.Execution.GitHubVcsHost, push: push, create_pr: create_pr}
             )

    assert_receive {:github_push, _, branch, "example/cuckoding", ^token}
    assert branch == released.run.branch

    assert_receive {:github_pr, "example/cuckoding", payload, ^token}
    assert payload["draft"] == true
    assert payload["head"] == released.run.branch
    assert payload["base"] == "main"
    assert payload["body"] =~ "## Evidence"
    assert payload["body"] =~ "qa stage"
    assert payload["body"] =~ "## Knowledge citations"
    assert payload["body"] =~ "knowledge/candidates/walking-skeleton.md"
    assert released.handoff.result["draft_pr_url"] == "https://github.example/pull/1"

    assert %SecretAccessAudit{purpose: "github.release_handoff", run_id: run_id} =
             Repo.one!(SecretAccessAudit)

    assert run_id == released.run.id
    refute inspect(Repo.all(Command)) =~ token
    refute inspect(Repo.all(RunEvent)) =~ token
  end

  test "an approved release can retry after a failed host handoff", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    assert {:ok, pending} = WalkingSkeleton.run(created, simulate_sleep_gap: false)

    dirty_path = Path.join(pending.environment.worktree_path, "UNTRACKED.txt")
    File.write!(dirty_path, "blocks release\n")

    assert {:error, :dirty_worktree} =
             WalkingSkeleton.approve_and_release(pending.approval.id, "tester")

    assert Repo.get!(Cuckoding.Workflows.Approval, pending.approval.id).decision == "approved"
    assert Repo.get!(Cuckoding.Execution.Run, created.run.id).state == "running"

    assert [%{attempt: 1, state: "failed"}] =
             Repo.all(
               from(attempt in StageAttempt,
                 where:
                   attempt.run_id == ^created.run.id and
                     attempt.stage_key == "release_handoff",
                 select: %{attempt: attempt.attempt, state: attempt.state}
               )
             )

    assert [%{approval: %{id: approval_id}}] = WalkingSkeleton.pending_approvals()
    assert approval_id == pending.approval.id

    File.rm!(dirty_path)
    assert {:ok, released} = WalkingSkeleton.approve_and_release(pending.approval.id, "tester")
    assert released.run.state == "done"

    assert [%{attempt: 1, state: "failed"}, %{attempt: 2, state: "succeeded"}] =
             Repo.all(
               from(attempt in StageAttempt,
                 where:
                   attempt.run_id == ^created.run.id and
                     attempt.stage_key == "release_handoff",
                 order_by: attempt.attempt,
                 select: %{attempt: attempt.attempt, state: attempt.state}
               )
             )

    approval_events =
      Repo.aggregate(
        from(event in RunEvent,
          where: event.run_id == ^created.run.id and event.event_type == "approval.decided"
        ),
        :count
      )

    assert approval_events == 1
  end

  test "failed provider attempts remain durable and a retry gets a new ordinal", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)

    assert {:error, :provider_failed} =
             WalkingSkeleton.run(created,
               adapter: FailingAdapter,
               simulate_sleep_gap: false
             )

    assert [%{attempt: 1, state: "failed"}] =
             Repo.all(
               from(attempt in StageAttempt,
                 where:
                   attempt.run_id == ^created.run.id and
                     attempt.stage_key == "specification",
                 select: %{attempt: attempt.attempt, state: attempt.state}
               )
             )

    assert {:ok, _pending} = WalkingSkeleton.run(created, simulate_sleep_gap: false)

    assert [%{attempt: 1, state: "failed"}, %{attempt: 2, state: "succeeded"}] =
             Repo.all(
               from(attempt in StageAttempt,
                 where:
                   attempt.run_id == ^created.run.id and
                     attempt.stage_key == "specification",
                 order_by: attempt.attempt,
                 select: %{attempt: attempt.attempt, state: attempt.state}
               )
             )
  end

  test "real-provider response schema is a closed object", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)

    assert {:error, :captured} =
             WalkingSkeleton.run(created,
               adapter: CapturingAdapter,
               adapter_options: [caller: self()]
             )

    assert_receive {:stage_request, request}
    assert request.required_output_schema["additionalProperties"] == false
    assert request.grant["approval_mode"] == "plan"
  end

  test "host commits a real adapter patch without granting Git metadata", fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)

    assert {:ok, pending} =
             WalkingSkeleton.run(created,
               adapter: PatchAdapter,
               simulate_sleep_gap: false
             )

    assert File.read!(Path.join(pending.environment.worktree_path, "PATCH.txt")) ==
             "created by adapter\n"

    assert git!(pending.environment.worktree_path, ["status", "--porcelain"]) == ""

    assert git!(pending.environment.worktree_path, ["log", "-1", "--pretty=%s"]) ==
             "feat: Ship the walking skeleton"
  end

  defp configure_identity!(repo) do
    git!(repo, ["config", "user.name", "Cuckoding Test"])
    git!(repo, ["config", "user.email", "cuckoding@example.invalid"])
  end

  defp review_output(summary, transition, category) do
    %{
      "summary" => summary,
      "findings" => [
        %{
          "transition" => transition,
          "severity" => "error",
          "category" => category,
          "summary" => summary,
          "evidence" => %{"check" => category}
        }
      ]
    }
  end

  defp git!(directory, args) do
    case System.cmd(@git, args, cd: directory, stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed (#{status}): #{output}")
    end
  end

  defp free_port do
    {:ok, socket} = :gen_tcp.listen(0, [:binary, active: false, ip: {127, 0, 0, 1}])
    {:ok, {_address, port}} = :inet.sockname(socket)
    :ok = :gen_tcp.close(socket)
    port
  end

  defp use_fake_secret_store! do
    previous = Application.get_env(:cuckoding, :secret_store)
    Application.put_env(:cuckoding, :secret_store, FakeSecretStore)
    FakeSecretStore.reset()

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :secret_store, previous),
        else: Application.delete_env(:cuckoding, :secret_store)
    end)
  end

  defp eventually(assertion, attempts \\ 100)

  defp eventually(assertion, attempts) when attempts > 0 do
    if assertion.() do
      :ok
    else
      Process.sleep(20)
      eventually(assertion, attempts - 1)
    end
  end

  defp eventually(_assertion, 0), do: flunk("condition did not become true")
end
