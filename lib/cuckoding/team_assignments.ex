defmodule Cuckoding.TeamAssignments do
  @moduledoc "Confirmed scoped adoptions; creation references and past requests stay immutable."
  import Ecto.Query
  alias Cuckoding.{Arena, Command, Foundation, Repo, Tabula, Team, TeamAdoption, TeamRevision}

  def assigned(scope) do
    adoption = Repo.one(from a in query(scope), order_by: [desc: a.id], limit: 1)

    Repo.get!(
      TeamRevision,
      if(adoption, do: adoption.team_revision_id, else: scope.team_revision_id)
    )
  end

  def history(scope),
    do:
      Repo.all(from a in query(scope), order_by: [desc: a.id], limit: 5, preload: :team_revision)

  # Called inside the accepted logout transaction; historical teams and battle snapshots stay intact.
  def disconnect_agent(agent_id, cause_id) do
    true = Repo.in_transaction?()
    default = Team.current()

    changed =
      for scope <- Repo.all(Arena) ++ Repo.all(Tabula),
          team = assigned(scope),
          Enum.any?(team.definition["roles"], &(&1["agent"] == agent_id)) do
        revision = unassigned_revision(team, agent_id, cause_id)

        Repo.insert!(%TeamAdoption{
          arena_id: if(match?(%Arena{}, scope), do: scope.id, else: scope.arena_id),
          tabula_id: if(match?(%Tabula{}, scope), do: scope.id),
          team_revision_id: revision.id,
          command_id: revision.command_id,
          inserted_at: DateTime.utc_now()
        })
      end

    # Team.current is the latest revision, so restore the default last even if only scoped teams changed.
    if changed != [] or Enum.any?(default.definition["roles"], &(&1["agent"] == agent_id)),
      do: unassigned_revision(default, agent_id, cause_id)
  end

  defp unassigned_revision(team, agent_id, cause_id) do
    roles =
      Enum.map(team.definition["roles"], fn role ->
        if role["agent"] == agent_id,
          do: Map.merge(role, %{"agent" => "", "model_id" => "", "model" => ""}),
          else: role
      end)

    command =
      Repo.insert!(%Command{
        id: Ecto.UUID.generate(),
        kind: "disconnect_agent_roles",
        expected_revision: team.id,
        payload: %{"agent_id" => agent_id, "disconnect_command_id" => cause_id},
        state: "completed"
      })

    revision =
      Repo.insert!(%TeamRevision{
        command_id: command.id,
        definition: Map.put(team.definition, "roles", roles),
        inserted_at: DateTime.utc_now()
      })

    Foundation.record(
      "team.agent_unassigned",
      %{
        "agent_id" => agent_id,
        "previous_revision" => team.id,
        "revision" => revision.id,
        "disconnect_command_id" => cause_id
      },
      command.id
    )

    revision
  end

  defp query(%Arena{id: id}),
    do: from(a in TeamAdoption, where: a.arena_id == ^id and is_nil(a.tabula_id))

  defp query(%Tabula{id: id, arena_id: arena_id}),
    do: from(a in TeamAdoption, where: a.arena_id == ^arena_id and a.tabula_id == ^id)

  def busy?(%Arena{}), do: false

  def busy?(%Tabula{id: id}) do
    Repo.exists?(
      from c in Command,
        where:
          c.kind == "plan_tabula" and c.state in ~w(pending running cancelling) and
            fragment("json_extract(?, '$.tabula_id')", c.payload) == ^id
    )
  end

  def adopt(key, arena_id, tabula_id, expected, target, confirmed) do
    with {:ok, key} <- Ecto.UUID.cast(key),
         {:ok, arena_id} <- Ecto.UUID.cast(arena_id),
         {:ok, tabula_id} <- optional_id(tabula_id),
         true <- is_integer(expected) and expected > 0 and is_integer(target) and target > 0 do
      payload = %{
        "arena_id" => arena_id,
        "tabula_id" => tabula_id,
        "team_revision_id" => target,
        "confirmed" => confirmed == true
      }

      command(key, expected, payload)
    else
      _ -> {:error, "invalid_adoption"}
    end
  end

  defp command(key, expected, payload) do
    result =
      Repo.transaction(
        fn ->
          case Repo.get(Command, key) do
            nil ->
              persist(key, expected, payload)

            %Command{kind: "adopt_team", expected_revision: ^expected, payload: ^payload} = c ->
              c

            _ ->
              Repo.rollback(:key_conflict)
          end
        end,
        mode: :immediate
      )

    if match?({:ok, _}, result), do: Foundation.broadcast()

    case result do
      {:ok, %Command{state: "completed"}} -> {:ok, Repo.get_by!(TeamAdoption, command_id: key)}
      {:ok, %Command{result: reason}} -> {:error, reason}
      error -> error
    end
  end

  defp optional_id(nil), do: {:ok, nil}
  defp optional_id(id), do: Ecto.UUID.cast(id)

  defp persist(key, expected, payload) do
    scope =
      if payload["tabula_id"],
        do: Repo.get_by(Tabula, id: payload["tabula_id"], arena_id: payload["arena_id"]),
        else: Repo.get(Arena, payload["arena_id"])

    reason = rejection(scope, expected, payload)

    command =
      Repo.insert!(%Command{
        id: key,
        kind: "adopt_team",
        expected_revision: expected,
        payload: payload,
        state: if(reason, do: "rejected", else: "completed"),
        result: reason
      })

    if is_nil(reason) do
      Repo.insert!(%TeamAdoption{
        arena_id: payload["arena_id"],
        tabula_id: payload["tabula_id"],
        team_revision_id: payload["team_revision_id"],
        command_id: key,
        inserted_at: DateTime.utc_now()
      })
    end

    Foundation.record(
      "team.adoption_#{command.state}",
      payload
      |> Map.delete("confirmed")
      |> Map.merge(%{"previous_revision" => expected, "reason" => reason}),
      key
    )

    command
  end

  defp rejection(scope, expected, payload) do
    cond do
      scope == nil ->
        "scope_missing"

      not payload["confirmed"] ->
        "adoption_confirmation_required"

      assigned(scope).id != expected or Team.current().id != payload["team_revision_id"] ->
        "stale_adoption"

      expected == payload["team_revision_id"] ->
        "team_already_adopted"

      busy?(scope) ->
        "planning_active"

      true ->
        nil
    end
  end
end
