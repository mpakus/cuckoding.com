defmodule Cuckoding.Battles.Capacity do
  @moduledoc "Frozen cross-Arena capacity; callers check inside the SQLite claim transaction."
  import Ecto.Query
  alias Cuckoding.Battles.{Attempt, Battle, ProviderClosure}
  alias Cuckoding.Repo

  def policy, do: "isolated-arenas-v1"
  def limit, do: 2
  def concurrent?(snapshot), do: snapshot["scheduler"] == policy()

  def available?(snapshot, role) do
    running =
      Repo.all(from a in Attempt, where: a.state == "running", select: a.request, limit: 2)

    connection = role && role["agent_id"]
    reservations = guest_reservations()

    length(running) + reservations < limit() and
      (reservations == 0 or concurrent?(snapshot)) and
      (running == [] or
         (concurrent?(snapshot) and Enum.all?(running, &concurrent?(&1["snapshot"])))) and
      connection_available?(connection)
  end

  defp guest_reservations do
    Repo.all(
      from a in Attempt,
        where:
          a.state != "running" and a.stage in ~w(admission checks final_checks) and
            fragment(
              "json_extract(?, '$.snapshot.check_execution.version') = ?",
              a.request,
              "isolated-guest-checks-v1"
            ) and
            fragment("coalesce(json_extract(?, '$.cleanup_verified'), 0) != 1", a.result),
        select: a.id,
        limit: 2
    )
    |> length()
  end

  defp connection_available?(nil), do: true

  defp connection_available?(connection) do
    not Repo.exists?(
      from a in Attempt,
        join: b in Battle,
        on: b.id == a.battle_id,
        where: not is_nil(a.role),
        where: fragment("json_extract(?, '$.role.agent_id') = ?", a.request, ^connection),
        where: fragment("coalesce(json_extract(?, '$.cleanup_verified'), 0) != 1", a.result),
        where:
          not (a.state == "interrupted" and
                 fragment(
                   "coalesce(json_extract(?, '$.provider_closure'), '') = ?",
                   b.snapshot,
                   ^ProviderClosure.policy()
                 ) and
                 fragment(
                   "coalesce(json_extract(?, '$.provider_closures.\"' || ? || '\".cleanup_verified'), 0) = 1",
                   b.context,
                   a.id
                 ) and
                 fragment(
                   "coalesce(json_extract(?, '$.provider_closures.\"' || ? || '\".status'), '') = 'closed'",
                   b.context,
                   a.id
                 ))
    )
  end
end
