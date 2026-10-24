# Source-only proof: real OTP/domain/Git/image/VM operations, synthetic provider replies.
# No production provider override and no account inference. Accept only a fresh driver fixture.
defmodule Cuckoding.GuestBattleFixture do
  import Bitwise

  alias Cuckoding.{
    ArenaGit,
    Arenas,
    BattleExecutor,
    BattleRunner,
    Battles,
    Codex,
    ExecutionSupervisor,
    Foundation,
    GuestChecks,
    LocalGit,
    Planning,
    PlanningDocuments,
    ProjectChecks,
    Repo,
    Storage,
    Tabulae,
    Team
  }

  def run do
    true = Mix.env() == :test
    Logger.configure(level: :warning)
    root = System.fetch_env!("CUCKODING_GUEST_FIXTURE_ROOT")
    mode = System.get_env("CUCKODING_GUEST_FIXTURE_MODE", "declared")
    true = mode in ~w(declared planned)
    planned? = mode == "planned"
    true = Path.expand(root) == root and Path.dirname(root) == "/private/tmp"

    true =
      String.starts_with?(
        Path.basename(root),
        if(planned?, do: "cuckoding-r050q-", else: "cuckoding-r050p-")
      )

    true = Enum.all?(components(root), &match?({:ok, %{type: :directory}}, File.lstat(&1)))
    true = band(File.stat!(root).mode, 0o777) == 0o700
    [".fixture-v1", "data"] = Enum.sort(File.ls!(root))
    marker = Path.join(root, ".fixture-v1")
    %{type: :regular, links: 1} = File.lstat!(marker)
    "guest-battle-fixture-v1\n" = File.read!(marker)
    data = Path.join(root, "data")
    ["shell.lock"] = File.ls!(data)
    Storage.prepare!(data)

    helper =
      Path.expand(
        "../../desktop/src-tauri/target/release/bundle/macos/Cuckoding.app/Contents/MacOS/ccoding",
        __DIR__
      )

    {:ok, _} = Codex.executable(helper)
    Application.put_env(:cuckoding, :data_dir, data)
    Application.put_env(:cuckoding, :native_helper, helper)
    Application.put_env(:cuckoding, :discovery_home, Path.join(root, "discovery-home"))
    Application.put_env(:cuckoding, :dispatcher, false)

    Application.put_env(:cuckoding, Repo,
      database: Path.join(data, "foundation.db"),
      pool: DBConnection.ConnectionPool,
      pool_size: 3,
      log: false,
      journal_mode: :wal,
      foreign_keys: :on
    )

    {:ok, _} = Application.ensure_all_started(:cuckoding)
    File.mkdir!(Path.join(data, "runtime-home"))
    File.chmod!(Path.join(data, "runtime-home"), 0o700)
    File.mkdir!(Path.join(root, "source"))
    File.chmod!(Path.join(root, "source"), 0o700)
    executable = Path.join(root, "synthetic-agent-not-a-provider")
    File.write!(executable, "#!/bin/sh\nexit 73\n", [:exclusive])
    File.chmod!(executable, 0o700)
    setup_agent(executable)
    arena = setup_arena(root)
    source_files = setup_git(arena, planned?)
    index = digest(File.read!(Path.join(arena.path, ".git/index")))
    [selected] = Tabulae.list(arena.id)
    board = Tabulae.get(arena.id, selected.id)

    if planned? do
      plan_tasks(board)
    else
      first = save_task(board, "Fixture A", [])
      save_task(board, "Fixture B", [first.id])
    end

    checks =
      Enum.map(~w(npm mix), fn tool ->
        %{
          "id" => Ecto.UUID.generate(),
          "name" => tool <> " tests",
          "executable" => tool,
          "arguments" => if(tool == "npm", do: ["test", "--offline"], else: ["test"]),
          "directory" => ".",
          "timeout_seconds" => 30
        }
      end)

    unless planned?,
      do: {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), arena.id, 0, checks, true)

    if planned?, do: 0 = ProjectChecks.current(arena.id).revision
    true = Process.register(self(), __MODULE__)

    {:ok, supervisor} =
      ExecutionSupervisor.start_link(
        coordinator: BattleRunner,
        tasks: Cuckoding.BattleTasks,
        options: [executor: &execute/1]
      )

    battle = start(board)

    {completed, responsive} =
      await(battle.id, false, System.monotonic_time(:millisecond) + 600_000, false)

    "completed" = completed.state
    true = responsive
    tasks = Battles.tasks(battle.id)
    true = Enum.all?(tasks, &(&1.state == "completed"))
    true = Enum.any?(tasks, &(&1.review_round == 1))
    attempts = Battles.attempts(battle.id)
    vm = Enum.filter(attempts, &(&1.stage in ~w(checks final_checks)))
    true = Enum.any?(vm, &(&1.result["status"] == "checks_failed"))
    true = Enum.all?(vm, &(&1.result["cleanup_verified"] == true))

    true =
      Enum.all?(vm, fn a -> Enum.all?(a.result["checks"], &GuestChecks.valid_check?(a, &1)) end)

    admission = Enum.find(attempts, &(&1.stage == "admission"))
    image = admission.result["check_image"]

    true =
      Enum.all?(source_files, fn {name, text} ->
        File.read!(Path.join(arena.path, name)) == text
      end)

    true = digest(File.read!(Path.join(arena.path, ".git/index"))) == index
    source = completed.snapshot["source"]

    observed =
      LocalGit.run(%{id: Ecto.UUID.generate(), payload: Map.put(source, "operation", "inspect")},
        active?: fn -> true end
      )

    true = observed["head"] == admission.result["head"]
    second = start(board)
    {paused, _} = await(second.id, true, System.monotonic_time(:millisecond) + 90_000, false)
    "paused" = paused.state
    0 = paused.turns_used
    true = paused.context["check_image"] == image
    [reuse] = Battles.attempts(second.id)
    "admission" = reuse.stage
    true = reuse.result["cleanup_verified"]
    {:ok, stopped} = Battles.stop(second.id)
    "stopped" = stopped.state
    true = File.ls!(Path.join(data, "runtime-home/check-images")) == [image["key"]]

    evidence = %{
      "format" => 1,
      "verification_mode" => mode,
      "configured_check_revision" => ProjectChecks.current(arena.id).revision,
      "inference" => false,
      "provider" => "synthetic source-only adapter",
      "battle_id" => completed.id,
      "state" => completed.state,
      "tasks" => length(tasks),
      "review_rounds" => Enum.map(tasks, & &1.review_round),
      "check_stages" =>
        Enum.map(vm, fn a ->
          %{
            "id" => a.id,
            "stage" => a.stage,
            "status" => a.result["status"],
            "checks" => a.result["checks"],
            "cleanup_verified" => a.result["cleanup_verified"]
          }
        end),
      "responsive_during_checks" => responsive,
      "image_key" => image["key"],
      "image_spec_sha256" => image["spec_sha256"],
      "second_start_reused_image" => true,
      "paused_after_admission" => true,
      "source_and_index_preserved" => true
    }

    File.write!(Path.join(root, "evidence.json"), Jason.encode!(evidence), [:exclusive])
    File.chmod!(Path.join(root, "evidence.json"), 0o600)
    Supervisor.stop(supervisor)
    :ok = Application.stop(:cuckoding)

    IO.puts(
      "PASS: one Start, dependent tasks, actual npm/Mix failure/correction/final checks, image reuse/Pause/Stop; synthetic providers only."
    )
  end

  def execute(attempt) do
    true = self() in Task.Supervisor.children(Cuckoding.BattleTasks)
    false = self() == Process.whereis(BattleRunner)
    send(__MODULE__, {:worker_started, attempt, self()})

    receive do
      {:proceed, id} when id == attempt.id -> :ok
    after
      5_000 -> raise "fixture observer missing"
    end

    result =
      BattleExecutor.execute(attempt,
        provider: Cuckoding.GuestBattleFixture.Provider,
        clock_check: &Cuckoding.BattleClock.check/0
      )

    send(__MODULE__, {:worker_finished, attempt.id, attempt.stage, result["status"]})
    result
  end

  defp start(board) do
    {:ok, preview} = Battles.preview(board.arena_id, board.id)
    [] = preview.blockers
    true = GuestChecks.enabled?(preview.snapshot)

    {:ok, battle} =
      Battles.start(Ecto.UUID.generate(), board.arena_id, board.id, preview.fingerprint, true)

    battle
  end

  defp await(id, pause?, deadline, responsive) do
    true = System.monotonic_time(:millisecond) < deadline
    battle = Battles.get(id)

    cond do
      battle.state in ~w(completed paused) ->
        {battle, responsive}

      battle.state == "needs_attention" ->
        raise "synthetic battle needs attention: #{battle.reason}"

      true ->
        receive do
          {:worker_started, attempt, pid} ->
            ^id = attempt.battle_id

            if pause? and attempt.stage == "admission",
              do: {:ok, _} = Battles.pause(id, battle.control_revision)

            send(pid, {:proceed, attempt.id})
            IO.puts(Jason.encode!(%{"stage_started" => attempt.stage}))

          {:worker_finished, _, stage, status} ->
            IO.puts(Jason.encode!(%{"stage_finished" => stage, "status" => status}))
        after
          100 -> :ok
        end

        state = :sys.get_state(BattleRunner, 1_000)

        checking =
          Enum.any?(state.jobs, fn {_, {_, attempt, _}} ->
            attempt.battle_id == id and attempt.stage in ~w(checks final_checks)
          end)

        await(id, pause?, deadline, responsive or checking)
    end
  end

  def digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  defp components(path), do: Path.split(path) |> Enum.scan(&Path.join(&2, &1))

  defp setup_agent(path) do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, path, true)
    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{"status" => "supported", "version" => Codex.isolation_version()})

    {:ok, _} =
      Foundation.inspect_codex(Ecto.UUID.generate(), Foundation.workspace().revision, true)

    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{
        "status" => "checked",
        "authorization" => "chatgpt",
        "catalog_status" => "fresh",
        "models" => [
          %{
            "id" => "fixture-id",
            "model" => "synthetic-model",
            "name" => "Synthetic fixture, no provider account",
            "efforts" => ["low"],
            "default_effort" => "low",
            "input_modalities" => ["text"],
            "default" => true
          }
        ]
      })

    connection = Foundation.workspace().connection

    {:ok, _} =
      Foundation.save_agent_models(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        connection["command_id"],
        ["fixture-id"]
      )

    team = Team.current()

    roles =
      Enum.map(
        Team.editable(team),
        &Map.merge(&1, %{"agent" => "codex", "model_id" => "fixture-id"})
      )

    {:ok, _} = Team.save(Ecto.UUID.generate(), team.id, roles)
  end

  defp setup_arena(root) do
    {:ok, _} = Arenas.choose(Ecto.UUID.generate())
    {:ok, claim} = Foundation.claim()

    {:ok, selected} =
      Foundation.finish(claim, %{"status" => "selected", "path" => Path.join(root, "source")})

    {:ok, arena} =
      Arenas.register(Ecto.UUID.generate(), selected.id, "SYNTHETIC guest battle", true)

    arena
  end

  defp setup_git(arena, planned?) do
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    observed = finish_git()
    "missing" = observed.result
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "init", observed.id, true)
    "initialized" = finish_git().result

    files = %{
      "a.txt" => "a base\n",
      "b.txt" => "b base\n",
      "package.json" =>
        ~s|{"private":true,"type":"module","scripts":{"test":"node --test test/check.test.js"}}| <>
          "\n",
      "test/check.test.js" =>
        "import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';\ntest('owned files',()=>{for(const c of ['a','b'])assert.ok([c+' base\\n',c+' result\\n'].includes(fs.readFileSync(c+'.txt','utf8')));});\n",
      "mix.exs" =>
        "defmodule Probe.MixProject do\n use Mix.Project\n def project, do: [app: :probe, version: \"0.1.0\", deps: []]\nend\n",
      "test/test_helper.exs" => "ExUnit.start()\n",
      "test/check_test.exs" =>
        "defmodule ProbeTest do\n use ExUnit.Case\n test \"owned files\" do\n for c <- [\"a\",\"b\"], do: assert File.read!(c <> \".txt\") in [c <> \" base\\n\",c <> \" result\\n\"]\n end\nend\n"
    }

    files =
      if planned? do
        files
        |> Enum.map(&planned_file/1)
        |> Map.new()
        |> Map.put(
          "docs/brief.md",
          "# Synthetic scope\nTask A changes a.txt and runs npm-test in frontend. Task B depends on A, changes b.txt and runs mix-test in backend. Keep all existing checks passing.\n"
        )
      else
        files
      end

    for {name, text} <- files do
      path = Path.join(arena.path, name)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, text, [:exclusive])
    end

    {:ok, _} = ArenaGit.preview(Ecto.UUID.generate(), arena.id, Enum.sort(Map.keys(files)))
    preview = finish_git()
    "previewed" = preview.result
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "commit", preview.id, true)
    "committed" = finish_git().result
    files
  end

  defp planned_file({name, text}) when name in ~w(package.json test/check.test.js),
    do:
      {"frontend/" <> name,
       String.replace(text, "fs.readFileSync(c+", "fs.readFileSync('../'+c+")}

  defp planned_file({name, text})
       when name in ~w(mix.exs test/test_helper.exs test/check_test.exs),
       do:
         {"backend/" <> name,
          String.replace(text, "File.read!(c <>", "File.read!(\"../\" <> c <>")}

  defp planned_file(file), do: file

  defp plan_tasks(board) do
    {:ok, preview} = PlanningDocuments.scan(Ecto.UUID.generate(), board.arena_id, board.id)
    {:ok, claim} = Foundation.claim()
    {:ok, %{state: "completed"}} = Foundation.finish(claim, PlanningDocuments.execute(claim))
    setup = Planning.setup(board, preview.id)
    "docs/brief.md" = hd(setup.payload["documents"])["path"]
    "brief-plan-v4" = setup.payload["contract"]

    {:ok, plan} =
      Planning.request(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        "Analyze the supplied specs and create both tasks with verification.",
        setup.token,
        true,
        preview.id
      )

    {:ok, claim} = Foundation.claim()

    tasks =
      for {title, dependencies, profile, directory} <- [
            {"Fixture A", [], "npm-test", "frontend"},
            {"Fixture B", [0], "mix-test", "backend"}
          ] do
        %{
          "title" => title,
          "description" => "Synthetic owned-file change only",
          "criteria" =>
            "Corresponding file has its result line and the selected offline test passes.",
          "depends_on" => dependencies,
          "sources" => [0],
          "verification" => [
            %{"profile" => profile, "directory" => directory, "timeout_seconds" => 30}
          ]
        }
      end

    receipt = %{
      "status" => "planned",
      "request_id" => plan.id,
      "grant" => "scratch-read-only-v1",
      "requested_model" => "synthetic-model",
      "observed_model" => "synthetic-model",
      "effort" => "low",
      "thread_id" => Ecto.UUID.generate(),
      "turn_id" => Ecto.UUID.generate(),
      "cleanup_verified" => true,
      "proposal" => %{"summary" => "SYNTHETIC planning reply; no inference.", "tasks" => tasks}
    }

    {:ok, %{state: "completed"}} = Foundation.finish(claim, receipt)
    [a, b] = Tabulae.tasks(board.id)
    a_id = a.id
    [^a_id] = b.depends_on
    true = Enum.all?([a, b], &(length(&1.verification) == 1))
  end

  defp finish_git do
    {:ok, claim} = Foundation.claim()
    {:ok, completed} = Foundation.finish(claim, ArenaGit.execute(claim))
    "completed" = completed.state
    completed
  end

  defp save_task(board, title, dependencies) do
    {:ok, _} =
      Tabulae.save(Ecto.UUID.generate(), board.arena_id, board.id, Ecto.UUID.generate(), 0, %{
        "title" => title,
        "description" => "Synthetic owned-file change only",
        "criteria" =>
          "Corresponding file has its result line and all offline npm/Mix checks pass.",
        "column" => "specs",
        "depends_on" => dependencies
      })

    Enum.find(Tabulae.tasks(board.id), &(&1.title == title))
  end
end

defmodule Cuckoding.GuestBattleFixture.Provider do
  alias Cuckoding.{ArenaGit, Repo}
  alias Cuckoding.GuestBattleFixture, as: Fixture

  def run_task(_, profile, scratch, request, active?) do
    true = active?.()
    [] = File.ls!(profile)
    [] = File.ls!(scratch)
    attempt = Repo.get!(Cuckoding.Battles.Attempt, request["request_id"])
    path = request["workspace"]["path"]
    true = path == ArenaGit.worktree_path(request["workspace"]["key"])
    %{type: :directory, major_device: device, inode: inode} = File.lstat!(path)
    true = device == request["workspace"]["device"] and inode == request["workspace"]["inode"]
    write? = request["access"] == "write"
    file = if attempt.request["task"]["title"] == "Fixture B", do: "b.txt", else: "a.txt"

    apply_change(path, file, attempt.request["review_round"], write?)

    files = if attempt.task_id, do: [file], else: ["a.txt", "b.txt"]

    tools =
      Enum.map(files, fn name ->
        %{
          "call_id" => Ecto.UUID.generate(),
          "tool" => if(write?, do: "edit_file", else: "read_file"),
          "status" => "completed",
          "path" => name,
          "sha256" => Fixture.digest(File.read!(Path.join(path, name)))
        }
      end)

    prompt = Jason.decode!(request["prompt"])
    failed = Enum.any?(prompt["host_checks"] || [], &(&1["status"] != "passed"))
    outcome = if attempt.stage == "secutor" and failed, do: "changes_requested", else: "completed"

    %{
      "status" => "task_finished",
      "request_id" => request["request_id"],
      "grant" => "host-task-tools-v1",
      "access" => request["access"],
      "requested_model" => request["model"],
      "observed_model" => request["model"],
      "effort" => request["effort"],
      "thread_id" => Ecto.UUID.generate(),
      "turn_id" => Ecto.UUID.generate(),
      "report" => %{
        "summary" =>
          "SYNTHETIC provider: inspect owned bytes and supplied native check evidence; no inference.",
        "outcome" => outcome
      },
      "tools" => tools,
      "changes" => if(write?, do: Enum.map(tools, &Map.take(&1, ~w(path sha256))), else: []),
      "cleanup_verified" => true
    }
  end

  defp apply_change(_, _, _, false), do: :ok

  defp apply_change(path, "a.txt", 0, true),
    do: File.write!(Path.join(path, "a.txt"), "a wrong\n")

  defp apply_change(path, file, _, true),
    do: File.write!(Path.join(path, file), String.first(file) <> " result\n")
end

Cuckoding.GuestBattleFixture.run()
