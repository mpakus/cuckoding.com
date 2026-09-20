defmodule CuckodingWeb.AgentFloorLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.ActivityStream
  alias Cuckoding.Adapters.Types
  alias Cuckoding.AgentFloor
  alias Cuckoding.Execution
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Identifier
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Telemetry.Accounting
  alias Cuckoding.Telemetry.ResourceSample
  alias Cuckoding.Workflows
  alias CuckodingWeb.AgentFloorComponents

  @now ~U[2026-09-18 00:30:00.000000Z]

  test "projection and table remain bounded and complete at 100 cards" do
    fixture = domain_fixture(105)
    cards = AgentFloor.list_sessions()

    assert length(cards) == 100
    assert Enum.all?(cards, &(&1.project.id == fixture.project.id))

    groups = AgentFloor.group_sessions(cards, "role")

    html =
      render_component(&AgentFloorComponents.agent_floor/1,
        groups: groups,
        cards: cards,
        group_by: "role"
      )

    assert length(Regex.scan(~r/id="agent-card-[^"]+"/, html)) == 100
    assert html =~ "Agent table view"
    assert html =~ "Inspect agent"
    refute html =~ ~r/tabindex="[1-9]/
  end

  test "keyboard-operable journey reaches floor, run detail, and agent inspector", %{conn: conn} do
    fixture = domain_fixture(10, rich?: true)
    first_session = hd(fixture.sessions)

    {:ok, floor, html} = live(conn, ~p"/agents")
    assert html =~ "Agent Floor"
    assert has_element?(floor, "form[aria-label='Group Agent Floor'] select[name=group]")
    assert has_element?(floor, "details summary", "Agent table view")
    assert has_element?(floor, "[role=region][tabindex='0'][aria-label='Agent session table']")
    assert has_element?(floor, "h3", "Agent-001")
    assert has_element?(floor, "#agent-card-#{first_session.id} nav[aria-label]")
    refute render(floor) =~ ~r/tabindex="[1-9]/

    floor
    |> element("form[aria-label='Group Agent Floor']")
    |> render_change(%{"group" => "runtime"})

    assert_patch(floor, ~p"/agents?group=runtime")
    assert has_element?(floor, "#agent-lane-codex", "codex")

    agent_path = ~p"/agents/#{first_session.id}"

    assert {:error, {:live_redirect, %{to: ^agent_path}}} =
             floor
             |> element("#agent-card-#{first_session.id} a", "Inspect agent")
             |> render_click()

    {:ok, agent, _html} = live(conn, agent_path)
    assert has_element?(agent, "h1", "Agent-001 session")
    assert has_element?(agent, "a", "Manage project agents")
    assert has_element?(agent, "#host-runner-notice", "not a sandbox")
    assert has_element?(agent, "section[aria-labelledby=identity-heading]")
    assert has_element?(agent, "table caption", "Processes attributed")
    assert has_element?(agent, "[role=region][tabindex='0'][aria-label='Owned processes table']")
    assert has_element?(agent, "section[aria-labelledby=resources-heading]")

    run_path = ~p"/runs/#{fixture.run.id}"
    {:ok, run, _html} = live(conn, run_path)
    assert has_element?(run, "h1", "Run 1")
    assert has_element?(run, "#host-runner-notice", "not a sandbox")
    assert has_element?(run, "section[aria-labelledby=timeline-heading]")
    assert has_element?(run, "section[aria-labelledby=preview-heading]", "No preview is active")
    assert has_element?(run, "section[aria-labelledby=artifacts-heading]", "evidence.txt")
    assert has_element?(run, "[role=region][tabindex='0'][aria-label='Recent activity table']")
    assert has_element?(run, "section[aria-labelledby=findings-heading]", "Fixture finding")
    assert has_element?(run, "section[aria-labelledby=knowledge-heading]", "Phase 7")

    assert render(run) =~ "Estimated shell-output tokens avoided"
    assert render(run) =~ "(estimated)"

    assert has_element?(run, "section[aria-labelledby=resources-heading] table")
    assert has_element?(run, "section[aria-labelledby=usage-heading]", "$0.000123 USD")
    refute render(run) =~ fixture.run_dir
  end

  test "activity hints coalesce behind one floor refresh", %{conn: conn} do
    fixture = domain_fixture(1)
    {:ok, floor, _html} = live(conn, ~p"/agents")

    send(floor.pid, {:activity_event, fixture.run.id, 1})
    send(floor.pid, {:activity_event, fixture.run.id, 2})
    _html = render(floor)

    assert :sys.get_state(floor.pid).socket.assigns.refresh_pending
    send(floor.pid, :refresh_floor)
    assert render(floor) =~ "Agent Floor updated."
  end

  test "run logs follow the last 5000 lines, pause, reconnect, and download the full public log",
       %{conn: conn} do
    conn = %{conn | host: "127.0.0.1"}
    fixture = domain_fixture(1)
    log_id = Identifier.generate()
    path = Path.join([fixture.run_dir, "artifacts", "process-#{log_id}.log"])
    File.write!(path, Enum.map_join(1..5_005, &log_line/1))

    {:ok, view, _html} = live(conn, ~p"/runs/#{fixture.run.id}")
    assert has_element?(view, "#run-log-status", "Showing 5000 lines")
    assert has_element?(view, "#run-log-output", "public-line-00006")
    refute has_element?(view, "#run-log-output", "public-line-00005")
    assert has_element?(view, "#run-log-output", "public-line-05005")

    File.write!(path, log_line(5_006), [:append])
    send(view.pid, :refresh_log)
    assert has_element?(view, "#run-log-output", "public-line-05006")
    refute has_element?(view, "#run-log-output", "public-line-00006")

    view |> element("button[phx-click=toggle-log]") |> render_click()
    File.write!(path, log_line(5_007), [:append])
    send(view.pid, :refresh_log)
    refute has_element?(view, "#run-log-output", "public-line-05007")
    view |> element("button[phx-click=toggle-log]") |> render_click()
    assert has_element?(view, "#run-log-output", "public-line-05007")

    {:ok, reconnected, _html} = live(conn, ~p"/runs/#{fixture.run.id}")
    assert has_element?(reconnected, "#run-log-output", "public-line-05007")
    download = get(conn, ~p"/runs/#{fixture.run.id}/logs/#{log_id}")
    body = response(download, 200)
    assert body =~ "public-line-00001"
    assert body =~ "public-line-05007"
    assert length(String.split(body, "\n", trim: true)) == 5_007
    assert get_resp_header(download, "cache-control") == ["no-store"]

    File.write!(path, log_line(42))
    send(view.pid, :refresh_log)
    assert has_element?(view, "#run-log-status", "Showing 1 lines")
    refute has_element?(view, "#run-log-output", "public-line-05007")

    second_id = Identifier.generate()

    File.write!(
      Path.join([fixture.run_dir, "artifacts", "process-#{second_id}.log"]),
      log_line(7)
    )

    send(view.pid, :refresh_run)
    view |> form("#run-log-select") |> render_change(%{"process_id" => second_id})
    assert has_element?(view, "#run-log-output", "public-line-00007")
    refute has_element?(view, "#run-log-output", "public-line-00042")
  end

  test "log preview and download exclude secrets, hidden reasoning, malformed and oversized entries",
       %{conn: conn} do
    conn = %{conn | host: "127.0.0.1"}
    fixture = domain_fixture(1)
    log_id = Identifier.generate()
    path = Path.join([fixture.run_dir, "artifacts", "process-#{log_id}.log"])

    rows = [
      Jason.encode!(%{
        type: "item.completed",
        item: %{type: "reasoning", text: "PRIVATE-THOUGHT"}
      }),
      Jason.encode!(%{
        type: "error",
        error: %{message: "Public failure", token: "SECRET-CANARY"}
      }),
      "unsupported-SECRET-CANARY",
      <<255, 254>>,
      String.duplicate("x", 200_000),
      String.trim_trailing(log_line(99))
    ]

    File.write!(path, Enum.join(rows, "\n"))
    assert {:ok, tail} = Cuckoding.RunLog.tail(fixture.run.id, log_id)
    download = get(conn, ~p"/runs/#{fixture.run.id}/logs/#{log_id}") |> response(200)

    for text <- [tail.text, download] do
      assert text =~ "Public failure"
      assert text =~ "public-line-00099"
      assert text =~ "Entry omitted"
      refute text =~ "PRIVATE-THOUGHT"
      refute text =~ "SECRET-CANARY"
      refute text =~ String.duplicate("x", 1_000)
    end
  end

  test "tail remains bounded for huge lines and reads a replaced log", %{conn: _conn} do
    fixture = domain_fixture(1)
    log_id = Identifier.generate()
    path = Path.join([fixture.run_dir, "artifacts", "process-#{log_id}.log"])
    File.write!(path, [String.duplicate("x", 9_000_000), "\n", log_line(1)])

    assert {:ok, %{limited?: true, lines: 1, text: text}} =
             Cuckoding.RunLog.tail(fixture.run.id, log_id)

    assert text =~ "public-line-00001"
    File.rename!(path, path <> ".old")
    File.write!(path, log_line(2))

    assert {:ok, %{limited?: false, lines: 1, text: text}} =
             Cuckoding.RunLog.tail(fixture.run.id, log_id)

    assert text =~ "public-line-00002"
  end

  test "a prepared task links to its queued run instead of preparing another", %{conn: conn} do
    fixture = domain_fixture(1)
    task = Repo.get!(Cuckoding.Workflows.Task, fixture.run.task_id)
    task |> Ecto.Changeset.change(state: "ready") |> Repo.update!()
    {:ok, view, _html} = live(conn, ~p"/boards/#{task.board_id}/tasks/#{task.id}")
    assert has_element?(view, "a[href='/runs/#{fixture.run.id}']", "Open prepared run and start")
    refute has_element?(view, "#prepare-task-run")
    assert length(Execution.list_runs(task.id)) == 1
  end

  test "log access rejects other runs, invalid IDs, symlinks, and unauthenticated sessions", %{
    conn: conn
  } do
    conn = %{conn | host: "127.0.0.1"}
    fixture = domain_fixture(1)
    other = domain_fixture(1)
    log_id = Identifier.generate()
    path = Path.join([fixture.run_dir, "artifacts", "process-#{log_id}.log"])
    File.write!(path, log_line(1))
    assert {:error, :log_unavailable} = Cuckoding.RunLog.tail(other.run.id, log_id)
    assert {:error, :log_unavailable} = Cuckoding.RunLog.tail(fixture.run.id, "../outside")
    assert get(conn, ~p"/runs/#{other.run.id}/logs/#{log_id}") |> response(404)

    prior = Application.get_env(:cuckoding, :shell_bootstrap_file)
    Application.put_env(:cuckoding, :shell_bootstrap_file, "/not-read-by-this-test")

    on_exit(fn ->
      if prior,
        do: Application.put_env(:cuckoding, :shell_bootstrap_file, prior),
        else: Application.delete_env(:cuckoding, :shell_bootstrap_file)
    end)

    assert get(conn, ~p"/runs/#{fixture.run.id}/logs/#{log_id}") |> response(401)

    authorized = init_test_session(conn, browser_authenticated: true)
    assert get(authorized, ~p"/runs/#{fixture.run.id}/logs/#{log_id}") |> response(200)

    assert get(
             %{authorized | host: "attacker.example"},
             ~p"/runs/#{fixture.run.id}/logs/#{log_id}"
           )
           |> response(403)

    linked_id = Identifier.generate()
    linked_path = Path.join([fixture.run_dir, "artifacts", "process-#{linked_id}.log"])
    File.ln_s!(path, linked_path)
    assert {:error, :log_unavailable} = Cuckoding.RunLog.tail(fixture.run.id, linked_id)

    hardlinked_id = Identifier.generate()
    hardlinked_path = Path.join([fixture.run_dir, "artifacts", "process-#{hardlinked_id}.log"])
    File.ln!(path, hardlinked_path)
    assert {:error, :log_unavailable} = Cuckoding.RunLog.tail(fixture.run.id, hardlinked_id)
    File.rm!(hardlinked_path)

    File.rename!(Path.join(fixture.run_dir, "artifacts"), Path.join(fixture.run_dir, "moved"))
    File.ln_s!(Path.join(fixture.run_dir, "moved"), Path.join(fixture.run_dir, "artifacts"))
    assert {:error, :log_unavailable} = Cuckoding.RunLog.tail(fixture.run.id, log_id)
  end

  defp log_line(number) do
    Jason.encode!(%{
      type: "item.completed",
      item: %{
        type: "agent_message",
        text: "public-line-#{String.pad_leading(to_string(number), 5, "0")}"
      }
    }) <> "\n"
  end

  test "resolved runs do not retain stale attention from earlier attempts" do
    fixture = domain_fixture(1)
    session = hd(fixture.sessions)
    attempt = Repo.get!(StageAttempt, session.stage_attempt_id)

    attempt |> Ecto.Changeset.change(state: "failed") |> Repo.update!()
    fixture.run |> Ecto.Changeset.change(state: "done") |> Repo.update!()

    refute AgentFloor.list_sessions() |> hd() |> Map.fetch!(:attention?)

    fixture.run |> Ecto.Changeset.change(state: "failed") |> Repo.update!()

    assert AgentFloor.list_sessions() |> hd() |> Map.fetch!(:attention?)
  end

  defp domain_fixture(count, options \\ []) do
    suffix = System.unique_integer([:positive])
    run_dir = Path.join(System.tmp_dir!(), "cuckoding-floor-#{suffix}")
    worktree = Path.join(run_dir, "worktree")
    File.mkdir_p!(Path.join(run_dir, "artifacts"))
    File.mkdir_p!(worktree)
    on_exit(fn -> File.rm_rf!(run_dir) end)

    {:ok, project} =
      Projects.register(%{
        name: "Floor Project #{suffix}",
        repo_path: "/tmp/floor-project-#{suffix}",
        default_branch: "main",
        workspace_root: "/tmp/floor-workspaces-#{suffix}",
        port_range_start: 47_000,
        port_range_end: 47_100
      })

    {:ok, config} =
      Projects.add_config_version(%{
        project_id: project.id,
        revision: 1,
        source_hash: String.pad_leading(Integer.to_string(suffix, 16), 64, "0"),
        config_json: %{"version" => 1},
        trusted_at: @now
      })

    {:ok, workflow} =
      Workflows.publish_workflow(%{
        project_id: project.id,
        name: "default",
        version: 1,
        definition_json: %{"stages" => [%{"key" => "agent", "role" => "implementer"}]},
        published_at: @now
      })

    {:ok, board} =
      Workflows.create_board(%{
        project_id: project.id,
        workflow_version_id: workflow.id,
        name: "Floor Board #{suffix}",
        concurrency_limit: max(count, 1)
      })

    {:ok, task} = Workflows.create_task(%{board_id: board.id, title: "Floor task", position: 0})

    {:ok, run} =
      Execution.create_run(%{
        task_id: task.id,
        sequence: 1,
        policy_snapshot_id: config.id,
        plugin_snapshot_json: %{
          "rtk" => %{
            "enabled" => true,
            "contribution" => "Estimated shell-output tokens avoided",
            "source" => "estimated"
          }
        },
        branch: "feature/floor-#{suffix}",
        base_sha: String.duplicate("a", 40)
      })

    {:ok, environment} =
      Execution.create_environment(%{
        run_id: run.id,
        runner_key: "local_process",
        kind: "local_process",
        worktree_path: worktree,
        run_dir: run_dir,
        base_sha: run.base_sha,
        ports_json: %{},
        isolation_claims_json: %{}
      })

    {attempts, sessions} = create_sessions(run, count)

    if options[:rich?] do
      enrich_fixture(run, environment, hd(attempts), hd(sessions), run_dir)
    end

    %{project: project, run: run, run_dir: run_dir, sessions: sessions}
  end

  defp create_sessions(run, count) do
    1..count
    |> Enum.map(fn index ->
      role = "agent-#{String.pad_leading(Integer.to_string(index), 3, "0")}"

      {:ok, attempt} =
        Execution.create_stage_attempt(%{
          run_id: run.id,
          stage_key: role,
          attempt: 1,
          role_key: role,
          role_kind: "agent"
        })

      {:ok, session} =
        Execution.create_agent_session(%{
          stage_attempt_id: attempt.id,
          adapter_key: if(rem(index, 2) == 0, do: "claude_code", else: "codex"),
          requested_model: "fixture-model",
          effective_grant_json: %{"enforced" => %{"paths" => true}}
        })

      {attempt, session}
    end)
    |> Enum.unzip()
  end

  defp enrich_fixture(run, environment, attempt, session, run_dir) do
    assert {:ok, _command} =
             Execution.transition_stage_attempt(
               attempt.id,
               "running",
               "floor:#{attempt.id}:running"
             )

    assert {:ok, _finding} =
             Workflows.record_finding(%{
               run_id: run.id,
               stage_attempt_id: attempt.id,
               severity: "warning",
               category: "fixture",
               summary: "Fixture finding",
               evidence_json: %{}
             })

    assert {:ok, process} =
             Execution.record_process(%{
               environment_id: environment.id,
               agent_session_id: session.id,
               pid: 90_000,
               pgid: 90_000,
               start_identity: "floor-fixture",
               role: "agent:codex"
             })

    %ResourceSample{}
    |> ResourceSample.create_changeset(%{
      id: Identifier.generate(),
      agent_session_id: session.id,
      process_id: process.id,
      cpu_nanos: 4_000,
      memory_bytes: 2_048,
      process_count: 1,
      open_ports_json: [],
      sampled_at: @now,
      limits_enforced: false
    })
    |> Repo.insert!()

    assert {:ok, _usage} =
             Accounting.record_usage(
               session.id,
               "floor-usage",
               %Types.Usage{
                 source: "provider",
                 confidence: "reported",
                 input_tokens: 10,
                 output_tokens: 5,
                 cost_micros: 123,
                 currency: "USD"
               },
               occurred_at: @now
             )

    assert {:ok, _event} =
             ActivityStream.record(session, %Types.Event{
               event_id: "floor-event",
               sequence: 1,
               type: "activity.summary",
               public_summary: "Implementing fixture",
               metadata: %{},
               trust: :untrusted
             })

    File.write!(Path.join([run_dir, "artifacts", "evidence.txt"]), "fixture")
  end
end
