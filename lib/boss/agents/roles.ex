defmodule Boss.Agents.Roles do
  @moduledoc false
  import Ecto.Query
  alias Boss.Agents.{Detections, Metadata, Role, RoleMember}
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

  def selection_for(kind, agent_id)
      when kind in ~w(reviewer implementer analytic) and is_binary(agent_id) do
    case Enum.find(list(), &(&1.kind == kind)) do
      %{selections: selections} ->
        Map.get(selections, agent_id, %{model_id: nil, reasoning_effort: nil})

      _ ->
        %{model_id: nil, reasoning_effort: nil}
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

    authorized =
      if Detections.any_saved?() do
        MapSet.new(Map.keys(Detections.authorized_map()))
      else
        nil
      end

    Metadata.catalog()
    |> Enum.filter(fn agent ->
      id_str = Atom.to_string(agent.id)
      id_str in assigned and (is_nil(authorized) or MapSet.member?(authorized, id_str))
    end)
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

  def assign(id, agent_ids, selections \\ %{}) when is_list(agent_ids) and is_map(selections) do
    ensure_standard()
    ids = agent_ids |> Enum.map(&agent_id_string/1) |> Enum.uniq()

    if Enum.all?(ids, &known_agent?/1) do
      Repo.transaction(
        fn ->
          role = fetch(id) || Repo.rollback(:not_found)
          authorized = Detections.authorized_map()

          attrs =
            Enum.map(ids, fn agent_id ->
              raw =
                Map.get(
                  selections,
                  agent_id,
                  Map.get(selections, String.to_existing_atom(agent_id), %{})
                )

              selection!(role.id, agent_id, raw, authorized[agent_id])
            end)

          Repo.delete_all(from member in RoleMember, where: member.role_id == ^role.id)
          Enum.each(attrs, &save_member!(%RoleMember{}, &1))
          role.id
        end,
        mode: :immediate
      )
    else
      {:error, :unknown_agent}
    end
  end

  def assign_member(role_id, agent_id, selection) do
    if known_agent?(agent_id) do
      Repo.transaction(
        fn ->
          role = fetch(role_id) || Repo.rollback(:not_found)

          member = Repo.get_by(RoleMember, role_id: role.id, agent_id: agent_id)

          case selection do
            nil ->
              if member, do: Repo.delete!(member)

            raw ->
              attrs = selection!(role.id, agent_id, raw, Detections.get_view(agent_id))
              save_member!(member || %RoleMember{}, attrs)
          end

          role.id
        end,
        mode: :immediate
      )
    else
      {:error, :unknown_agent}
    end
  end

  defp selection!(
         role_id,
         agent_id,
         raw,
         %{probe_status: :ok, auth_status: :configured} = detection
       )
       when is_map(raw) do
    model_id = normalize_choice(Map.get(raw, "model_id", raw[:model_id]), ["", "__default__"])

    effort =
      normalize_choice(Map.get(raw, "reasoning_effort", raw[:reasoning_effort]), ["", "default"])

    model = Enum.find(detection.models, &(&1["id"] == model_id))

    cond do
      model_id != nil and model == nil ->
        Repo.rollback(:model_not_supported)

      effort != nil and (model == nil or effort not in (model["reasoning_efforts"] || [])) ->
        Repo.rollback(:invalid_reasoning_effort)

      true ->
        %{role_id: role_id, agent_id: agent_id, model_id: model_id, reasoning_effort: effort}
    end
  end

  defp selection!(_, _, _, %{probe_status: :ok, auth_status: :configured}),
    do: Repo.rollback(:model_not_supported)

  defp selection!(_, _, _, _), do: Repo.rollback(:agent_not_authorized)

  defp save_member!(%RoleMember{id: nil} = member, attrs),
    do: member |> RoleMember.changeset(attrs) |> Repo.insert!()

  defp save_member!(member, attrs), do: member |> RoleMember.changeset(attrs) |> Repo.update!()

  defp agent_id_string(id) when is_atom(id), do: Atom.to_string(id)
  defp agent_id_string(id), do: id

  defp known_agent?(id), do: Enum.any?(Metadata.ids(), &(Atom.to_string(&1) == id))

  defp normalize_choice(val, blanks) when is_binary(val) do
    trimmed = String.trim(val)
    if trimmed in blanks, do: nil, else: trimmed
  end

  defp normalize_choice(nil, _), do: nil
  defp normalize_choice(_, _), do: :invalid

  defp present(role) do
    selections =
      Map.new(role.members, fn m ->
        {m.agent_id, %{model_id: m.model_id, reasoning_effort: m.reasoning_effort}}
      end)

    %{
      id: role.id,
      name: role.name,
      kind: role.kind,
      purpose: purpose(role.kind),
      standard: is_binary(role.kind),
      agent_ids: role.members |> Enum.map(& &1.agent_id) |> Enum.sort(),
      selections: selections
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
        |> Repo.insert!(on_conflict: :nothing)

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
