defmodule Cuckoding.ProjectWorkflowTest do
  use CuckodingWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.RunEvent
  alias Cuckoding.ProjectOnboarding
  alias Cuckoding.ProjectWorkflow
  alias Cuckoding.Repo
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
                   "api_key_helper" => ""
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
    assert implementer["settings"]["connection_label"] == "Local Codex"

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
    assert has_element?(task_view, "p", "waiting for authentication")

    {:ok, dashboard, _html} = live(conn, ~p"/")
    assert has_element?(dashboard, "#operation-#{run.id}", "Ship monitored work")
    assert has_element?(dashboard, "#operation-#{run.id}", "Queued")
    assert has_element?(dashboard, "#operation-#{run.id}", "Waiting for launch")
    assert has_element?(dashboard, "#project-#{project.id}", "Tasks")
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

  test "Cursor roles prepare a queued run with run-owned authentication setup", %{
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

    for setup <- setups do
      assert setup.environment["HOME"] =~ "/agent/cursor/home"
      assert setup.environment["CURSOR_CONFIG_DIR"] =~ "/agent/cursor/config"
      assert setup.environment["CLAUDE_CONFIG_DIR"] =~ "/agent/cursor/claude"
    end
  end

  defp git!(repo_path, args) do
    assert {_output, 0} =
             System.cmd("/usr/bin/git", args,
               cd: repo_path,
               stderr_to_stdout: true,
               env: [{"LC_ALL", "C"}]
             )
  end
end
