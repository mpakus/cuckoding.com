defmodule Boss.Projects.RoleBindings do
  @moduledoc """
  Per-project selection of Agent-Model-Role bindings (`analytic`, multi-`implementer` pool,
  `reviewer`) and Analytic load-balancing dispatch across enabled Implementers.
  """
  import Ecto.Query
  alias Boss.Agents.{Metadata, RoleMember, Roles}
  alias Boss.Deliveries.{Delivery, ImplementerBinding}
  alias Boss.Projects.{ImplementerPoolItem, RoleBinding}
  alias Boss.Repo

  @roles ~w(analytic implementer reviewer)
  @busy_statuses ~w(planning implementing testing reviewing)

  def topic(project_id), do: "project:#{project_id}:roles"

  def subscribe(project_id) when is_integer(project_id) and project_id > 0 do
    Phoenix.PubSub.subscribe(Boss.PubSub, topic(project_id))
  end

  def with_project_scope(project_id, fun) when is_function(fun, 0) do
    prev = Process.get(:boss_active_project_id)
    Process.put(:boss_active_project_id, project_id)

    try do
      fun.()
    after
      if is_nil(prev),
        do: Process.delete(:boss_active_project_id),
        else: Process.put(:boss_active_project_id, prev)
    end
  end

  def with_delivery_scope(project_id, delivery_id, fun) when is_function(fun, 0) do
    prev_proj = Process.get(:boss_active_project_id)
    prev_del = Process.get(:boss_active_delivery_id)
    Process.put(:boss_active_project_id, project_id)
    Process.put(:boss_active_delivery_id, delivery_id)

    try do
      fun.()
    after
      if is_nil(prev_proj),
        do: Process.delete(:boss_active_project_id),
        else: Process.put(:boss_active_project_id, prev_proj)

      if is_nil(prev_del),
        do: Process.delete(:boss_active_delivery_id),
        else: Process.put(:boss_active_delivery_id, prev_del)
    end
  end

  def table_ready? do
    Repo.query!(
      "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='table' AND name='project_role_bindings')"
    ).rows == [[1]]
  rescue
    _ -> false
  end

  def pool_table_ready? do
    Repo.query!(
      "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='table' AND name='project_implementer_pool')"
    ).rows == [[1]]
  rescue
    _ -> false
  end

  def delivery_binding_table_ready? do
    Repo.query!(
      "SELECT EXISTS(SELECT 1 FROM sqlite_schema WHERE type='table' AND name='delivery_implementer_bindings')"
    ).rows == [[1]]
  end

  def for_project(project_id) when is_integer(project_id) and project_id > 0 do
    saved_map = saved_rows(project_id)
    roles_by_kind = Map.new(Roles.standard_list(), &{&1.kind, &1})

    Map.new(@roles, fn kind ->
      role = roles_by_kind[kind]
      choices = choices_for_kind(kind, role)
      active = resolve_active(kind, saved_map[kind], choices)
      full_choices = ensure_active_in_choices(active, choices)

      pool =
        if kind == "implementer",
          do: resolve_implementer_pool(project_id, full_choices, active),
          else: [active]

      {kind,
       %{
         kind: kind,
         name: if(role, do: role.name, else: String.capitalize(kind)),
         purpose: if(role, do: role.purpose, else: ""),
         active: active,
         choices: full_choices,
         pool: pool,
         pool_keys: MapSet.new(pool, & &1.choice_key)
       }}
    end)
  end

  def select(project_id, role_kind, choice_value)
      when is_integer(project_id) and project_id > 0 and role_kind in @roles do
    if table_ready?() do
      result =
        Repo.transaction(
          fn ->
            attrs = resolve_choice_attrs!(project_id, role_kind, choice_value)
            saved = upsert_role_binding!(project_id, role_kind, attrs)

            if role_kind == "implementer" and pool_table_ready?() do
              ensure_in_pool!(project_id, attrs, 0)
            end

            saved
          end,
          mode: :immediate
        )

      case result do
        {:ok, saved} ->
          broadcast_roles(project_id)
          {:ok, saved}

        error ->
          error
      end
    else
      {:error, :unavailable}
    end
  end

  def select(_, _, _), do: {:error, :invalid_binding}

  @doc """
  Toggles an Implementer binding inside the project's Multi-Implementer Pool.
  Always retains at least one enabled Implementer.
  """
  def toggle_implementer_pool(project_id, choice_value)
      when is_integer(project_id) and project_id > 0 and is_binary(choice_value) do
    if table_ready?() and pool_table_ready?() do
      result =
        Repo.transaction(
          fn ->
            seed_pool_from_active!(project_id)
            attrs = resolve_choice_attrs!(project_id, "implementer", choice_value)

            existing = find_pool_item(project_id, attrs)

            cond do
              not is_nil(existing) ->
                count =
                  Repo.aggregate(
                    from(p in ImplementerPoolItem, where: p.project_id == ^project_id),
                    :count
                  )

                if count <= 1 do
                  Repo.rollback(:at_least_one_implementer)
                else
                  Repo.delete!(existing)
                  sync_primary_from_pool!(project_id)
                end

              true ->
                next_pos =
                  (Repo.one(
                     from p in ImplementerPoolItem,
                       where: p.project_id == ^project_id,
                       select: max(p.position)
                   ) || -1) + 1

                ensure_in_pool!(project_id, attrs, next_pos)
                sync_primary_from_pool!(project_id)
            end
          end,
          mode: :immediate
        )

      case result do
        {:ok, ok} ->
          broadcast_roles(project_id)
          {:ok, ok}

        error ->
          error
      end
    else
      {:error, :unavailable}
    end
  end

  def toggle_implementer_pool(_, _), do: {:error, :invalid_binding}

  def enable_all_implementers(project_id) when is_integer(project_id) and project_id > 0 do
    if table_ready?() and pool_table_ready?() do
      entry = for_project(project_id)["implementer"]

      result =
        Repo.transaction(
          fn ->
            Enum.with_index(entry.choices)
            |> Enum.each(fn {choice, idx} ->
              attrs = resolve_choice_attrs!(project_id, "implementer", choice.choice_key)
              ensure_in_pool!(project_id, attrs, idx)
            end)

            sync_primary_from_pool!(project_id)
          end,
          mode: :immediate
        )

      case result do
        {:ok, ok} ->
          broadcast_roles(project_id)
          {:ok, ok}

        error ->
          error
      end
    else
      {:error, :unavailable}
    end
  end

  def implementer_pool_size(project_id) when is_integer(project_id) and project_id > 0 do
    if pool_table_ready?() do
      count =
        Repo.aggregate(
          from(p in ImplementerPoolItem, where: p.project_id == ^project_id),
          :count
        )

      max(count, 1)
    else
      1
    end
  rescue
    _ -> 1
  end

  @doc """
  Selects the least-busy Implementer binding from the project's Multi-Implementer Pool
  for `task_id` (tie-breaking deterministically across pool order by task_id).
  Returns `nil` when no explicit pool or role binding is saved for the project.
  """
  def pick_implementer_for_task(project_id, task_id)
      when is_integer(project_id) and project_id > 0 and is_integer(task_id) do
    pool = saved_pool_items(project_id)

    cond do
      pool != [] ->
        busy = active_counts_by_tag(project_id)
        len = length(pool)
        offset = rem(max(task_id - 1, 0), len)
        rotated = Enum.drop(pool, offset) ++ Enum.take(pool, offset)

        chosen =
          Enum.min_by(rotated, fn item ->
            Map.get(busy, item.binding_tag, 0)
          end)

        %{
          member_id: chosen.member_id,
          agent_id: chosen.agent_id,
          model_id: chosen.model_id,
          reasoning_effort: chosen.reasoning_effort,
          binding_tag: chosen.binding_tag,
          pool_size: len
        }

      saved = active_row(project_id, "implementer") ->
        %{
          member_id: saved.member_id,
          agent_id: saved.agent_id,
          model_id: saved.model_id,
          reasoning_effort: saved.reasoning_effort,
          binding_tag:
            Roles.binding_tag(
              "implementer",
              saved.agent_id,
              saved.model_id,
              saved.reasoning_effort
            ),
          pool_size: 1
        }

      true ->
        nil
    end
  end

  def pick_implementer_for_task(_, _), do: nil

  @doc false
  def pinned_implementer(%Delivery{} = parent) do
    if delivery_binding_table_ready?() do
      case Repo.get(ImplementerBinding, parent.id) do
        nil ->
          nil

        binding ->
          unless binding.project_id == parent.project_id and binding.task_id == parent.task_id and
                   binding.agent_id == parent.implementer,
                 do: Repo.rollback(:storage_error)

          Map.take(binding, [:member_id, :agent_id, :model_id, :reasoning_effort, :binding_tag])
      end
    end
  end

  @doc false
  def record_delivery_implementer!(%Delivery{} = delivery, %{agent_id: agent_id} = chosen) do
    if delivery_binding_table_ready?() do
      %ImplementerBinding{}
      |> ImplementerBinding.changeset(%{
        delivery_id: delivery.id,
        project_id: delivery.project_id,
        task_id: delivery.task_id,
        member_id: chosen[:member_id],
        agent_id: agent_id,
        model_id: chosen[:model_id],
        reasoning_effort: chosen[:reasoning_effort],
        binding_tag:
          chosen[:binding_tag] ||
            Roles.binding_tag(
              "implementer",
              agent_id,
              chosen[:model_id],
              chosen[:reasoning_effort]
            )
      })
      |> Repo.insert()
      |> case do
        {:ok, _} -> :ok
        {:error, _} -> Repo.rollback(:storage_error)
      end

      if Map.get(chosen, :pool_size, 1) > 1 do
        Boss.Tasks.Entries.add_comment(delivery.project_id, delivery.task_id, %{
          author_role: "analytic",
          author_agent: delivery.analytic,
          kind: "stage_log",
          stage: "dispatch",
          delivery_id: delivery.id,
          body: "Analytic dispatched task to #{chosen[:binding_tag]}."
        })
      end
    end

    :ok
  end

  def implementer_agent_maybe(project_id) do
    case saved_pool_items(project_id) do
      [%{agent_id: agent} | _] when is_binary(agent) ->
        agent

      _ ->
        case active_row(project_id, "implementer") do
          %{agent_id: agent} when is_binary(agent) -> agent
          _ -> nil
        end
    end
  end

  def analytic_agent_maybe(project_id) do
    case active_row(project_id, "analytic") do
      %{agent_id: agent} when is_binary(agent) -> agent
      _ -> nil
    end
  end

  def reviewer_agent_maybe(project_id) do
    case active_row(project_id, "reviewer") do
      %{agent_id: agent} when is_binary(agent) -> agent
      _ -> nil
    end
  end

  def reviewer_agent(project_id) when is_integer(project_id) and project_id > 0 do
    case reviewer_agent_maybe(project_id) do
      agent when is_binary(agent) ->
        agent

      _ ->
        case for_project(project_id)["reviewer"] do
          %{active: %{agent_id: id}} when is_binary(id) -> id
          _ -> "codex"
        end
    end
  end

  def selection_for(project_id, "implementer", agent_id)
      when is_integer(project_id) and project_id > 0 and is_binary(agent_id) do
    delivery_id = Process.get(:boss_active_delivery_id)

    cond do
      is_binary(delivery_id) and delivery_binding_table_ready?() ->
        case Repo.get(ImplementerBinding, delivery_id) do
          %ImplementerBinding{
            agent_id: ^agent_id,
            model_id: model_id,
            reasoning_effort: effort
          } ->
            %{model_id: model_id, reasoning_effort: effort}

          _ ->
            fallback_implementer_selection(project_id, agent_id)
        end

      true ->
        fallback_implementer_selection(project_id, agent_id)
    end
  rescue
    _ -> nil
  end

  def selection_for(project_id, role_kind, agent_id)
      when is_integer(project_id) and project_id > 0 and role_kind in @roles and
             is_binary(agent_id) do
    case active_row(project_id, role_kind) do
      %{agent_id: ^agent_id, model_id: model_id, reasoning_effort: effort} ->
        %{model_id: model_id, reasoning_effort: effort}

      _ ->
        nil
    end
  end

  def selection_for(_, _, _), do: nil

  defp fallback_implementer_selection(project_id, agent_id) do
    case Enum.find(saved_pool_items(project_id), &(&1.agent_id == agent_id)) do
      %{model_id: model_id, reasoning_effort: effort} ->
        %{model_id: model_id, reasoning_effort: effort}

      nil ->
        case active_row(project_id, "implementer") do
          %{agent_id: ^agent_id, model_id: model_id, reasoning_effort: effort} ->
            %{model_id: model_id, reasoning_effort: effort}

          _ ->
            nil
        end
    end
  end

  defp active_counts_by_tag(project_id) do
    if delivery_binding_table_ready?() do
      Repo.all(
        from b in ImplementerBinding,
          join: d in Delivery,
          on: d.id == b.delivery_id,
          where: b.project_id == ^project_id and d.status in ^@busy_statuses,
          group_by: b.binding_tag,
          select: {b.binding_tag, count(d.id)}
      )
      |> Map.new()
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp saved_pool_items(project_id) do
    if pool_table_ready?() do
      Repo.all(
        from p in ImplementerPoolItem,
          where: p.project_id == ^project_id,
          order_by: [asc: p.position, asc: p.id]
      )
    else
      []
    end
  rescue
    _ -> []
  end

  defp resolve_implementer_pool(project_id, choices, active) do
    items = saved_pool_items(project_id)

    if items == [] do
      [active]
    else
      Enum.map(items, fn item ->
        matched =
          (item.member_id && Enum.find(choices, &(&1.id == item.member_id))) ||
            Enum.find(
              choices,
              &(&1.agent_id == item.agent_id and &1.model_id == item.model_id and
                  &1.reasoning_effort == item.reasoning_effort)
            )

        matched ||
          %{
            id: item.member_id,
            choice_key:
              if(item.member_id,
                do: "member:#{item.member_id}",
                else: "agent:#{item.agent_id}"
              ),
            role_kind: "implementer",
            agent_id: item.agent_id,
            agent_name: Roles.agent_label(item.agent_id),
            model_id: item.model_id,
            model_name: item.model_id || "CLI default",
            reasoning_effort: item.reasoning_effort,
            price_label: "Saved",
            billing_label: "Saved",
            authorized: true,
            stale: true,
            tag: item.binding_tag
          }
      end)
    end
  end

  defp seed_pool_from_active!(project_id) do
    if saved_pool_items(project_id) == [] do
      entry = for_project(project_id)["implementer"]
      attrs = resolve_choice_attrs!(project_id, "implementer", entry.active.choice_key)
      ensure_in_pool!(project_id, attrs, 0)
    end
  end

  defp find_pool_item(project_id, attrs) do
    Repo.one(
      from p in ImplementerPoolItem,
        where: p.project_id == ^project_id and p.agent_id == ^attrs.agent_id,
        where:
          fragment("COALESCE(?, '__default__')", p.model_id) ==
            ^(attrs.model_id || "__default__"),
        where:
          fragment("COALESCE(?, 'default')", p.reasoning_effort) ==
            ^(attrs.reasoning_effort || "default"),
        limit: 1
    )
  end

  defp ensure_in_pool!(project_id, attrs, position) do
    tag =
      Roles.binding_tag(
        "implementer",
        attrs.agent_id,
        attrs.model_id,
        attrs.reasoning_effort
      )

    case find_pool_item(project_id, attrs) do
      nil ->
        %ImplementerPoolItem{}
        |> ImplementerPoolItem.changeset(%{
          project_id: project_id,
          member_id: attrs.member_id,
          agent_id: attrs.agent_id,
          model_id: attrs.model_id,
          reasoning_effort: attrs.reasoning_effort,
          binding_tag: tag,
          position: position
        })
        |> Repo.insert!()

      existing ->
        existing
    end
  end

  defp sync_primary_from_pool!(project_id) do
    case saved_pool_items(project_id) do
      [first | _] ->
        upsert_role_binding!(project_id, "implementer", %{
          project_id: project_id,
          role_kind: "implementer",
          member_id: first.member_id,
          agent_id: first.agent_id,
          model_id: first.model_id,
          reasoning_effort: first.reasoning_effort
        })

      [] ->
        nil
    end
  end

  defp upsert_role_binding!(project_id, role_kind, attrs) do
    case Repo.get_by(RoleBinding, project_id: project_id, role_kind: role_kind) do
      nil -> %RoleBinding{} |> RoleBinding.changeset(attrs) |> Repo.insert!()
      row -> row |> RoleBinding.changeset(attrs) |> Repo.update!()
    end
  end

  defp broadcast_roles(project_id) do
    Phoenix.PubSub.broadcast(
      Boss.PubSub,
      topic(project_id),
      {:project_roles_updated, project_id}
    )
  end

  defp active_row(project_id, role_kind) do
    if table_ready?() do
      Repo.get_by(RoleBinding, project_id: project_id, role_kind: role_kind)
    end
  rescue
    _ -> nil
  end

  defp saved_rows(project_id) do
    if table_ready?() do
      RoleBinding
      |> where([b], b.project_id == ^project_id)
      |> Repo.all()
      |> Map.new(&{&1.role_kind, &1})
    else
      %{}
    end
  rescue
    _ -> %{}
  end

  defp choices_for_kind(kind, role) do
    configured =
      if role do
        role.bindings
        |> Enum.filter(fn b -> b.authorized and Roles.runner_allowed?(kind, b.agent_id) end)
        |> Enum.map(fn b ->
          Map.merge(b, %{
            choice_key: "member:#{b.id}",
            stale: false
          })
        end)
      else
        []
      end

    if configured != [] do
      configured
    else
      fallback_choices(kind)
    end
  end

  defp fallback_choices(kind) do
    runners =
      if kind == "reviewer",
        do: Roles.reviewer_choices(),
        else: Roles.prompt_agent_choices()

    Enum.map(runners, fn a ->
      %{
        id: nil,
        choice_key: "agent:#{a.id}",
        role_kind: kind,
        agent_id: a.id,
        agent_name: a.name,
        model_id: nil,
        model_name: "CLI default",
        reasoning_effort: nil,
        price_label: "CLI default",
        billing_label: "Subscription / API",
        authorized: true,
        stale: false,
        tag: Roles.binding_tag(kind, a.id, nil, nil)
      }
    end)
  end

  defp resolve_active(kind, %RoleBinding{} = saved, choices) do
    matched =
      (saved.member_id && Enum.find(choices, &(&1.id == saved.member_id))) ||
        Enum.find(
          choices,
          &(&1.agent_id == saved.agent_id and &1.model_id == saved.model_id and
              &1.reasoning_effort == saved.reasoning_effort)
        )

    if matched do
      matched
    else
      %{
        id: saved.member_id,
        choice_key:
          if(saved.member_id,
            do: "member:#{saved.member_id}",
            else: "saved:#{saved.agent_id}:#{saved.model_id || "__default__"}"
          ),
        role_kind: kind,
        agent_id: saved.agent_id,
        agent_name: Roles.agent_label(saved.agent_id),
        model_id: saved.model_id,
        model_name: saved.model_id || "CLI default",
        reasoning_effort: saved.reasoning_effort,
        price_label: "Saved",
        billing_label: "Saved",
        authorized: true,
        stale: true,
        tag: Roles.binding_tag(kind, saved.agent_id, saved.model_id, saved.reasoning_effort)
      }
    end
  end

  defp resolve_active(kind, nil, [first | _] = choices) do
    case kind do
      "analytic" ->
        impl = Roles.implementer()
        Enum.find(choices, &(&1.agent_id != impl)) || first

      _ ->
        first
    end
  end

  defp resolve_active(kind, nil, []) do
    %{
      id: nil,
      choice_key: "agent:codex",
      role_kind: kind,
      agent_id: "codex",
      agent_name: "Codex",
      model_id: nil,
      model_name: "CLI default",
      reasoning_effort: nil,
      price_label: "CLI default",
      billing_label: "Subscription / API",
      authorized: false,
      stale: false,
      tag: Roles.binding_tag(kind, "codex", nil, nil)
    }
  end

  defp ensure_active_in_choices(active, choices) do
    if Enum.any?(choices, &(&1.choice_key == active.choice_key)) do
      choices
    else
      choices ++ [active]
    end
  end

  defp resolve_choice_attrs!(project_id, role_kind, "member:" <> raw_id) do
    with {member_id, ""} when member_id > 0 <- Integer.parse(raw_id),
         %RoleMember{} = member <- Repo.get(RoleMember, member_id),
         true <- Roles.runner_allowed?(role_kind, member.agent_id) do
      %{
        project_id: project_id,
        role_kind: role_kind,
        member_id: member.id,
        agent_id: member.agent_id,
        model_id: member.model_id,
        reasoning_effort: member.reasoning_effort
      }
    else
      _ -> Repo.rollback(:invalid_binding)
    end
  end

  defp resolve_choice_attrs!(project_id, role_kind, "agent:" <> agent_id) do
    if Roles.runner_allowed?(role_kind, agent_id) and
         agent_id in ~w(codex claude cursor opencode) do
      sel = Roles.selection_for(role_kind, agent_id, nil)

      %{
        project_id: project_id,
        role_kind: role_kind,
        member_id: nil,
        agent_id: agent_id,
        model_id: sel.model_id,
        reasoning_effort: sel.reasoning_effort
      }
    else
      Repo.rollback(:invalid_binding)
    end
  end

  defp resolve_choice_attrs!(project_id, role_kind, "saved:" <> rest) do
    case String.split(rest, ":", parts: 2) do
      [agent_id, raw_model] when agent_id in ~w(codex claude cursor opencode) ->
        model_id = if raw_model in ["", "__default__"], do: nil, else: raw_model

        %{
          project_id: project_id,
          role_kind: role_kind,
          member_id: nil,
          agent_id: agent_id,
          model_id: model_id,
          reasoning_effort: nil
        }

      _ ->
        Repo.rollback(:invalid_binding)
    end
  end

  defp resolve_choice_attrs!(_, _, _), do: Repo.rollback(:invalid_binding)

  def runner_name(agent_id),
    do: Roles.agent_label(agent_id) || Metadata.catalog() |> hd() |> Map.get(:name)
end
