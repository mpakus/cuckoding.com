defmodule Boss.Agents.Roles do
  @moduledoc false
  import Ecto.Query
  alias Boss.Agents.{Metadata, Role, RoleMember}
  alias Boss.Repo

  def list do
    Role
    |> order_by([role], asc: role.name, asc: role.id)
    |> preload(:members)
    |> Repo.all()
    |> Enum.map(fn role ->
      %{
        id: role.id,
        name: role.name,
        agent_ids: role.members |> Enum.map(& &1.agent_id) |> Enum.sort()
      }
    end)
  end

  def create(name), do: %Role{} |> Role.changeset(%{name: name}) |> Repo.insert()

  def update(id, name) do
    case fetch(id) do
      nil -> {:error, :not_found}
      role -> role |> Role.changeset(%{name: name}) |> Repo.update()
    end
  end

  def delete(id) do
    case fetch(id) do
      nil -> {:error, :not_found}
      role -> Repo.delete(role)
    end
  end

  def assign(id, agent_ids) when is_list(agent_ids) do
    ids = agent_ids |> Enum.map(&to_string/1) |> Enum.uniq() |> Enum.sort()
    allowed = MapSet.new(Metadata.ids(), &Atom.to_string/1)

    if Enum.all?(ids, &MapSet.member?(allowed, &1)) do
      Repo.transaction(fn ->
        role = fetch(id) || Repo.rollback(:not_found)

        Repo.delete_all(from member in RoleMember, where: member.role_id == ^role.id)

        Enum.each(ids, fn agent_id ->
          %RoleMember{}
          |> RoleMember.changeset(%{role_id: role.id, agent_id: agent_id})
          |> Repo.insert!()
        end)

        role.id
      end)
    else
      {:error, :unknown_agent}
    end
  end

  defp fetch(id) when is_integer(id), do: Repo.get(Role, id)

  defp fetch(id) when is_binary(id) do
    case Integer.parse(id) do
      {value, ""} -> Repo.get(Role, value)
      _ -> nil
    end
  end

  defp fetch(_), do: nil
end
