defmodule Cuckoding.BoardControl.GoalChecks do
  @moduledoc "Host-run checks from the commands explicitly authorized by Run."
  import Ecto.Query
  alias Cuckoding.{BoardControl, Repo, RunControl}
  alias Cuckoding.BoardControl.{Budget, Plans}

  alias Cuckoding.Execution.{
    CommandPolicy,
    EventStore,
    GitService,
    LocalProcessRunner,
    RunEvent,
    Toolchain
  }

  @doc "Validate the proposed command list and freeze resolved executable paths."
  def prepare(commands) when is_list(commands) and length(commands) in 1..10 do
    with true <- Enum.all?(commands, &valid_declaration?/1),
         names = Enum.map(commands, & &1["name"]),
         true <- Enum.uniq(names) == names,
         true <- Enum.any?(commands, &(&1["phase"] == "check")),
         {:ok, commands} <- resolve_tools(commands),
         config = %{
           "schema_version" => 2,
           "repository" => %{"protected_paths" => []},
           "commands" => Map.new(commands, &{&1["name"], &1["command"]})
         },
         :ok <- CommandPolicy.validate(config) do
      {:ok,
       Enum.map(commands, fn declaration ->
         {:ok, command} = CommandPolicy.resolve_config(config, declaration["name"])
         Map.put(declaration, "command", [command.executable | command.args])
       end)}
    else
      _ -> {:error, :invalid_goal_commands}
    end
  end

  def prepare(_), do: {:error, :invalid_goal_commands}

  defp resolve_tools(commands) do
    catalog = Toolchain.catalog()

    Enum.reduce_while(commands, {:ok, []}, fn declaration, {:ok, resolved} ->
      [program | args] = declaration["command"]

      case Toolchain.resolve(program, catalog) do
        {:ok, path} ->
          {:cont, {:ok, resolved ++ [Map.put(declaration, "command", [path | args])]}}

        error ->
          {:halt, error}
      end
    end)
  end

  defp valid_declaration?(%{"name" => name, "phase" => phase, "command" => argv} = command)
       when is_binary(name) and is_list(argv) do
    Enum.sort(Map.keys(command)) == ~w(command name phase) and
      Regex.match?(~r/\A[a-z][a-z0-9_]{0,39}\z/, name) and phase in ~w(setup check) and
      length(argv) in 1..32 and
      Enum.all?(argv, &(is_binary(&1) and byte_size(&1) in 1..500)) and
      supported_command?(argv, phase)
  end

  defp valid_declaration?(_), do: false

  # Run authorizes repository build/test code, never an inline shell or interpreter program.
  defp supported_command?([program | args], phase) do
    supported?(Path.basename(program), phase, args) and
      not Enum.any?(args, &(&1 in ~w(-e -c --eval --exec --global -g)))
  end

  defp supported?("mix", "setup", [command | _]), do: command in ~w(deps.get deps.compile)

  defp supported?(tool, "setup", [command | _]) when tool in ~w(npm pnpm yarn bun),
    do: command in ~w(ci install)

  defp supported?("bundle", "setup", ["install" | _]), do: true
  defp supported?("cargo", "setup", ["fetch" | _]), do: true
  defp supported?("uv", "setup", ["sync" | _]), do: true

  defp supported?("mix", "check", [command | _]),
    do: command in ~w(test compile format credo sobelow quality)

  defp supported?(tool, "check", [command | _]) when tool in ~w(npm pnpm yarn bun),
    do: command in ~w(test run build typecheck lint)

  defp supported?("cargo", "check", [command | _]), do: command in ~w(test check clippy fmt build)
  defp supported?("bundle", "check", ["exec", tool | _]), do: tool in ~w(rspec rake rubocop)
  defp supported?("node", "check", ["--test" | _]), do: true

  defp supported?(tool, "check", ["-m", module | _]) when tool in ~w(python python3),
    do: module in ~w(pytest unittest)

  defp supported?("git", "check", ["diff", "--check"]), do: true
  defp supported?(_, _, _), do: false

  def declarations(e),
    do: get_in(e.delivery_authorization_json || %{}, ["snapshot", "commands"]) || []

  def context(run) do
    e = run.board_execution_id && BoardControl.get(run.board_execution_id)

    if e && Plans.prepared_goal?(e) && e.delivery_authorization_json do
      item = Enum.find(BoardControl.items(e.id), &(&1.task_id == run.task_id))

      %{
        "authorization_digest" => e.delivery_authorization_json["digest"],
        "goal" => Plans.goal(e),
        "task_criteria" => (item && item.criteria_json["ids"]) || [],
        "commands" => declarations(e)
      }
    end
  end

  @doc "Run the authorized setup/checks in the final review worktree, recording host evidence."
  def run(skeleton, %{"phase" => "plan_review", "preparing" => true} = input) do
    with {:ok, commands} <- prepare(input["plan"]["proposal"]["commands"]),
         {:ok, toolchain} <- Toolchain.snapshot(commands),
         {:ok, checks} <- probe_tools(skeleton, toolchain),
         payload = %{
           "plan_id" => input["plan"]["id"],
           "commands_digest" => digest(input["plan"]["proposal"]["commands"]),
           "commands" => commands,
           "toolchain" => toolchain,
           "checks" => checks
         },
         {:ok, _} <-
           EventStore.append(skeleton.run.id, %{
             event_type: "goal.toolchain_verified",
             public_summary: "Developer tools verified in the restricted run environment",
             payload: payload
           }) do
      {:ok, Map.put(input, "toolchain", payload)}
    end
  end

  def run(skeleton, input) do
    if input["phase"] == "final_review" do
      e = BoardControl.get(skeleton.run.board_execution_id)

      with :ok <- Budget.check(e),
           {:ok, head} <- initial_candidate(skeleton, e),
           {:ok, results} <- execute_all(skeleton, e),
           :ok <- protected_paths(skeleton),
           {:ok, %{clean?: clean, head_sha: ^head}} <- GitService.inspect(skeleton.environment),
           {:ok, paths} <- Cuckoding.Execution.ProtectedPaths.changed_paths(skeleton.environment) do
        {:ok,
         Map.merge(input, %{
           "checks" => results,
           "candidate_clean" => clean,
           "changed_paths" => paths
         })}
      else
        false -> {:error, :goal_candidate_changed}
        {:ok, _} -> {:error, :goal_checks_changed_candidate}
        error -> error
      end
    else
      {:ok, input}
    end
  end

  defp probe_tools(skeleton, toolchain) do
    Enum.reduce_while(toolchain["tools"], {:ok, []}, fn tool, {:ok, checks} ->
      with {:ok, handle} <- launch_probe(skeleton, toolchain, tool),
           {:ok, %{exit_status: 0, timed_out?: false} = result} <-
             Cuckoding.Execution.LocalProcessWorker.await(handle.worker) do
        {:cont,
         {:ok,
          checks ++
            [
              %{
                "name" => tool["name"],
                "process_id" => result.process.id,
                "path" => Path.basename(result.artifact_path),
                "sha256" => result.artifact_sha256
              }
            ]}}
      else
        {:error, _} = error -> {:halt, error}
        _ -> {:halt, {:error, :goal_toolchain_unavailable}}
      end
    end)
  end

  defp launch_probe(skeleton, toolchain, tool) do
    command = %{
      executable: tool["path"],
      args: Toolchain.version_args(tool["name"]),
      role: "tool_version:#{tool["name"]}"
    }

    RunControl.launch(skeleton.run.id, fn ->
      LocalProcessRunner.start(skeleton.environment, command,
        env: Toolchain.environment(toolchain),
        timeout: Budget.timeout(skeleton.run, 15_000)
      )
    end)
  end

  def verified_toolchain(plan) do
    payload =
      Repo.one(
        from event in RunEvent,
          where:
            event.run_id == ^plan.review_run_id and event.event_type == "goal.toolchain_verified",
          order_by: [desc: event.sequence],
          limit: 1,
          select: event.payload
      )

    env = Repo.get_by(Cuckoding.Execution.Environment, run_id: plan.review_run_id)

    if payload && env && payload["plan_id"] == plan.id &&
         payload["commands_digest"] == digest(plan.plan_json["commands"]) &&
         Toolchain.current?(payload["toolchain"]) &&
         Enum.all?(payload["checks"], &safe_artifact?(&1, env)),
       do: {:ok, Map.take(payload, ~w(commands toolchain))},
       else: {:error, :goal_toolchain_unavailable}
  end

  def environment(run_id) do
    run = Repo.get(Cuckoding.Execution.Run, run_id)
    e = run && run.board_execution_id && BoardControl.get(run.board_execution_id)

    get_in((e && e.delivery_authorization_json) || %{}, ["snapshot", "toolchain"])
    |> Toolchain.environment()
  end

  def toolchain_current?(e) do
    case get_in(e.delivery_authorization_json || %{}, ["snapshot", "toolchain"]) do
      nil -> true
      toolchain -> Toolchain.current?(toolchain)
    end
  end

  defp initial_candidate(skeleton, e) do
    with {:ok, %{head_sha: head, clean?: clean}} <- GitService.inspect(skeleton.environment),
         true <- head == e.head_sha do
      checks =
        Enum.map(
          declarations(e),
          &receipt(skeleton.run.id, "goal-check:#{skeleton.run.id}:#{&1["name"]}")
        )

      # A resumed Reviewer may inspect files changed by completed checks. Dirty work
      # still fails final acceptance; never replay setup against an unknown partial result.
      if clean or verify(e, skeleton.run, checks) == :ok,
        do: {:ok, head},
        else: {:error, :goal_checks_changed_candidate}
    else
      _ -> {:error, :goal_candidate_changed}
    end
  end

  defp execute_all(skeleton, e) do
    commands = Enum.sort_by(declarations(e), &if(&1["phase"] == "setup", do: 0, else: 1))

    Enum.reduce_while(commands, {:ok, []}, fn command, {:ok, results} ->
      case execute(skeleton, e, command) do
        {:ok, result} -> {:cont, {:ok, results ++ [result]}}
        error -> {:halt, error}
      end
    end)
  end

  defp execute(skeleton, e, declaration) do
    key = "goal-check:#{skeleton.run.id}:#{declaration["name"]}"

    case receipt(skeleton.run.id, key) do
      nil -> start_check(skeleton, e, declaration, key)
      %{"event" => "completed"} = stored -> {:ok, stored}
      _ -> {:error, :goal_check_outcome_unknown}
    end
  end

  defp start_check(skeleton, e, declaration, key) do
    [executable | args] = declaration["command"]
    command = %{executable: executable, args: args, role: "goal_check:#{declaration["name"]}"}

    payload = %{
      "command_key" => key,
      "name" => declaration["name"],
      "phase" => declaration["phase"],
      "command_digest" => digest(declaration),
      "head_sha" => e.head_sha,
      "authorization_digest" => e.delivery_authorization_json["digest"]
    }

    with :ok <- RunControl.await_running(skeleton.run.id),
         :ok <- BoardControl.launch_authorized(skeleton.run),
         {:ok, _} <- record(skeleton.run.id, payload, "started"),
         {:ok, handle} <-
           RunControl.launch(skeleton.run.id, fn -> launch_check(skeleton, command) end),
         {:ok, %{exit_status: status} = result} <-
           Cuckoding.Execution.LocalProcessWorker.await(handle.worker),
         receipt =
           Map.merge(payload, %{
             "event" => "completed",
             "process_id" => result.process.id,
             "exit_status" => status,
             "timed_out" => result.timed_out?,
             "path" => Path.basename(result.artifact_path),
             "sha256" => result.artifact_sha256
           }),
         {:ok, _} <- record(skeleton.run.id, receipt, "completed"),
         :ok <- protected_paths(skeleton) do
      {:ok, receipt}
    end
  end

  defp launch_check(skeleton, command) do
    Cuckoding.Plugins.RTK.filter_command(
      skeleton.run,
      skeleton.environment,
      command,
      :start,
      [],
      fn ->
        LocalProcessRunner.start(skeleton.environment, command,
          timeout: Budget.timeout(skeleton.run, 300_000)
        )
      end
    )
  end

  defp protected_paths(skeleton) do
    policy = Repo.get!(Cuckoding.Projects.ProjectConfigVersion, skeleton.run.policy_snapshot_id)
    paths = get_in(policy.config_json, ["repository", "protected_paths"]) || []

    case Cuckoding.Execution.ProtectedPaths.scan(skeleton.environment, paths) do
      {:ok, []} -> :ok
      {:ok, _} -> {:error, :protected_path_approval_required}
      error -> error
    end
  end

  def candidate(e, run) do
    env = Repo.get_by!(Cuckoding.Execution.Environment, run_id: run.id)

    with {:ok, %{head_sha: head, clean?: clean}} <- GitService.inspect(env),
         true <- head == e.head_sha do
      {:ok, clean}
    else
      _ -> {:error, :goal_candidate_changed}
    end
  end

  defp record(run_id, payload, event) do
    EventStore.append(run_id, %{
      event_type: "goal.check_#{event}",
      public_summary: "Goal command #{event}: #{payload["name"]}",
      payload: Map.put(payload, "event", event)
    })
  end

  defp receipt(run_id, key) do
    Repo.all(
      from event in RunEvent,
        where:
          event.run_id == ^run_id and
            event.event_type in ["goal.check_started", "goal.check_completed"],
        order_by: [desc: event.sequence],
        select: event.payload
    )
    |> Enum.find(&(&1["command_key"] == key))
    |> then(fn value -> if value, do: Map.delete(value, "correlation") end)
  end

  @doc "Verify that the supplied results are host records for every authorized command and this head."
  def verify(e, run, checks) when is_list(checks) do
    environment = Repo.get_by!(Cuckoding.Execution.Environment, run_id: run.id)
    commands = declarations(e)

    valid = Enum.all?(commands, &verified_command?(&1, e, run, checks, environment))

    if length(checks) == length(commands) and commands != [] and valid,
      do: :ok,
      else: {:error, :invalid_goal_check_evidence}
  end

  def verify(_e, _run, _checks), do: {:error, :invalid_goal_check_evidence}

  defp verified_command?(command, e, run, checks, environment) do
    stored = receipt(run.id, "goal-check:#{run.id}:#{command["name"]}")
    stored in checks and valid_receipt?(stored, command, e, environment)
  end

  defp digest(command),
    do: :crypto.hash(:sha256, Jason.encode!(command)) |> Base.encode16(case: :lower)

  defp valid_receipt?(%{"event" => "completed"} = receipt, command, e, environment) do
    receipt["command_digest"] == digest(command) and receipt["head_sha"] == e.head_sha and
      receipt["authorization_digest"] == e.delivery_authorization_json["digest"] and
      safe_artifact?(receipt, environment)
  end

  defp valid_receipt?(_, _, _, _), do: false

  defp safe_artifact?(receipt, environment) do
    name = receipt["path"]

    with true <- is_binary(name) and Path.basename(name) == name,
         path = Path.join([environment.run_dir, "artifacts", name]),
         {:ok, %{type: :regular}} <- File.lstat(path),
         {:ok, contents} <- File.read(path) do
      Base.encode16(:crypto.hash(:sha256, contents), case: :lower) == receipt["sha256"]
    else
      _ -> false
    end
  end

  def passed?(checks),
    do: checks != [] and Enum.all?(checks, &(&1["exit_status"] == 0 and &1["timed_out"] == false))
end
