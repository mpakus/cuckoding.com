# Developer-only synthetic input builder; no production provider or grant override.
defmodule Cuckoding.PackagedRecoveryFixture do
  import Bitwise

  alias Cuckoding.{
    ArenaGit,
    Arenas,
    BattleExecutor,
    Battles,
    Codex,
    Foundation,
    Repo,
    Storage,
    Tabulae,
    Team
  }

  def run do
    true = Mix.env() == :test
    Logger.configure(level: :warning)
    root = System.fetch_env!("CUCKODING_PACKAGED_FIXTURE_ROOT")
    true = Path.expand(root) == root and Path.dirname(root) == "/private/tmp"
    true = String.starts_with?(Path.basename(root), "cuckoding-packaged-recovery-")
    true = Enum.all?(components(root), &match?({:ok, %{type: :directory}}, File.lstat(&1)))
    true = band(File.stat!(root).mode, 0o777) == 0o700
    true = Enum.sort(File.ls!(root)) == [".fixture-v1", "data"]
    marker = Path.join(root, ".fixture-v1")
    %{type: :regular, links: 1, size: 29} = File.lstat!(marker)
    true = File.read!(marker) == "packaged-recovery-fixture-v1\n"
    data = Path.join(root, "data")
    true = File.ls!(data) == ["shell.lock"]
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
      pool_size: 1,
      log: false,
      journal_mode: :wal,
      foreign_keys: :on
    )

    {:ok, _} = Application.ensure_all_started(:cuckoding)
    File.mkdir!(Path.join(data, "runtime-home"))
    File.chmod!(Path.join(data, "runtime-home"), 0o700)
    {:ok, tasks} = Task.Supervisor.start_link()
    File.mkdir!(Path.join(root, "source"))
    File.chmod!(Path.join(root, "source"), 0o700)
    executable = Path.join(root, "synthetic-agent-not-a-provider")
    File.write!(executable, "#!/bin/sh\nexit 73\n", [:exclusive])
    File.chmod!(executable, 0o700)
    setup_agent(executable)
    arena = setup_arena(root)
    setup_git(arena)
    [selected] = Tabulae.list(arena.id)
    board = Tabulae.get(arena.id, selected.id)
    for title <- ["Fixture A", "Fixture B"], do: save_task(board, title)
    {:ok, preview} = Battles.preview(arena.id, board.id)
    [] = preview.blockers

    {:ok, battle} =
      Battles.start(Ecto.UUID.generate(), arena.id, board.id, preview.fingerprint, true)

    {attempt, receipt} = stage_until_combined(battle, tasks, 60)
    "combined" = receipt["status"]
    current = Battles.get(battle.id)
    true = Repo.get!(Cuckoding.Battles.Attempt, attempt.id).state == "running"
    true = Enum.count(Battles.attempts(battle.id), &(&1.state == "running")) == 1
    true = File.read!(Path.join(arena.path, "a.txt")) == "a base\n"
    true = File.read!(Path.join(arena.path, "b.txt")) == "b base\n"

    expected = %{
      "format" => 1,
      "synthetic_provider" => true,
      "battle_id" => battle.id,
      "attempt_id" => attempt.id,
      "arena_id" => arena.id,
      "tabula_id" => board.id,
      "candidate_sha" => receipt["candidate_sha"],
      "head" => current.context["head"],
      "turns_used" => current.turns_used,
      "deadline_at" => DateTime.to_iso8601(current.deadline_at),
      "request_sha256" => digest(Jason.encode!(attempt.request)),
      "snapshot_sha256" => digest(Jason.encode!(current.snapshot)),
      "attempts" => length(Battles.attempts(battle.id)),
      "source_index_sha256" => digest(File.read!(Path.join(arena.path, ".git/index")))
    }

    File.write!(Path.join(root, "expected.json"), Jason.encode!(expected), [:exclusive])
    File.chmod!(Path.join(root, "expected.json"), 0o600)
    Supervisor.stop(tasks)
    :ok = Application.stop(:cuckoding)

    IO.puts(
      "PACKAGED_FIXTURE_READY " <>
        Jason.encode!(Map.take(expected, ~w(format synthetic_provider battle_id attempt_id)))
    )
  end

  defp components(path), do: path |> Path.split() |> Enum.scan(&Path.join(&2, &1))
  def digest(bytes), do: Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

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
      Arenas.register(Ecto.UUID.generate(), selected.id, "SYNTHETIC packaged recovery", true)

    arena
  end

  defp setup_git(arena) do
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "inspect")
    observed = finish_git()
    "missing" = observed.result
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "init", observed.id, true)
    "initialized" = finish_git().result
    File.write!(Path.join(arena.path, "a.txt"), "a base\n", [:exclusive])
    File.write!(Path.join(arena.path, "b.txt"), "b base\n", [:exclusive])
    {:ok, _} = ArenaGit.preview(Ecto.UUID.generate(), arena.id, ["a.txt", "b.txt"])
    preview = finish_git()
    "previewed" = preview.result
    {:ok, _} = ArenaGit.request(Ecto.UUID.generate(), arena.id, "commit", preview.id, true)
    "committed" = finish_git().result
  end

  defp finish_git do
    {:ok, claim} = Foundation.claim()
    {:ok, completed} = Foundation.finish(claim, ArenaGit.execute(claim))
    "completed" = completed.state
    completed
  end

  defp save_task(board, title) do
    {:ok, _} =
      Tabulae.save(Ecto.UUID.generate(), board.arena_id, board.id, Ecto.UUID.generate(), 0, %{
        "title" => title,
        "description" => "Synthetic file edit only",
        "criteria" =>
          "Corresponding file contains its result line; inspect exact bytes. No runtime command checks required.",
        "column" => "specs",
        "depends_on" => []
      })
  end

  defp stage_until_combined(battle, tasks, remaining) do
    true = remaining > 0
    {:ok, attempt} = Battles.claim_next(battle.id)

    result =
      tasks
      |> Task.Supervisor.async_nolink(fn ->
        result =
          BattleExecutor.execute(attempt, provider: Cuckoding.PackagedRecoveryFixture.Provider)

        if attempt.stage == "combine" do
          {:unsettled, result}
        else
          Battles.finish(attempt.id, attempt.claim_token, result)
        end
      end)
      |> Task.await(180_000)

    case result do
      {:unsettled, receipt} ->
        {attempt, receipt}

      {:ok, next} ->
        "running" = next.state
        stage_until_combined(next, tasks, remaining - 1)
    end
  end
end

defmodule Cuckoding.PackagedRecoveryFixture.Provider do
  alias Cuckoding.{ArenaGit, Repo}
  alias Cuckoding.PackagedRecoveryFixture, as: Fixture

  def run_task(_, profile, scratch, request, active?) do
    true = active?.()
    [] = File.ls!(profile)
    [] = File.ls!(scratch)
    attempt = Repo.get!(Cuckoding.Battles.Attempt, request["request_id"])
    path = request["workspace"]["path"]
    true = path == ArenaGit.worktree_path(request["workspace"]["key"])
    %{type: :directory, major_device: device, inode: inode} = File.lstat!(path)
    true = device == request["workspace"]["device"] and inode == request["workspace"]["inode"]
    title = attempt.request["task"]["title"]

    file =
      case title do
        "Fixture A" -> "a.txt"
        "Fixture B" -> "b.txt"
      end

    target = Path.join(path, file)
    contents = String.first(file) <> " result\n"
    write? = request["access"] == "write"
    if write?, do: File.write!(target, contents)
    bytes = File.read!(target)
    if attempt.stage == "secutor", do: true = bytes == contents
    hash = Fixture.digest(bytes)

    tool = %{
      "call_id" => Ecto.UUID.generate(),
      "tool" => if(write?, do: "edit_file", else: "read_file"),
      "status" => "completed",
      "path" => file,
      "sha256" => hash
    }

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
          "SYNTHETIC fixture: inspected exact owned file bytes; no inference or command tests.",
        "outcome" => "completed"
      },
      "tools" => [tool],
      "changes" => if(write?, do: [%{"path" => file, "sha256" => hash}], else: []),
      "cleanup_verified" => true
    }
  end
end

Cuckoding.PackagedRecoveryFixture.run()
