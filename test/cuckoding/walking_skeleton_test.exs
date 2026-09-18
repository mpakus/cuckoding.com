defmodule Cuckoding.WalkingSkeletonTest do
  use CuckodingWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.Execution.LocalBareRemote
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Repo
  alias Cuckoding.WalkingSkeleton

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

  test "LiveView requires an explicit confirmation before host-side release",
       %{
         conn: conn
       } = fixture do
    assert {:ok, created} = WalkingSkeleton.create(fixture.attrs)
    assert {:ok, pending} = WalkingSkeleton.run(created, simulate_sleep_gap: false)
    assert {:ok, view, _html} = live(conn, ~p"/")

    selector = "#approval-#{pending.approval.id}"
    assert has_element?(view, selector, "Ship the walking skeleton")
    refute has_element?(view, "#{selector} button", "Approve and push")

    view |> element("#{selector} button", "Review release") |> render_click()
    assert has_element?(view, "#{selector} [role=alert]", "Confirm pushing")
    assert has_element?(view, "#{selector} button", "Approve and push")
    assert has_element?(view, "#{selector} button", "Cancel")

    view |> element("#{selector} button", "Approve and push") |> render_click()
    assert render(view) =~ "Approved branch pushed to the local bare remote."
    refute has_element?(view, selector)
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
end
