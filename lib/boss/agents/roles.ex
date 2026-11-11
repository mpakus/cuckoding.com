defmodule Boss.Agents.Roles do
  @moduledoc false
  import Ecto.Query
  alias Boss.Agents.{Metadata, Role, RoleMember}
  alias Boss.Repo

  @standard [
    %{
      kind: "reviewer",
      name: "Reviewer",
      purpose: "Reviews specs and code."
    },
    %{
      kind: "implementer",
      name: "Implementer",
      purpose: "Writes code and tests from the specs."
    },
    %{
      kind: "analytic",
      name: "Analytic",
      purpose:
        "Analyzes prompts, specs, and the project to create specs, and helps the Reviewer with questions or when work is stuck."
    }
  ]
  @kind_order %{"reviewer" => 0, "implementer" => 1, "analytic" => 2}

  def standard, do: @standard

  def reviewer_choices do
    assigned = Enum.filter(agents_for("reviewer"), &Metadata.review_runner?(&1.id))

    if assigned == [] do
      [
        %{id: "codex", name: "Codex"},
        %{id: "claude", name: "Claude Code"}
      ]
    else
      assigned
    end
  end

  def implementer do
    case Enum.filter(agents_for("implementer"), &Metadata.execution_runner?(&1.id)) do
      [%{id: id} | _] -> id
      [] -> "codex"
    end
  end

  def analytic(implementer) when implementer in ~w(codex claude cursor) do
    assigned = Enum.filter(agents_for("analytic"), &Metadata.execution_runner?(&1.id))

    case Enum.find(assigned, &(&1.id != implementer)) || List.first(assigned) do
      %{id: id} -> id
      nil -> "codex"
    end
  end

  def agents_for(kind) when kind in ~w(reviewer implementer analytic) do
    assigned =
      list()
      |> Enum.find(&(&1.kind == kind))
      |> then(fn
        nil -> []
        role -> role.agent_ids
      end)

    Metadata.catalog()
    |> Enum.filter(&(Atom.to_string(&1.id) in assigned))
    |> Enum.map(&%{id: Atom.to_string(&1.id), name: &1.name})
  end

  def list do
    if roles_table_ready?() do
      ensure_standard()

      Role
      |> preload(:members)
      |> Repo.all()
      |> Enum.map(&present/1)
      |> Enum.sort_by(&{Map.get(@kind_order, &1.kind, 3), &1.name, &1.id})
    else
      []
    end
  end

  defp roles_table_ready? do
    Repo.query!(
      "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='table' AND name='agent_roles')"
    ).rows == [[1]]
  rescue
    _ -> false
  end

  def create(name) do
    ensure_standard()
    %Role{} |> Role.changeset(%{name: name}) |> Repo.insert()
  end

  def update(id, name) do
    ensure_standard()

    case fetch(id) do
      nil -> {:error, :not_found}
      %{kind: kind} when is_binary(kind) -> {:error, :standard}
      role -> role |> Role.changeset(%{name: name}) |> Repo.update()
    end
  end

  def delete(id) do
    ensure_standard()

    case fetch(id) do
      nil -> {:error, :not_found}
      %{kind: kind} when is_binary(kind) -> {:error, :standard}
      role -> Repo.delete(role)
    end
  end

  def assign(id, agent_ids) when is_list(agent_ids) do
    ensure_standard()
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

  defp present(role) do
    %{
      id: role.id,
      name: role.name,
      kind: role.kind,
      purpose: purpose(role.kind),
      standard: is_binary(role.kind),
      agent_ids: role.members |> Enum.map(& &1.agent_id) |> Enum.sort()
    }
  end

  defp purpose(kind), do: Enum.find_value(@standard, &(&1.kind == kind && &1.purpose))

  defp ensure_standard do
    Enum.each(@standard, fn spec ->
      case Repo.get_by(Role, kind: spec.kind) do
        nil -> insert_standard(spec)
        _role -> :ok
      end
    end)
  end

  defp insert_standard(spec) do
    case Repo.get_by(Role, name: spec.name) do
      nil ->
        %Role{}
        |> Role.standard_changeset(Map.take(spec, [:name, :kind]))
        |> Repo.insert!()

      role ->
        role |> Ecto.Changeset.change(kind: spec.kind) |> Repo.update!()
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
