defmodule AgentDesk.Providers.LifecycleAcceptanceTest do
  use AgentDesk.DataCase

  alias AgentDesk.Agents
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects
  alias AgentDesk.Providers
  alias AgentDesk.Providers.Cursor
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Providers.Transcript
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Security.Capability
  alias AgentDesk.Storage
  alias AgentDesk.Worktrees

  setup do
    repo = GitRepo.tmp_repo!("agentdesk-provider-acceptance")
    {:ok, project} = Projects.open_project(repo)
    %{project: project, scope: Scope.for_project(project)}
  end

  test "provider OS exit stops and unregisters its worker", %{
    scope: scope
  } do
    {executable, _trace} = cursor_peer!("exit-once")
    assert {:ok, ^executable, ["acp"]} = Cursor.resolve(executable: executable)

    assert {:ok, session} =
             Providers.start_session(
               scope,
               %{provider: "cursor", display_name: "Exit then resume"},
               fixture: false,
               executable: executable
             )

    assert wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)
    assert {:ok, worker} = SessionWorker.fetch(session.id)
    monitor = Process.monitor(worker)
    assert :ok = SessionWorker.prompt(session.id, "exit now")

    assert_receive {:DOWN, ^monitor, :process, ^worker, _reason}, 2_000
    assert {:error, :not_started} = SessionWorker.fetch(session.id)

    failed = Repo.get!(Agents.Session, session.id)
    assert failed.status == "failed"
  end

  test "termination force-kills the provider process group and descendants", %{scope: scope} do
    {executable, child_pid_path} = stubborn_cursor_peer!()

    assert {:ok, session} =
             Providers.start_session(
               scope,
               %{provider: "cursor", display_name: "Stubborn descendants"},
               fixture: false,
               executable: executable
             )

    assert wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)
    assert wait_until(fn -> File.exists?(child_pid_path) end)
    child_pid = child_pid_path |> File.read!() |> String.trim() |> String.to_integer()
    identity = Repo.get!(Agents.Session, session.id).process_identity
    assert is_integer(identity["process_group_id"])
    assert :ok = SessionWorker.terminate_session(session.id)
    assert wait_until(fn -> SessionWorker.fetch(session.id) == {:error, :not_started} end)
    assert wait_until(fn -> !os_process_alive?(child_pid) end)
  end

  test "cursor resume uses session/load with the prior provider session id", %{scope: scope} do
    {executable, trace} = cursor_peer!("resume-load")

    assert {:ok, session} =
             Providers.start_session(
               scope,
               %{provider: "cursor", display_name: "Resume load"},
               fixture: false,
               executable: executable
             )

    assert initial =
             wait_until(fn ->
               persisted = Repo.get!(Agents.Session, session.id)
               persisted.provider_session_id && persisted
             end)

    assert wait_until(fn -> traced_method?(trace, "session/prompt") end)
    prior_provider_session_id = initial.provider_session_id
    assert :ok = Providers.stop_worker(session.id)
    assert wait_until(fn -> SessionWorker.fetch(session.id) == {:error, :not_started} end)
    persisted = Repo.get!(Agents.Session, session.id)

    assert {:ok, resumed_worker} =
             Providers.resume_session(persisted,
               fixture: false,
               executable: executable
             )

    assert wait_until(fn ->
             traced_request?(trace, "session/load", %{
               "sessionId" => prior_provider_session_id
             })
           end)

    assert wait_until(fn ->
             resumed = Repo.get!(Agents.Session, session.id)

             resumed.status == "idle" &&
               resumed.provider_session_id == prior_provider_session_id
           end)

    assert {:ok, ^resumed_worker} = SessionWorker.fetch(session.id)
  end

  test "failed provider start compensates session, worktree, capability, and port resources", %{
    project: project,
    scope: scope
  } do
    missing =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-missing-cursor-#{System.unique_integer([:positive])}"
      )

    refute File.exists?(missing)
    assert {:ok, ^missing, ["acp"]} = Cursor.resolve(executable: missing)
    before = resource_snapshot(project)

    assert {:error, _reason} =
             Providers.start_session(
               scope,
               %{provider: "cursor", display_name: "Must compensate"},
               fixture: false,
               executable: missing
             )

    assert resource_snapshot(project) == before
  end

  test "post-provision failure preserves edits and records incomplete cleanup", %{
    project: project,
    scope: scope
  } do
    GitRepo.add_file!(
      project.canonical_path,
      "compose.yaml",
      "services:\n  db:\n    image: postgres:16\n"
    )

    GitRepo.add_file!(project.canonical_path, ".agentdesk-compose-fixture-edit", "write\n")
    {:ok, runtime} = AgentDesk.Projects.Runtime.fetch(project.id)
    :ok = Supervisor.terminate_child(runtime, AgentDesk.Providers.ProjectSupervisor)

    on_exit(fn ->
      case Supervisor.restart_child(runtime, AgentDesk.Providers.ProjectSupervisor) do
        {:ok, _pid} -> :ok
        {:ok, _pid, _info} -> :ok
        {:error, :running} -> :ok
        {:error, _reason} -> :ok
      end
    end)

    assert {:error, {:start_failed, :not_started, {:cleanup_incomplete, cleanup_failures}}} =
             Providers.start_session(scope, %{
               provider: "fake",
               display_name: "Preserve failed start",
               settings: %{"container" => true}
             })

    assert {:worktree_cleanup, :dirty_after_process_start} in cleanup_failures
    [failed] = Agents.list_sessions(project.id)
    assert failed.status == "failed"
    assert failed.exit_reason =~ "worktree_cleanup"
    worktree = Worktrees.get_for_session(failed.id)
    assert File.read!(Path.join(worktree.path, "compose-created.txt")) =~ "compose fixture"
    assert Manager.list_owned(failed.id) == []
    assert DateTime.compare(failed.capability_expires_at, AgentDesk.Clock.utc_now()) != :gt
  end

  test "resume reprovisions released port and Compose resources", %{
    project: project,
    scope: scope
  } do
    GitRepo.add_file!(
      project.canonical_path,
      "compose.yaml",
      "services:\n  db:\n    image: postgres:16\n"
    )

    assert {:ok, session} =
             Providers.start_session(scope, %{
               provider: "fake",
               display_name: "Reprovision",
               settings: %{"container" => true}
             })

    assert wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)
    assert :ok = Providers.stop_worker(session.id)
    assert Manager.list_owned(session.id) == []
    refute File.exists?(Path.join(Storage.session_dir(project.id, session.id), "mcp.json"))

    persisted = Repo.get!(Agents.Session, session.id)
    assert {:ok, _pid} = Providers.resume_session(persisted)

    assert wait_until(fn ->
             resumed = Repo.get!(Agents.Session, session.id)
             path = Path.join(Storage.session_dir(project.id, session.id), "mcp.json")

             with true <- resumed.status in ["starting", "idle", "working"],
                  {:ok, body} <- File.read(path),
                  {:ok, config} <- Jason.decode(body),
                  token when is_binary(token) <-
                    get_in(config, [
                      "mcpServers",
                      "agentdesk-hub",
                      "env",
                      "AGENTDESK_CAPABILITY_TOKEN"
                    ]),
                  {:ok, authenticated} <- Capability.authenticate(token) do
               authenticated.id == session.id
             else
               _ -> false
             end
           end)

    leases = Manager.list_owned(session.id)
    assert Enum.any?(leases, &(&1.resource_type == "port"))
    assert Enum.any?(leases, &(&1.resource_type == "service"))
    assert Jason.decode!(File.read!(AgentDesk.Containers.record_path(session)))["action"] == "up"
  end

  test "non-resumable adapters reject provider-session resume", %{scope: scope} do
    assert {:ok, session} =
             Providers.start_session(scope, %{provider: "sdk", display_name: "No resume"})

    assert wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)
    assert :ok = Providers.stop_worker(session.id)
    persisted = Repo.get!(Agents.Session, session.id)
    assert {:error, :resume_unsupported} = Providers.resume_session(persisted)
    assert Repo.get!(Agents.Session, session.id).status == "failed"
  end

  test "ACP stderr stays diagnostic while unexpected OS exit is normalized", %{scope: scope} do
    {executable, _trace} = cursor_peer!("stderr-and-exit")

    assert {:ok, session} =
             Providers.start_session(
               scope,
               %{provider: "cursor", display_name: "Diagnostics"},
               fixture: false,
               executable: executable
             )

    assert wait_until(fn -> Repo.get!(Agents.Session, session.id).provider_session_id end)
    assert :ok = SessionWorker.prompt(session.id, "exit now")

    assert evidence =
             wait_until(fn ->
               evidence =
                 session.project_id
                 |> Transcript.read(session.id)
                 |> Enum.reduce(%{stderr: false, exit: false}, fn
                   %{"type" => "stderr", "payload" => %{"text" => text}}, acc ->
                     %{acc | stderr: String.contains?(text, "cursor fixture diagnostic")}

                   %{"type" => "provider_error", "payload" => %{"exit" => 23}}, acc ->
                     %{acc | exit: true}

                   _event, acc ->
                     acc
                 end)

               evidence == %{stderr: true, exit: true} && evidence
             end)

    assert evidence == %{stderr: true, exit: true}
  end

  test "ACP fake peer completes auth, fs read, permission, and cancel round trips", %{
    scope: scope
  } do
    {executable, trace} = cursor_contract_peer!()

    assert {:ok, session} =
             Providers.start_session(
               scope,
               %{provider: "cursor", display_name: "ACP contract"},
               fixture: false,
               executable: executable
             )

    assert wait_until(fn -> traced_method?(trace, "authenticate") end)
    assert wait_until(fn -> traced_result?(trace, "fixture\n") end)

    assert wait_until(fn ->
             Transcript.read(session.project_id, session.id)
             |> Enum.any?(&(&1["type"] == "approval_requested"))
           end)

    assert :ok = SessionWorker.approve(session.id, "9001", "allow")
    assert wait_until(fn -> traced_outcome?(trace, "selected") end)

    assert :ok = SessionWorker.interrupt(session.id)
    assert wait_until(fn -> traced_method?(trace, "session/cancel") end)
    assert wait_until(fn -> Repo.get!(Agents.Session, session.id).status == "failed" end)
  end

  defp resource_snapshot(project) do
    %{
      sessions: Enum.map(Agents.list_sessions(project.id), & &1.id),
      worktrees: Enum.map(Worktrees.list_project(project.id), & &1.id),
      leases: Enum.map(Manager.list_project(project.id), & &1.id),
      session_files: entries(Path.join(Storage.project_dir(project.id), "sessions")),
      worktree_files: entries(Path.join(Storage.project_dir(project.id), "worktrees"))
    }
  end

  defp entries(path) do
    case File.ls(path) do
      {:ok, entries} -> Enum.sort(entries)
      {:error, :enoent} -> []
    end
  end

  defp cursor_peer!(name) do
    dir = owned_tmp_dir!("cursor-peer-#{name}")
    executable = Path.join(dir, "cursor-agent")
    trace = executable <> ".trace"

    File.write!(executable, """
    #!/bin/sh
    trace="$0.trace"
    first=0
    if [ ! -e "$0.resumed" ]; then
      : > "$0.resumed"
      first=1
    fi

    IFS= read -r initialize || exit 10
    printf '%s\n' "$initialize" >> "$trace"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"serverInfo":{"name":"cursor-fixture"}}}'
    IFS= read -r session || exit 11
    printf '%s\n' "$session" >> "$trace"
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"sessionId":"cursor-exit-session"}}'

    if [ "$first" -eq 1 ]; then
      IFS= read -r role_prompt || exit 12
      printf '%s\n' "$role_prompt" >> "$trace"
      printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}'
      IFS= read -r exit_prompt || exit 13
      printf '%s\n' "$exit_prompt" >> "$trace"
      printf '%s\n' 'cursor fixture diagnostic' >&2
      exit 23
    fi

    while IFS= read -r line; do
      case "$line" in
        *session/cancel*)
          printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{}}'
          ;;
      esac
    done
    """)

    File.chmod!(executable, 0o755)
    {executable, trace}
  end

  defp cursor_contract_peer! do
    dir = owned_tmp_dir!("cursor-contract-peer")
    executable = Path.join(dir, "cursor-agent")
    trace = executable <> ".trace"

    File.write!(executable, """
    #!/bin/sh
    trace="$0.trace"

    IFS= read -r initialize || exit 10
    printf '%s\n' "$initialize" >> "$trace"
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1,"authMethods":[{"id":"cursor-login"}]}}'

    IFS= read -r authenticate || exit 11
    printf '%s\n' "$authenticate" >> "$trace"
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"authenticated":true}}'

    IFS= read -r session || exit 12
    printf '%s\n' "$session" >> "$trace"
    printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"sessionId":"cursor-contract-session"}}'

    IFS= read -r role_prompt || exit 13
    printf '%s\n' "$role_prompt" >> "$trace"
    printf '%s\n' '{"jsonrpc":"2.0","id":4,"result":{"stopReason":"end_turn"}}'

    printf '{"jsonrpc":"2.0","id":9002,"method":"fs/read_text_file","params":{"path":"%s/README.md","line":1,"limit":20}}\n' "$PWD"
    IFS= read -r fs_response || exit 14
    printf '%s\n' "$fs_response" >> "$trace"

    printf '%s\n' '{"jsonrpc":"2.0","id":9001,"method":"session/request_permission","params":{"toolCall":{"title":"Read README","kind":"read"}}}'
    IFS= read -r permission_response || exit 15
    printf '%s\n' "$permission_response" >> "$trace"

    IFS= read -r cancel || exit 16
    printf '%s\n' "$cancel" >> "$trace"
    printf '%s\n' '{"jsonrpc":"2.0","id":5,"result":{}}'
    exit 23
    """)

    File.chmod!(executable, 0o755)
    {executable, trace}
  end

  defp stubborn_cursor_peer! do
    dir = owned_tmp_dir!("cursor-stubborn-peer")
    executable = Path.join(dir, "cursor-agent")
    child_pid_path = executable <> ".child"

    File.write!(executable, """
    #!/bin/sh
    trap '' TERM INT
    sleep 30 &
    child=$!
    printf '%s\n' "$child" > "$0.child"

    IFS= read -r initialize || exit 10
    printf '%s\n' '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":1}}'
    IFS= read -r session || exit 11
    printf '%s\n' '{"jsonrpc":"2.0","id":2,"result":{"sessionId":"cursor-stubborn-session"}}'
    IFS= read -r role_prompt || exit 12
    printf '%s\n' '{"jsonrpc":"2.0","id":3,"result":{"stopReason":"end_turn"}}'

    while IFS= read -r _line; do
      :
    done
    """)

    File.chmod!(executable, 0o755)
    {executable, child_pid_path}
  end

  defp traced_method?(path, method) do
    Enum.any?(trace_frames(path), &(&1["method"] == method))
  end

  defp traced_result?(path, content) do
    Enum.any?(trace_frames(path), &(get_in(&1, ["result", "content"]) == content))
  end

  defp traced_outcome?(path, outcome) do
    Enum.any?(
      trace_frames(path),
      &(get_in(&1, ["result", "outcome", "outcome"]) == outcome)
    )
  end

  defp traced_request?(path, method, params) do
    Enum.any?(trace_frames(path), fn frame ->
      frame["method"] == method && Map.take(frame["params"] || %{}, Map.keys(params)) == params
    end)
  end

  defp trace_frames(path) do
    case File.read(path) do
      {:ok, body} ->
        body
        |> String.split("\n", trim: true)
        |> Enum.map(&Jason.decode!/1)

      {:error, :enoent} ->
        []
    end
  end

  defp os_process_alive?(pid) do
    case System.find_executable("kill") do
      nil ->
        false

      kill ->
        match?(
          {_output, 0},
          System.cmd(kill, ["-0", Integer.to_string(pid)], stderr_to_stdout: true)
        )
    end
  end

  defp owned_tmp_dir!(name) do
    dir =
      Path.join(
        System.tmp_dir!(),
        "agentdesk-#{name}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(dir)

    on_exit(fn ->
      File.rm_rf!(dir)
      refute File.exists?(dir)
    end)

    dir
  end
end
