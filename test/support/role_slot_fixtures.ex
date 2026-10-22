defmodule Cuckoding.RoleSlotFixtures do
  @moduledoc false
  alias Cuckoding.{Agents, Codex, Foundation, Team, TeamAssignments}

  def additional_connection do
    {:ok, command} =
      Agents.add_and_probe(Ecto.UUID.generate(), revision(), "Second writer", "codex", "/bin/sh")

    {:ok, claim} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(claim, %{"status" => "supported", "version" => Codex.isolation_version()})

    id = command.payload["agent_id"]
    {:ok, _} = Foundation.inspect_codex(Ecto.UUID.generate(), revision(), true, id)
    {:ok, claim} = Foundation.claim()

    model = %{
      "id" => "worker-model",
      "model" => "test-model",
      "name" => "Worker model",
      "efforts" => ["low"],
      "default_effort" => "low",
      "input_modalities" => ["text"],
      "default" => true
    }

    {:ok, _} =
      Foundation.finish(claim, %{
        "status" => "checked",
        "authorization" => "chatgpt",
        "catalog_status" => "fresh",
        "models" => [model]
      })

    connection = Agents.get(id).connection

    {:ok, _} =
      Foundation.save_agent_models(
        Ecto.UUID.generate(),
        revision(),
        connection["command_id"],
        ["worker-model"],
        id
      )

    id
  end

  def assign_worker(board, id) do
    team = TeamAssignments.assigned(board)

    roles =
      Team.editable(team)
      |> Enum.map(fn role ->
        if role["id"] == "implementor",
          do: Map.merge(role, %{"parallel_agent" => id, "parallel_model_id" => "worker-model"}),
          else: role
      end)

    {:ok, saved} = Team.save(Ecto.UUID.generate(), team.id, roles, false, board)
    saved
  end

  defp revision, do: Foundation.workspace().revision
end
