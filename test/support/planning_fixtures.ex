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
            "criteria" => "A focused test passes"
          }
        ]
      }
    }
  end
end
