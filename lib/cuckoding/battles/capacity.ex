defmodule Cuckoding.Battles.Capacity do
  @moduledoc "Frozen cross-Arena capacity; callers check inside the SQLite claim transaction."
  import Ecto.Query
  alias Cuckoding.Battles.Attempt
  alias Cuckoding.Repo

  def policy, do: "isolated-arenas-v1"
  def limit, do: 2
  def concurrent?(snapshot), do: snapshot["scheduler"] == policy()

  def available?(snapshot, role) do
    running =
      Repo.all(from a in Attempt, where: a.state == "running", select: a.request, limit: 2)

    connection = role && role["agent_id"]

    length(running) < limit() and
      (running == [] or
         (concurrent?(snapshot) and Enum.all?(running, &concurrent?(&1["snapshot"])))) and
      connection_available?(connection)
  end

  defp connection_available?(nil), do: true

  defp connection_available?(connection) do
    not Repo.exists?(
      from a in Attempt,
        where: not is_nil(a.role),
        where: fragment("json_extract(?, '$.role.agent_id') = ?", a.request, ^connection),
        where: fragment("coalesce(json_extract(?, '$.cleanup_verified'), 0) != 1", a.result)
    )
  end
end
