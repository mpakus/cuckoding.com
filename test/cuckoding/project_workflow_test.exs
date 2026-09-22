defmodule Cuckoding.ProjectWorkflowTest do
  use CuckodingWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.ProcessRecord
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.ProjectOnboarding
  alias Cuckoding.ProjectWorkflow
  alias Cuckoding.Repo
  alias Cuckoding.WalkingSkeleton
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.RoleAssignment

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "cuckoding-project-workflow-#{System.unique_integer([:positive])}"
      )

    repo_path = Path.join(root, "repo")
    workspace_root = Path.join(root, "workspaces")
    File.mkdir_p!(repo_path)
    git!(repo_path, ["init", "-b", "main"])
    git!(repo_path, ["config", "user.email", "tests@cuckoding.local"])
    git!(repo_path, ["config", "user.name", "Cuckoding Tests"])
    File.write!(Path.join(repo_path, "README.md"), "# Project workflow\n")
    git!(repo_path, ["add", "README.md"])
    git!(repo_path, ["commit", "-m", "Initial commit"])

    previous = Application.get_env(:cuckoding, :workspace_root)
    Application.put_env(:cuckoding, :workspace_root, workspace_root)

    assert {:ok, %{project: project}} =
             ProjectOnboarding.create(%{
               "name" => "Workflow project",
               "description" => "",
               "repo_path" => repo_path,
               "default_branch" => "main"
             })

    assert {:ok, _config} =
             ProjectOnboarding.update_configuration(project.id, 1, %{
               "agent_connections" => [
                 %{
                   "key" => "codex-local",
                   "label" => "Local Codex",
                   "adapter_key" => "codex",
                   "executable_path" => "/usr/bin/true",
                   "api_key_helper" => "",
                   "model" => "gpt-6-astra",
                   "reasoning_effort" => "high"
                 }
               ],
               "default_roles" =>
                 Enum.map(ProjectOnboarding.default_roles(), fn role ->
                   Map.put(role, "agent_connection_key", "codex-local")
                 end)
             })

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :workspace_root, previous),
        else: Application.delete_env(:cuckoding, :workspace_root)

      File.rm_rf!(root)
    end)

    %{project: project}
  end

  test "prepares a ready task from the board snapshot and exposes it to monitoring", %{
    conn: conn,
    project: project
  } do
    assert {:ok, board} =
             ProjectWorkflow.create_board(project.id, %{
               "name" => "Product",
               "description" => "Default workflow",
               "concurrency_limit" => "1"
             })

    assert Repo.aggregate(
             from(role in RoleAssignment, where: role.board_id == ^board.id),
             :count
           ) == 5

    assert {:ok, task} =
             ProjectWorkflow.create_task(board.id, %{
               "title" => "Ship monitored work",
               "description" => "Create durable evidence",
               "priority" => "3"
             })

    assert {:ok, %{result: %{"outcome" => "transitioned"}}} =
             Workflows.transition_task(task.id, "ready", "test:#{task.id}:ready")

    assert {:ok, %{run: run, environment: environment}} = ProjectWorkflow.prepare_task(task.id)
    assert run.state == "queued"
    assert File.dir?(environment.worktree_path)
    run_id = run.id
    assert %Environment{run_id: ^run_id} = Repo.get_by!(Environment, run_id: run_id)

    snapshot_roles = run.workflow_snapshot_json["roles"]

    assert Enum.map(snapshot_roles, & &1["role_key"]) ==
             ~w(approver implementer release reviewer spec_writer)

    implementer = Enum.find(snapshot_roles, &(&1["role_key"] == "implementer"))
    assert implementer["adapter_key"] == "codex"
    assert implementer["model_ref"] == "gpt-6-astra"
    assert implementer["settings"]["model"] == "gpt-6-astra"
    assert implementer["settings"]["reasoning_effort"] == "high"
    assert implementer["settings"]["connection_label"] == "Local Codex"
    assert is_binary(implementer["settings"]["provider_account_id"])

    assert {:ok, setups} = Cuckoding.GuidedRun.runtime_setups(run.id)
    setup = Enum.find(setups, &(&1.role_key == "implementer"))

    assert setup.command ==
             "CODEX_HOME='#{setup.home}' '/usr/bin/true' -c 'cli_auth_credentials_store=\"file\"' login --device-auth"

    assert {:error, :run_already_prepared} = ProjectWorkflow.prepare_task(task.id)

    assert Repo.exists?(
             from(event in RunEvent,
               where:
                 event.run_id == ^("board:" <> board.id) and event.event_type == "board.created"
             )
           )

    assert Repo.exists?(
             from(event in RunEvent,
               where: event.run_id == ^("task:" <> task.id) and event.event_type == "run.prepared"
             )
           )

    {:ok, task_view, _html} = live(conn, ~p"/boards/#{board.id}/tasks/#{task.id}")
    assert has_element?(task_view, "#run-history-heading", "Run history")
    assert has_element?(task_view, "a[href='/runs/#{run.id}']", "Open run")

    {:ok, run_view, _html} = live(conn, ~p"/runs/#{run.id}")

    refute has_element?(run_view, "#runtime-setup input[data-copy-source]")

    assert has_element?(run_view, "#runtime-setup a", "Check sign-in for Local Codex")

    assert has_element?(run_view, "#runtime-setup p", "Roles: Implementer, Reviewer, Spec writer")

    assert has_element?(task_view, "p", "waiting for authentication")

    {:ok, dashboard, _html} = live(conn, ~p"/")
    assert has_element?(dashboard, "#operation-#{run.id}", "Ship monitored work")
    assert has_element?(dashboard, "#operation-#{run.id}", "Queued")
    assert has_element?(dashboard, "#operation-#{run.id}", "Waiting for launch")
    assert has_element?(dashboard, "#project-#{project.id}", "Tasks")
  end

  test "two boards execute concurrently without crossing worktrees or evidence", %{
    project: project
  } do
    prepared =
      for {board_name, title} <- [
            {"Product", "Product change"},
            {"Maintenance", "Maintenance fix"}
          ] do
        {:ok, board} =
          ProjectWorkflow.create_board(project.id, %{
            "name" => board_name,
            "concurrency_limit" => "1"
          })

        {:ok, task} = ProjectWorkflow.create_task(board.id, %{"title" => title})

        assert_transition(
          Workflows.transition_task(task.id, "ready", "two-board:#{task.id}:ready")
        )

        {:ok, %{run: run, environment: environment}} = ProjectWorkflow.prepare_task(task.id)

        assert_transition(
          Execution.transition_run(run.id, "running", "two-board:#{run.id}:running")
        )

        {:ok, skeleton} = WalkingSkeleton.load(run.id)
        %{board: board, task: task, run: run, environment: environment, skeleton: skeleton}
      end

    assert length(Enum.uniq_by(prepared, & &1.environment.worktree_path)) == 2
    assert length(Enum.uniq_by(prepared, & &1.run.branch)) == 2
    parent = self()

    implementation = fn environment ->
      send(parent, {:candidate_ready, self(), environment.run_id})

      receive do
        :continue -> :ok
      after
        10_000 -> raise "concurrent board barrier timed out"
      end

      File.write!(Path.join(environment.worktree_path, "WALKING_SKELETON.md"), environment.run_id)
      GitService.commit_candidate(environment, ["WALKING_SKELETON.md"], "test: own candidate")
    end

    workers =
      Enum.map(prepared, fn %{skeleton: skeleton} ->
        Task.async(fn ->
          WalkingSkeleton.run(skeleton,
            simulate_sleep_gap: false,
            fake_implementation: implementation
          )
        end)
      end)

    assert_receive {:candidate_ready, first_pid, first_run_id}, 20_000
    assert_receive {:candidate_ready, second_pid, second_run_id}, 20_000
    assert first_run_id != second_run_id
    send(first_pid, :continue)
    send(second_pid, :continue)
    assert Enum.all?(workers, &match?({:ok, _}, Task.await(&1, 30_000)))

    for %{board: board, task: task, run: run, environment: environment} <- prepared do
      assert Repo.get!(Run, run.id).state == "waiting"
      assert Workflows.get_task(task.id).state == "waiting"
      assert File.read!(Path.join(environment.worktree_path, "WALKING_SKELETON.md")) == run.id

      assert File.read!(Path.join([environment.run_dir, "artifacts", "specification.md"])) =~
               task.title

      marker = environment.run_dir |> Path.join("run.json") |> File.read!() |> Jason.decode!()

      assert Map.take(marker, ~w(board_id task_id run_id)) == %{
               "board_id" => board.id,
               "task_id" => task.id,
               "run_id" => run.id
             }

      events = Repo.all(from(event in RunEvent, where: event.run_id == ^run.id))
      assert events != []
      assert Enum.all?(events, &(get_in(&1.payload, ["correlation", "board_id"]) == board.id))
      assert Enum.all?(events, &(get_in(&1.payload, ["correlation", "task_id"]) == task.id))
    end
  end

  test "task page shows durable agent messages and refreshes after new activity", %{
    project: project,
    conn: conn
  } do
    {:ok, board} =
      ProjectWorkflow.create_board(project.id, %{"name" => "Evidence", "concurrency_limit" => "1"})

    {:ok, task} = ProjectWorkflow.create_task(board.id, %{"title" => "Track agent work"})
    {:ok, _} = Workflows.transition_task(task.id, "ready", "evidence-ready:#{task.id}")
    {:ok, %{run: run}} = ProjectWorkflow.prepare_task(task.id)

    {:ok, attempt} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "specification",
        attempt: 1,
        role_key: "spec_writer",
        role_kind: "agent"
      })

    {:ok, _} =
      EventStore.append(run.id, %{
        event_type: "activity.summary",
        public_summary: "# Source specification\n\nCheck the legal API.",
        payload: %{"stage_attempt_id" => attempt.id}
      })

    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}/tasks/#{task.id}")
    assert has_element?(view, "#task-specification", "Check the legal API")
    assert has_element?(view, "#task-messages", "Source specification")

    {:ok, development} =
      Execution.create_stage_attempt(%{
        run_id: run.id,
        stage_key: "development",
        attempt: 1,
        role_key: "implementer",
        role_kind: "agent"
      })

    {:ok, _} =
      EventStore.append(run.id, %{
        event_type: "activity.summary",
        public_summary: "Implementation is starting.",
        payload: %{"stage_attempt_id" => development.id}
      })

    {:ok, _} =
      EventStore.append(run.id, %{
        event_type: "stage_attempt.transitioned",
        public_summary: "Development started",
        payload: %{"stage_attempt_id" => development.id}
      })

    Process.sleep(300)
    assert has_element?(view, "#task-messages", "Implementation is starting")
    assert has_element?(view, "#task-messages", "Development started")
  end

  test "blocked and failed delivery tasks can prepare distinct retries without losing old runs",
       %{
         project: project,
         conn: conn
       } do
    {:ok, board} =
      ProjectWorkflow.create_board(project.id, %{
        "name" => "Retry board",
        "concurrency_limit" => "1"
      })

    {:ok, task} = ProjectWorkflow.create_task(board.id, %{"title" => "Retry this work"})
    assert_transition(Workflows.transition_task(task.id, "ready", "retry-test:ready"))
    {:ok, %{run: first, environment: first_environment}} = ProjectWorkflow.prepare_task(task.id)
    assert_transition(Execution.transition_run(first.id, "running", "retry-test:first-running"))
    assert_transition(Execution.transition_run(first.id, "blocked", "retry-test:first-blocked"))

    {:ok, run_view, _html} = live(conn, ~p"/runs/#{first.id}")
    assert has_element?(run_view, "#run-failure a", "Open task to retry with a new run")

    {:ok, task_view, _html} = live(conn, ~p"/boards/#{board.id}/tasks/#{task.id}")
    assert has_element?(task_view, "#retry-task", "Retry with a new run")
    render_click(element(task_view, "#retry-task"))
    assert_redirect(task_view)

    [second, preserved] = Execution.list_runs(task.id)
    assert preserved.id == first.id
    assert preserved.state == "failed"
    assert second.state == "queued"
    assert second.branch != first.branch
    assert File.dir?(first_environment.worktree_path)
    assert {:error, :task_not_retryable} = ProjectWorkflow.retry_task(task.id)
    assert length(Execution.list_runs(task.id)) == 2

    assert_transition(Execution.transition_run(second.id, "running", "retry-test:second-running"))
    assert_transition(Execution.transition_run(second.id, "failed", "retry-test:second-failed"))
    assert {:ok, %{run: third}} = ProjectWorkflow.retry_task(task.id)
    assert third.sequence == 3
    assert third.branch != second.branch
    assert Repo.get!(Run, second.id).state == "failed"

    assert {:ok, %{result: %{"outcome" => "failed"}}} =
             Execution.fail_run_preparation(third.id, :branch_exists)

    assert {:ok, %{result: %{"outcome" => "failed"}}} =
             Execution.fail_run_preparation(third.id, :branch_exists)

    assert Repo.get!(Run, third.id).state == "failed"

    {:ok, history_view, _html} = live(conn, ~p"/boards/#{board.id}/tasks/#{task.id}")
    assert has_element?(history_view, "#task-messages", "Run preparation failed")

    assert Repo.aggregate(
             from(event in RunEvent,
               where: event.run_id == ^third.id and event.event_type == "run.preparation_failed"
             ),
             :count
           ) == 1

    assert Workflows.get_task(task.id).state == "ready"
    assert {:ok, %{run: fourth}} = ProjectWorkflow.prepare_task(task.id)
    assert fourth.sequence == 4
  end

  test "retry refuses a blocked run with a recorded live process", %{project: project} do
    {:ok, board} =
      ProjectWorkflow.create_board(project.id, %{
        "name" => "Guarded retry",
        "concurrency_limit" => "1"
      })

    {:ok, task} = ProjectWorkflow.create_task(board.id, %{"title" => "Guarded work"})
    assert_transition(Workflows.transition_task(task.id, "ready", "guarded:ready"))
    {:ok, %{run: run, environment: environment}} = ProjectWorkflow.prepare_task(task.id)
    assert_transition(Execution.transition_run(run.id, "running", "guarded:running"))
    assert_transition(Execution.transition_run(run.id, "blocked", "guarded:blocked"))

    assert {:ok, %ProcessRecord{}} =
             Execution.record_process(%{
               environment_id: environment.id,
               pid: 99_999,
               pgid: 99_999,
               start_identity: "retry-test",
               role: "agent"
             })

    assert {:error, :previous_process_running} = ProjectWorkflow.retry_task(task.id)
    assert Repo.get!(Run, run.id).state == "blocked"
    assert length(Execution.list_runs(task.id)) == 1
  end

  test "failed retry preparation leaves the task Ready with the old run intact", %{
    project: project,
    conn: conn
  } do
    {:ok, board} =
      ProjectWorkflow.create_board(project.id, %{
        "name" => "Retry preparation",
        "concurrency_limit" => "1"
      })

    {:ok, task} = ProjectWorkflow.create_task(board.id, %{"title" => "Needs clean base"})
    assert_transition(Workflows.transition_task(task.id, "ready", "retry-dirty:ready"))
    {:ok, %{run: run}} = ProjectWorkflow.prepare_task(task.id)
    assert_transition(Execution.transition_run(run.id, "running", "retry-dirty:running"))
    assert_transition(Execution.transition_run(run.id, "blocked", "retry-dirty:blocked"))
    File.write!(Path.join(project.repo_path, "UNCOMMITTED"), "keep this\n")

    {:ok, view, _html} = live(conn, ~p"/boards/#{board.id}/tasks/#{task.id}")
    render_click(element(view, "#retry-task"))
    assert has_element?(view, "#task-error", "Commit or stash changes")
    assert has_element?(view, "#prepare-task-run", "Prepare run")

    assert Workflows.get_task(task.id).state == "ready"
    assert Repo.get!(Run, run.id).state == "failed"
    assert length(Execution.list_runs(task.id)) == 1
  end

  test "setup-only roles fail before a run or worktree is created", %{project: project} do
    assert {:ok, _config} =
             ProjectOnboarding.update_configuration(project.id, 2, %{
               "agent_connections" => [
                 %{
                   "key" => "opencode-local",
                   "label" => "Local OpenCode",
                   "adapter_key" => "opencode",
                   "executable_path" => "/usr/bin/true",
                   "api_key_helper" => ""
                 }
               ],
               "default_roles" =>
                 Enum.map(ProjectOnboarding.default_roles(), fn role ->
                   Map.put(role, "agent_connection_key", "opencode-local")
                 end)
             })

    assert {:ok, board} =
             ProjectWorkflow.create_board(project.id, %{
               "name" => "Setup only",
               "description" => "",
               "concurrency_limit" => "1"
             })

    assert {:ok, task} =
             ProjectWorkflow.create_task(board.id, %{
               "title" => "Do not launch",
               "description" => "",
               "priority" => "0"
             })

    assert {:ok, _command} =
             Workflows.transition_task(task.id, "ready", "test:#{task.id}:ready")

    assert {:error, :runtime_setup_only} = ProjectWorkflow.prepare_task(task.id)
    assert Execution.list_runs(task.id) == []
  end

  test "Cursor roles share one saved account setup", %{
    project: project
  } do
    assert {:ok, _config} =
             ProjectOnboarding.update_configuration(project.id, 2, %{
               "agent_connections" => [
                 %{
                   "key" => "cursor-local",
                   "label" => "Local Cursor",
                   "adapter_key" => "cursor_agent",
                   "executable_path" => "/usr/bin/true"
                 }
               ],
               "default_roles" =>
                 Enum.map(ProjectOnboarding.default_roles(), fn role ->
                   Map.put(role, "agent_connection_key", "cursor-local")
                 end)
             })

    assert {:ok, board} =
             ProjectWorkflow.create_board(project.id, %{
               "name" => "Cursor board",
               "description" => "",
               "concurrency_limit" => "1"
             })

    assert {:ok, task} =
             ProjectWorkflow.create_task(board.id, %{
               "title" => "Run Cursor safely",
               "description" => "",
               "priority" => "0"
             })

    assert {:ok, _command} =
             Workflows.transition_task(task.id, "ready", "test:#{task.id}:ready")

    assert {:ok, %{run: run}} = ProjectWorkflow.prepare_task(task.id)
    assert {:ok, setups} = Cuckoding.GuidedRun.runtime_setups(run.id)
    assert Enum.all?(setups, &(&1.runtime == "Cursor Agent"))
    assert length(setups) == 1

    for setup <- setups do
      assert setup.home =~ "/#{setup.account_id}/cursor"
      assert setup.reusable?
      assert setup.command =~ "CLAUDE_CONFIG_DIR='"
      assert setup.command =~ "CURSOR_CONFIG_DIR='"
      assert setup.command =~ "HOME='"
      assert setup.command =~ "'/usr/bin/true' login"
    end
  end

  test "explicit legacy connections preserve tasks and immutable run snapshots", %{
    project: project,
    conn: conn
  } do
    {:ok, board} =
      ProjectWorkflow.create_board(project.id, %{"name" => "Legacy", "concurrency_limit" => "1"})

    roles = Workflows.list_agent_roles(board.id)
    account_id = hd(roles).settings_json["provider_account_id"]

    for role <- roles do
      role
      |> Ecto.Changeset.change(
        settings_json: Map.delete(role.settings_json, "provider_account_id")
      )
      |> Repo.update!()
    end

    {:ok, task} = ProjectWorkflow.create_task(board.id, %{"title" => "Keep this task"})
    {:ok, _transition} = Workflows.transition_task(task.id, "ready", "legacy-ready")
    {:ok, %{run: run}} = ProjectWorkflow.prepare_task(task.id)
    snapshot = run.workflow_snapshot_json
    assert {:ok, _board} = ProjectWorkflow.connect_saved_agents(board.id, 2)

    assert Enum.all?(
             Workflows.list_agent_roles(board.id),
             &(&1.settings_json["provider_account_id"] == account_id)
           )

    assert Repo.get!(Cuckoding.Execution.Run, run.id).workflow_snapshot_json == snapshot
    assert Workflows.get_task(task.id).title == "Keep this task"

    assert {:ok, incompatible} =
             Cuckoding.Adapters.save_provider_account(%{
               label: "Other Codex",
               adapter_key: "codex",
               auth_mode: "shared_profile",
               capabilities_json: %{
                 "settings" => %{"executable_path" => "/usr/bin/false", "api_key_helper" => ""}
               }
             })

    {:ok, home} = Cuckoding.Adapters.SharedProfile.prepare(account_id, "codex")
    File.write!(Path.join(home, "auth.json"), "{}")
    File.chmod!(Path.join(home, "auth.json"), 0o600)
    Cuckoding.Adapters.record_provider_status(account_id, "authenticated")
    {:ok, view, _html} = live(conn, ~p"/runs/#{run.id}")

    assert has_element?(view, "#connect-agent-implementer select[name='binding[account_id]']")
    assert has_element?(view, "#connect-agent-implementer option[value='#{account_id}']")
    refute has_element?(view, "#connect-agent-implementer option[value='#{incompatible.id}']")
    refute has_element?(view, "#connect-agent-implementer[data-confirm]")
    assert has_element?(view, "#connect-agent-implementer button[data-confirm]")
    refute has_element?(view, "#runtime-setup input[data-copy-source]")

    view
    |> form("#connect-agent-implementer", binding: %{account_id: account_id})
    |> render_submit()

    assert Cuckoding.AgentBindings.for_run(run.id)["implementer"] == account_id
    assert Repo.get!(Cuckoding.Execution.Run, run.id).workflow_snapshot_json == snapshot
    refute has_element?(view, "#connect-agent-implementer")
    assert has_element?(view, "#runtime-setup p", "Connected · sign-in checked again at start")
    assert has_element?(view, "#runtime-setup a", "Re-authorize agent")

    assert {:error, :provider_account_mismatch} =
             Cuckoding.AgentBindings.connect_run(run.id, "reviewer", Ecto.UUID.generate())

    run |> Ecto.Changeset.change(state: "running") |> Repo.update!()

    assert {:error, :run_not_queued_or_role_missing} =
             Cuckoding.AgentBindings.connect_run(run.id, "reviewer", account_id)
  end

  test "queued run identifies a saved agent whose file-store sign-in is missing", %{
    project: project,
    conn: conn
  } do
    executable = Path.join(Path.dirname(project.repo_path), "codex-status-fixture")

    File.write!(
      executable,
      "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'codex-cli 0.146.0'; else echo 'Logged in using ChatGPT'; fi\n"
    )

    File.chmod!(executable, 0o700)

    revision = Cuckoding.Projects.latest_config_version(project.id).revision

    assert {:ok, _config} =
             ProjectOnboarding.update_configuration(project.id, revision, %{
               "agent_connections" => [
                 %{
                   "key" => "saved-codex",
                   "label" => "Saved Codex",
                   "adapter_key" => "codex",
                   "executable_path" => executable,
                   "api_key_helper" => ""
                 }
               ],
               "default_roles" =>
                 Enum.map(ProjectOnboarding.default_roles(), fn role ->
                   Map.put(role, "agent_connection_key", "saved-codex")
                 end)
             })

    {:ok, board} =
      ProjectWorkflow.create_board(project.id, %{
        "name" => "Authorization",
        "concurrency_limit" => "1"
      })

    account_id = hd(Workflows.list_agent_roles(board.id)).settings_json["provider_account_id"]
    {:ok, task} = ProjectWorkflow.create_task(board.id, %{"title" => "Check saved sign-in"})
    {:ok, _} = Workflows.transition_task(task.id, "ready", "auth-ready:#{task.id}")
    {:ok, %{run: run, environment: environment}} = ProjectWorkflow.prepare_task(task.id)

    Cuckoding.Adapters.record_provider_status(account_id, "authenticated")
    {:ok, view, _html} = live(conn, ~p"/runs/#{run.id}")
    assert has_element?(view, "#runtime-setup", "Sign-in required for this saved agent")

    view |> element("button", "Check authentication and start workflow") |> render_click()

    assert has_element?(view, "#run-error", "Sign in to Saved Codex")

    assert has_element?(
             view,
             "a[href='/settings/agents#agent-#{account_id}']",
             "Sign in to Saved Codex"
           )

    assert Repo.get!(Cuckoding.Adapters.ProviderAccount, account_id).status ==
             "authentication_required"

    event =
      Repo.one!(
        from event in RunEvent,
          where: event.run_id == ^("provider:" <> account_id),
          order_by: [desc: event.sequence],
          limit: 1
      )

    assert event.payload["status"] == "authentication_required"

    assert Repo.get!(Cuckoding.Execution.Run, run.id).state == "queued"
    assert File.dir?(environment.worktree_path)
  end

  defp assert_transition({:ok, %{result: %{"outcome" => "transitioned"}}}), do: :ok

  defp git!(repo_path, args) do
    assert {_output, 0} =
             System.cmd("/usr/bin/git", args,
               cd: repo_path,
               stderr_to_stdout: true,
               env: [{"LC_ALL", "C"}]
             )
  end
end
