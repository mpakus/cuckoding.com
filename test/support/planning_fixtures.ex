defmodule Cuckoding.PlanningFixtures do
  @moduledoc false
  alias Cuckoding.{Foundation, Tabulae, Team}

  def planning_fixture do
    root = "/private/tmp/cuckoding-planning-test-#{Ecto.UUID.generate()}"
    File.mkdir!(root)
    path = Path.join(root, "codex")
    File.write!(path, "#!/bin/sh\nexit 1\n")
    File.chmod!(path, 0o700)
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf!(root) end)
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, path, true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => "0.146.0"})
    {:ok, _} = Foundation.inspect_codex(Ecto.UUID.generate(), 1, true)
    {:ok, claim} = Foundation.claim()

    Foundation.finish(claim, %{
      "status" => "checked",
      "authorization" => "chatgpt",
      "catalog_status" => "fresh",
      "models" => [
        %{
          "id" => "test-id",
          "model" => "test-model",
          "name" => "Fixture model",
          "efforts" => ["low"],
          "default_effort" => "low",
          "input_modalities" => ["text"],
          "default" => true
        }
      ]
    })

    team = Team.current()

    roles =
      Enum.map(Team.editable(team), fn role ->
        if role["id"] == "speculator",
          do: Map.merge(role, %{"agent" => "codex", "model_id" => "test-id"}),
          else: role
      end)

    {:ok, _} = Team.save(Ecto.UUID.generate(), team.id, roles)
    arena = Cuckoding.DataCase.arena_fixture()
    {:ok, board} = Tabulae.create(Ecto.UUID.generate(), arena.id, "Fixture planning")
    %{arena: arena, board: Tabulae.get(arena.id, board.id), path: path}
  end

  def planning_receipt(id) do
    %{
      "status" => "planned",
      "request_id" => id,
      "requested_model" => "test-model",
      "observed_model" => "test-model",
      "effort" => "low",
      "thread_id" => Ecto.UUID.generate(),
      "turn_id" => Ecto.UUID.generate(),
      "grant" => "scratch-read-only-v1",
      "elapsed_ms" => 20,
      "proposal" => %{
        "summary" => "A small plan",
        "tasks" => [
          %{
            "title" => "A proposed task",
            "description" => "Implement the brief",
            "criteria" => "A focused test passes",
            "depends_on" => [],
            "sources" => []
          }
        ]
      }
    }
  end

  def add_planning_role(board) do
    alias Cuckoding.TeamAssignments
    team = Team.current()
    planner = Enum.find(Team.editable(team), &(&1["id"] == "speculator"))

    role =
      Team.custom_role()
      |> Map.merge(Map.take(planner, ~w(agent model_id)))
      |> Map.merge(%{"name" => "Researcher", "instructions" => "Create a careful task plan."})

    {:ok, team} = Team.save(Ecto.UUID.generate(), team.id, Team.editable(team) ++ [role])

    {:ok, _} =
      TeamAssignments.adopt(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        TeamAssignments.assigned(board).id,
        team.id,
        true
      )

    %{board: Tabulae.get(board.arena_id, board.id), role: role}
  end

  def cursor_speculator(board) do
    alias Cuckoding.{Agents, Cursor, TeamAssignments}
    revision = fn -> Foundation.workspace().revision end

    {:ok, command} =
      Agents.add_and_probe(
        Ecto.UUID.generate(),
        revision.(),
        "Cursor planner",
        "cursor",
        "/bin/sh"
      )

    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{"status" => "supported", "version" => Cursor.task_version()})

    agent_id = command.payload["agent_id"]
    {:ok, _} = Foundation.inspect_codex(Ecto.UUID.generate(), revision.(), true, agent_id)
    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{
        "status" => "checked",
        "authorization" => "cursor",
        "catalog_status" => "fresh",
        "models" => [
          %{
            "id" => "cursor-fixture",
            "model" => "cursor-fixture",
            "name" => "Cursor fixture",
            "default" => true,
            "hidden" => false
          }
        ]
      })

    connection = Agents.get(agent_id).connection

    {:ok, _} =
      Foundation.save_agent_models(
        Ecto.UUID.generate(),
        revision.(),
        connection["command_id"],
        ["cursor-fixture"],
        agent_id
      )

    team = Team.current()

    roles =
      Team.editable(team)
      |> Enum.map(fn role ->
        if role["id"] == "speculator",
          do: Map.merge(role, %{"agent" => agent_id, "model_id" => "cursor-fixture"}),
          else: role
      end)

    {:ok, team} = Team.save(Ecto.UUID.generate(), team.id, roles)

    {:ok, _} =
      TeamAssignments.adopt(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        TeamAssignments.assigned(board).id,
        team.id,
        true
      )

    %{agent: Agents.get(agent_id), board: Tabulae.get(board.arena_id, board.id)}
  end

  def cursor_planning_receipt(id) do
    planning_receipt(id)
    |> Map.merge(%{
      "requested_model" => "cursor-fixture",
      "observed_model" => "cursor-fixture",
      "grant" => "cursor-plan-no-tools-v1",
      "transport" => "cursor-acp-v1",
      "effort" => nil,
      "runtime_model" => "fixture-base",
      "runtime_parameters" => %{"effort" => "xhigh"},
      "cleanup_verified" => true
    })
  end

  # Simulate a request consented before automatic card creation was introduced.
  def legacy_plan_fixture(claim) do
    claim
    |> Ecto.Changeset.change(payload: Map.delete(claim.payload, "card_creation"))
    |> Cuckoding.Repo.update!()
  end

  def imported_revision(board, plan_id, index \\ 0) do
    task_id = Map.fetch!(Tabulae.imported(board.id), {plan_id, index})
    Cuckoding.Repo.get_by!(Cuckoding.DraftTaskRevision, task_id: task_id, revision: 1)
  end

  def document_receipt(path \\ "docs/plan.md", text \\ "# Selected plan\nBuild a small feature.") do
    %{
      "status" => "previewed",
      "elapsed_ms" => 12,
      "files" => [
        %{
          "path" => path,
          "text" => text,
          "bytes" => byte_size(text),
          "sha256" => Base.encode16(:crypto.hash(:sha256, text), case: :lower)
        }
      ]
    }
  end

  def document_plan_fixture(board) do
    {:ok, preview} =
      Cuckoding.PlanningDocuments.request(Ecto.UUID.generate(), board.arena_id, board.id, [
        "docs/plan.md"
      ])

    {:ok, claim} = Foundation.claim()
    {:ok, _} = Foundation.finish(claim, document_receipt())
    setup = Cuckoding.Planning.setup(board, preview.id)

    {:ok, _} =
      Cuckoding.Planning.request(
        Ecto.UUID.generate(),
        board.arena_id,
        board.id,
        "Plan from the selected source",
        setup.token,
        true,
        preview.id
      )

    {:ok, claim} = Foundation.claim()
    claim
  end

  def folder_receipt(files \\ nil) do
    files = files || for n <- 0..15, do: hd(document_receipt("docs/#{n}.md")["files"])

    %{
      "status" => "previewed",
      "policy" => "folder-documents-v1",
      "files" => files,
      "scan" => %{"visited" => length(files), "skipped" => %{}, "limited" => false},
      "elapsed_ms" => 12
    }
  end

  def linked_planning_receipt(id) do
    task = hd(planning_receipt(id)["proposal"]["tasks"])

    tasks =
      for {title, dependencies} <- [
            {"Specify response", []},
            {"Implement response", [0]},
            {"Check response", [0, 1]}
          ] do
        Map.merge(task, %{"title" => title, "depends_on" => dependencies, "sources" => [0]})
      end

    put_in(planning_receipt(id), ["proposal", "tasks"], tasks)
  end
end
