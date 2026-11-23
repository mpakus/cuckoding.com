defmodule Boss.Agents.Roles do
  @moduledoc false
  import Ecto.Query
  alias Boss.Agents.{Detections, Metadata, ModelDiscovery, Role, RoleMember}
  alias Boss.Repo

  @standard [
    %{
      kind: "reviewer",
      name: "Reviewer",
      purpose:
        "Reviews specs and code, verifies tasks directly against their specification, and refines specs or requests fixes."
    },
    %{
      kind: "implementer",
      name: "Implementer",
      purpose:
        "Writes code and tests, updates documentation and texts, and implements tasks delegated by Analytic."
    },
    %{
      kind: "analytic",
      name: "Analytic",
      purpose:
        "Brain that orchestrates tasks and agents — analyzes prompts, specs, and the project to create specs, routes work to Implementer and Reviewer, and helps the Reviewer when work is stuck."
    }
  ]
  @kind_order %{"reviewer" => 0, "implementer" => 1, "analytic" => 2}

  def standard, do: @standard

  def standard_list do
    list()
    |> Enum.filter(& &1.standard)
  end

  def bindings_for(kind, opts \\ []) when kind in ~w(reviewer implementer analytic) do
    only_authorized? = Keyword.get(opts, :authorized_only, false)
    only_runners? = Keyword.get(opts, :runners_only, false)

    role = Enum.find(list(), &(&1.kind == kind))
    bindings = if role, do: role.bindings, else: []

    bindings
    |> Enum.filter(fn b ->
      (!only_authorized? or b.authorized) and
        (!only_runners? or runner_allowed?(kind, b.agent_id))
    end)
  end

  def runner_allowed?("reviewer", agent_id), do: Metadata.review_runner?(agent_id)
  def runner_allowed?(_, agent_id), do: Metadata.execution_runner?(agent_id)

  def reviewer_choices(project_id \\ nil) do
    project_choice =
      if is_integer(project_id) and project_id > 0 do
        Boss.Projects.RoleBindings.reviewer_agent_maybe(project_id)
      end

    assigned = Enum.filter(agents_for("reviewer"), &Metadata.review_runner?(&1.id))

    base =
      if assigned == [] do
        [
          %{id: "codex", name: "Codex"},
          %{id: "claude", name: "Claude Code"},
          %{id: "cursor", name: "Cursor Agent"},
          %{id: "opencode", name: "OpenCode"}
        ]
        |> filter_authorized_or_default(["codex", "claude"])
      else
        assigned
      end

    if is_binary(project_choice) and Metadata.review_runner?(project_choice) and
         not Enum.any?(base, &(&1.id == project_choice)) do
      [%{id: project_choice, name: agent_label(project_choice)} | base]
    else
      base
    end
  end

  defp filter_authorized_or_default(candidates, fallback_ids) do
    if Detections.any_saved?() do
      authorized = MapSet.new(Map.keys(Detections.authorized_map()))
      matched = Enum.filter(candidates, &MapSet.member?(authorized, &1.id))

      if matched != [] do
        matched
      else
        Enum.filter(candidates, &(&1.id in fallback_ids))
      end
    else
      Enum.filter(candidates, &(&1.id in fallback_ids))
    end
  end

  def prompt_agent_choices do
    authorized =
      if Detections.any_saved?() do
        MapSet.new(Map.keys(Detections.authorized_map()))
      else
        nil
      end

    choices =
      Metadata.catalog()
      |> Enum.filter(fn agent ->
        id_str = Atom.to_string(agent.id)

        Metadata.execution_runner?(id_str) and
          (is_nil(authorized) or MapSet.member?(authorized, id_str))
      end)
      |> Enum.map(&%{id: Atom.to_string(&1.id), name: &1.name})

    if choices == [] do
      [
        %{id: "codex", name: "Codex"},
        %{id: "claude", name: "Claude Code"},
        %{id: "cursor", name: "Cursor Agent"},
        %{id: "opencode", name: "OpenCode"}
      ]
    else
      choices
    end
  end

  def models_for_agent(agent_id, opts \\ [])

  def models_for_agent(agent_id, opts) when is_binary(agent_id) do
    include_disabled? = Keyword.get(opts, :include_disabled, false)

    case Detections.get_view(agent_id) do
      %{probe_status: :ok, auth_status: :configured, models: models} when is_list(models) ->
        models
        |> Enum.filter(&(include_disabled? or Map.get(&1, "enabled", true) != false))
        |> Enum.map(&present_model(agent_id, &1))

      _ ->
        []
    end
  end

  def models_for_agent(agent_id, opts) when is_atom(agent_id),
    do: models_for_agent(Atom.to_string(agent_id), opts)

  def present_model(agent_id, model) when is_map(model) do
    id = model["id"] || model[:id]
    name = model["name"] || model[:name] || id
    efforts = model["reasoning_efforts"] || model[:reasoning_efforts] || []

    %{
      id: id,
      name: name,
      reasoning: model["reasoning"] == true or efforts != [],
      reasoning_efforts: efforts,
      default_effort: model["default_effort"] || model[:default_effort],
      context_window: model["context_window"] || model[:context_window],
      pricing: model["pricing"] || model[:pricing],
      price_label: ModelDiscovery.price_label(model),
      billing: ModelDiscovery.billing_for(agent_id, model),
      billing_label: ModelDiscovery.billing_label(agent_id, model),
      enabled: Map.get(model, "enabled", Map.get(model, :enabled, true)) != false
    }
  end

  def default_prompt_agent(choices \\ nil, project_id \\ nil) do
    choices = choices || prompt_agent_choices()
    ids = Enum.map(choices, & &1.id)

    project_analytic =
      if is_integer(project_id) and project_id > 0 do
        Boss.Projects.RoleBindings.analytic_agent_maybe(project_id)
      end

    analytic_primary =
      case Enum.filter(agents_for("analytic"), &Metadata.execution_runner?(&1.id)) do
        [%{id: id} | _] -> id
        [] -> nil
      end

    implementer_primary = implementer(project_id)

    cond do
      is_binary(project_analytic) and project_analytic in ids -> project_analytic
      is_binary(analytic_primary) and analytic_primary in ids -> analytic_primary
      implementer_primary in ids -> implementer_primary
      "codex" in ids -> "codex"
      ids != [] -> hd(ids)
      true -> "codex"
    end
  end

  def implementer(project_id \\ Process.get(:boss_active_project_id)) do
    project_choice =
      if is_integer(project_id) and project_id > 0 do
        Boss.Projects.RoleBindings.implementer_agent_maybe(project_id)
      end

    cond do
      is_binary(project_choice) and Metadata.execution_runner?(project_choice) ->
        project_choice

      true ->
        case Enum.filter(agents_for("implementer"), &Metadata.execution_runner?(&1.id)) do
          [%{id: id} | _] -> id
          [] -> "codex"
        end
    end
  end

  def analytic(implementer, project_id \\ Process.get(:boss_active_project_id))
      when implementer in ~w(codex claude cursor opencode) do
    project_choice =
      if is_integer(project_id) and project_id > 0 do
        Boss.Projects.RoleBindings.analytic_agent_maybe(project_id)
      end

    if is_binary(project_choice) and Metadata.execution_runner?(project_choice) do
      project_choice
    else
      assigned = Enum.filter(agents_for("analytic"), &Metadata.execution_runner?(&1.id))

      non_codex_other = Enum.find(assigned, &(&1.id != implementer and &1.id != "codex"))
      any_other = Enum.find(assigned, &(&1.id != implementer))
      non_codex_any = Enum.find(assigned, &(&1.id != "codex"))

      case non_codex_other || any_other || non_codex_any || List.first(assigned) do
        %{id: id} -> id
        nil -> "codex"
      end
    end
  end

  def selection_for(kind, agent_id, project_id \\ Process.get(:boss_active_project_id))
      when kind in ~w(reviewer implementer analytic) and is_binary(agent_id) do
    project_sel =
      if is_integer(project_id) and project_id > 0 do
        Boss.Projects.RoleBindings.selection_for(project_id, kind, agent_id)
      end

    cond do
      is_map(project_sel) ->
        project_sel

      true ->
        case Enum.find(list(), &(&1.kind == kind)) do
          %{bindings: bindings, selections: selections} ->
            case Enum.find(bindings, &(&1.agent_id == agent_id and &1.authorized)) do
              %{model_id: model_id, reasoning_effort: effort} ->
                %{model_id: model_id, reasoning_effort: effort}

              nil ->
                Map.get(selections, agent_id, %{model_id: nil, reasoning_effort: nil})
            end

          _ ->
            %{model_id: nil, reasoning_effort: nil}
        end
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
      detections = Detections.load_state().results

      Role
      |> preload(:members)
      |> Repo.all()
      |> Enum.map(&present(&1, detections))
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

  def add_binding(role_id_or_kind, agent_id, raw \\ %{}) do
    ensure_standard()
    agent_str = agent_id_string(agent_id)

    if known_agent?(agent_str) do
      Repo.transaction(
        fn ->
          role = fetch_or_kind(role_id_or_kind) || Repo.rollback(:not_found)
          attrs = selection!(role.id, agent_str, raw, Detections.get_view(agent_str))

          existing =
            Repo.one(
              from m in RoleMember,
                where: m.role_id == ^role.id and m.agent_id == ^agent_str,
                where:
                  fragment("COALESCE(?, '__default__')", m.model_id) ==
                    ^(attrs.model_id || "__default__"),
                where:
                  fragment("COALESCE(?, '__default__')", m.reasoning_effort) ==
                    ^(attrs.reasoning_effort || "__default__"),
                limit: 1
            )

          existing || save_member!(%RoleMember{}, attrs)
        end,
        mode: :immediate
      )
    else
      {:error, :unknown_agent}
    end
  end

  def update_binding(member_id, agent_id, raw \\ %{}) do
    ensure_standard()
    agent_str = agent_id_string(agent_id)

    case {parse_int(member_id), known_agent?(agent_str)} do
      {nil, _} ->
        {:error, :not_found}

      {_, false} ->
        {:error, :unknown_agent}

      {id, true} ->
        result =
          Repo.transaction(
            fn ->
              member = Repo.get(RoleMember, id) || Repo.rollback(:not_found)
              attrs = selection!(member.role_id, agent_str, raw, Detections.get_view(agent_str))

              duplicate =
                Repo.one(
                  from m in RoleMember,
                    where: m.role_id == ^member.role_id and m.id != ^member.id,
                    where: m.agent_id == ^agent_str,
                    where:
                      fragment("COALESCE(?, '__default__')", m.model_id) ==
                        ^(attrs.model_id || "__default__"),
                    where:
                      fragment("COALESCE(?, '__default__')", m.reasoning_effort) ==
                        ^(attrs.reasoning_effort || "__default__"),
                    limit: 1
                )

              {saved, affected_projects} =
                case duplicate do
                  nil ->
                    updated = save_member!(member, attrs)
                    projects = sync_project_bindings(member.id, updated.id, attrs)
                    {updated, projects}

                  other ->
                    projects =
                      sync_project_bindings(member.id, other.id, %{
                        agent_id: other.agent_id,
                        model_id: other.model_id,
                        reasoning_effort: other.reasoning_effort
                      })

                    Repo.delete!(member)
                    {other, projects}
                end

              {saved, affected_projects}
            end,
            mode: :immediate
          )

        case result do
          {:ok, {saved, affected_projects}} ->
            Enum.each(affected_projects, fn pid ->
              Phoenix.PubSub.broadcast(
                Boss.PubSub,
                "project:#{pid}:roles",
                {:roles_changed, pid}
              )
            end)

            {:ok, saved}

          error ->
            error
        end
    end
  end

  def add_next_binding(role_id_or_kind, eligible_agent_ids) when is_list(eligible_agent_ids) do
    ensure_standard()

    case fetch_or_kind(role_id_or_kind) do
      nil ->
        {:error, :not_found}

      role ->
        existing =
          Repo.all(from m in RoleMember, where: m.role_id == ^role.id)
          |> MapSet.new(fn m ->
            {m.agent_id, m.model_id || "__default__", m.reasoning_effort || ""}
          end)

        candidate =
          Enum.find_value(eligible_agent_ids, fn raw_agent ->
            agent_str = agent_id_string(raw_agent)
            models = models_for_agent(agent_str)

            case models do
              [] ->
                key = {agent_str, "__default__", ""}
                if not MapSet.member?(existing, key), do: {agent_str, nil, nil}

              list ->
                Enum.find_value(list, fn m ->
                  eff = m.default_effort || ""
                  key = {agent_str, m.id, eff}

                  if not MapSet.member?(existing, key) do
                    {agent_str, m.id, m.default_effort}
                  end
                end)
            end
          end)

        case candidate do
          {agent_str, model_id, effort} ->
            add_binding(role.id, agent_str, %{
              "model_id" => model_id,
              "reasoning_effort" => effort
            })

          nil ->
            {:error, :all_combinations_bound}
        end
    end
  end

  def remove_binding(member_id) do
    case parse_int(member_id) do
      nil ->
        {:error, :not_found}

      id ->
        case Repo.get(RoleMember, id) do
          nil -> {:error, :not_found}
          member -> Repo.delete(member)
        end
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

          case selection do
            nil ->
              Repo.delete_all(
                from m in RoleMember,
                  where: m.role_id == ^role.id and m.agent_id == ^agent_id
              )

            raw ->
              attrs = selection!(role.id, agent_id, raw, Detections.get_view(agent_id))

              members =
                Repo.all(
                  from m in RoleMember,
                    where: m.role_id == ^role.id and m.agent_id == ^agent_id,
                    order_by: [asc: m.id]
                )

              case members do
                [] ->
                  save_member!(%RoleMember{}, attrs)

                [sole] ->
                  save_member!(sole, attrs)

                many ->
                  exact =
                    Enum.find(
                      many,
                      &(&1.model_id == attrs.model_id and
                          &1.reasoning_effort == attrs.reasoning_effort)
                    )

                  exact || save_member!(%RoleMember{}, attrs)
              end
          end

          role.id
        end,
        mode: :immediate
      )
    else
      {:error, :unknown_agent}
    end
  end

  def binding_tag(role_kind, agent_id, model_id, effort \\ nil) do
    prefix =
      case to_string(role_kind) do
        "reviewer" -> "Reviews"
        "implementer" -> "Implementer"
        "analytic" -> "Analytic"
        other -> Macro.camelize(other)
      end

    agent_token =
      case to_string(agent_id) do
        "codex" -> "Codex"
        "claude" -> "Claude"
        "cursor" -> "Cursor"
        "opencode" -> "OpenCode"
        "hermes" -> "Hermes"
        "pi" -> "Pi"
        other -> Macro.camelize(other)
      end

    model_token = compact_model_token(agent_id, model_id)
    effort_suffix = if is_binary(effort) and effort != "", do: "·#{effort}", else: ""

    "#{prefix}:#{agent_token}#{model_token}#{effort_suffix}"
  end

  defp compact_model_token(_agent_id, nil), do: "Default"
  defp compact_model_token(_agent_id, ""), do: "Default"

  defp compact_model_token(agent_id, model_id) when is_binary(model_id) do
    stripped =
      model_id
      |> String.replace(~r/\A[a-z0-9_-]+\//i, "")
      |> String.replace(~r/(\d+)-(\d+)/, "\\1.\\2")
      |> then(fn s ->
        if to_string(agent_id) == "claude",
          do: String.replace(s, ~r/\Aclaude-/i, ""),
          else: s
      end)

    parts =
      stripped
      |> String.split(~r/[^A-Za-z0-9.]+/, trim: true)
      |> Enum.map(fn part ->
        cond do
          Regex.match?(~r/\A[0-9.]+\z/, part) -> part
          String.downcase(part) == "gpt" -> "GPT"
          true -> String.capitalize(part)
        end
      end)

    case Enum.join(parts, "") do
      "" -> "Model"
      joined -> joined
    end
  end

  def agent_label(id_str) do
    Enum.find_value(Metadata.catalog(), id_str, fn a ->
      Atom.to_string(a.id) == id_str && a.name
    end)
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

  defp sync_project_bindings(old_member_id, new_member_id, attrs) do
    if attrs.agent_id in ~w(codex claude cursor opencode) and
         Boss.Projects.RoleBindings.table_ready?() do
      project_ids =
        Repo.all(
          from pb in Boss.Projects.RoleBinding,
            where: pb.member_id == ^old_member_id,
            select: pb.project_id
        )

      if project_ids != [] do
        now = DateTime.utc_now()

        Repo.update_all(
          from(pb in Boss.Projects.RoleBinding, where: pb.member_id == ^old_member_id),
          set: [
            member_id: new_member_id,
            agent_id: attrs.agent_id,
            model_id: attrs.model_id,
            reasoning_effort: attrs.reasoning_effort,
            updated_at: now
          ]
        )
      end

      pool_projects =
        if Boss.Projects.RoleBindings.pool_table_ready?() do
          pids =
            Repo.all(
              from pp in Boss.Projects.ImplementerPoolItem,
                where: pp.member_id == ^old_member_id,
                select: pp.project_id
            )

          if pids != [] do
            tag =
              binding_tag(
                "implementer",
                attrs.agent_id,
                attrs.model_id,
                attrs.reasoning_effort
              )

            now = DateTime.utc_now()

            Repo.update_all(
              from(pp in Boss.Projects.ImplementerPoolItem,
                where: pp.member_id == ^old_member_id
              ),
              set: [
                member_id: new_member_id,
                agent_id: attrs.agent_id,
                model_id: attrs.model_id,
                reasoning_effort: attrs.reasoning_effort,
                binding_tag: tag,
                updated_at: now
              ]
            )
          end

          pids
        else
          []
        end

      Enum.uniq(project_ids ++ pool_projects)
    else
      []
    end
  end

  defp agent_id_string(id) when is_atom(id), do: Atom.to_string(id)
  defp agent_id_string(id), do: to_string(id)

  defp known_agent?(id), do: Enum.any?(Metadata.ids(), &(Atom.to_string(&1) == id))

  defp normalize_choice(val, blanks) when is_binary(val) do
    trimmed = String.trim(val)
    if trimmed in blanks, do: nil, else: trimmed
  end

  defp normalize_choice(nil, _), do: nil
  defp normalize_choice(_, _), do: :invalid

  defp present(role, detections) do
    sorted_members = Enum.sort_by(role.members, & &1.id)

    bindings =
      Enum.map(sorted_members, fn m ->
        present_member(role, m, detections)
      end)

    selections =
      Enum.reduce(Enum.reverse(sorted_members), %{}, fn m, acc ->
        Map.put(acc, m.agent_id, %{model_id: m.model_id, reasoning_effort: m.reasoning_effort})
      end)

    %{
      id: role.id,
      name: role.name,
      kind: role.kind,
      purpose: purpose(role.kind),
      standard: is_binary(role.kind),
      agent_ids: sorted_members |> Enum.map(& &1.agent_id) |> Enum.uniq() |> Enum.sort(),
      selections: selections,
      bindings: bindings
    }
  end

  defp present_member(role, member, detections) do
    id_atom = Enum.find(Metadata.ids(), &(Atom.to_string(&1) == member.agent_id))
    det = if id_atom, do: Map.get(detections, id_atom)
    authorized? = match?(%{probe_status: :ok, auth_status: :configured}, det)

    model_map =
      if det && is_list(det.models) && is_binary(member.model_id) do
        Enum.find(det.models, &(&1["id"] == member.model_id))
      end

    fallback_model = %{
      "id" => member.model_id || "default",
      "name" => member.model_id || "CLI default"
    }

    effective_model = model_map || fallback_model

    %{
      id: member.id,
      role_id: role.id,
      role_kind: role.kind,
      role_name: role.name,
      agent_id: member.agent_id,
      agent_name: agent_label(member.agent_id),
      model_id: member.model_id,
      model_name: effective_model["name"] || member.model_id || "CLI default",
      reasoning_effort: member.reasoning_effort,
      price_label:
        if(member.model_id, do: ModelDiscovery.price_label(effective_model), else: "CLI default"),
      billing: ModelDiscovery.billing_for(member.agent_id, effective_model),
      billing_label: ModelDiscovery.billing_label(member.agent_id, effective_model),
      authorized: authorized?,
      tag:
        binding_tag(
          role.kind || role.name,
          member.agent_id,
          member.model_id,
          member.reasoning_effort
        )
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

  defp fetch_or_kind(kind) when kind in ~w(reviewer implementer analytic),
    do: Repo.get_by(Role, kind: kind)

  defp fetch_or_kind(id), do: fetch(id)

  defp fetch(id) when is_integer(id), do: Repo.get(Role, id)

  defp fetch(id) when is_binary(id) do
    case parse_int(id) do
      nil -> nil
      value -> Repo.get(Role, value)
    end
  end

  defp fetch(_), do: nil

  defp parse_int(val) when is_integer(val) and val > 0, do: val

  defp parse_int(val) when is_binary(val) do
    case Integer.parse(val) do
      {n, ""} when n > 0 -> n
      _ -> nil
    end
  end

  defp parse_int(_), do: nil
end
