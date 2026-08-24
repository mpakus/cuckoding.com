defmodule AgentDesk.A2A.Orchestration do
  @moduledoc """
  Lead-agent crew loop: analyze a goal, split work across specialists, review results.

  Agents still reach the hub through MCP only. SQLite tasks, delegations, messages,
  and shared memory are the durable record. This does not merge into the primary tree.
  """

  import Ecto.Query

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Graph
  alias AgentDesk.A2A.Participant
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents
  alias AgentDesk.Agents.Session
  alias AgentDesk.Clock
  alias AgentDesk.Ids
  alias AgentDesk.Providers
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Repo
  alias AgentDesk.Roles
  alias AgentDesk.Scope
  alias AgentDesk.Search
  alias AgentDesk.Search.Namespaces

  @lane_keys ~w(backend frontend tests)
  @terminal ~w(completed failed cancelled rejected)

  @spec default_lanes() :: [map()]
  def default_lanes do
    [
      %{
        "key" => "backend",
        "role" => "backend",
        "title" => "Backend",
        "description" => "Implement server, data, and API work in your isolated worktree."
      },
      %{
        "key" => "frontend",
        "role" => "frontend",
        "title" => "UI / frontend",
        "description" => "Implement UI and frontend work in your isolated worktree."
      },
      %{
        "key" => "tests",
        "role" => "tester",
        "title" => "Tests",
        "description" => "Write and run tests for the split work in your isolated worktree."
      }
    ]
  end

  @spec start_crew(Scope.t(), map()) :: {:ok, map()} | {:error, term()}
  def start_crew(%Scope{} = scope, attrs) when is_map(attrs) do
    _ = Roles.list(scope.project)

    with {:ok, goal} <- fetch_goal(attrs),
         {:ok, lead} <- resolve_lead(scope, attrs),
         {:ok, lanes} <- resolve_start_lanes(scope, lead, attrs) do
      split(Scope.for_agent(scope.project, lead), %{
        "goal" => goal,
        "lanes" => Enum.map(lanes, &lane_payload/1),
        "auto_accept" => true,
        "prompt_lead" => true
      })
    end
  end

  @spec split(Scope.t(), map()) :: {:ok, map()} | {:error, term()}
  def split(%Scope{agent_session: %Session{} = lead} = scope, attrs) when is_map(attrs) do
    _ = Roles.list(scope.project)

    with {:ok, goal} <- fetch_goal(attrs),
         {:ok, lanes} <- resolve_split_lanes(scope, attrs),
         {:ok, context} <-
           A2A.create_context(scope, %{
             title: bounded("Crew: " <> goal, 200),
             metadata: %{"orchestration" => "crew", "goal" => goal}
           }),
         :ok <- join_agents(context, [lead | Enum.map(lanes, & &1.session)]),
         {:ok, parent} <-
           A2A.create_task(scope, context, %{
             title: bounded("Crew: " <> goal, 200),
             description: goal,
             metadata: crew_meta("parent", nil, lead.id, nil)
           }),
         {:ok, children} <-
           create_children(scope, context, parent, lead, goal, lanes, auto_accept?(attrs)),
         {:ok, review} <-
           create_review_task(scope, context, parent, lead, goal, Enum.map(children, & &1.task)) do
      _ = remember_plan(scope, parent, goal, children, review)
      _ = if prompt_lead?(attrs), do: prompt_lead(lead, parent, goal, children, review), else: :ok

      {:ok, result_map(context, parent, review, lead, children)}
    end
  end

  def split(%Scope{agent_session: nil}, _attrs), do: {:error, :forbidden}

  @spec status(Scope.t(), Ecto.UUID.t()) :: {:ok, map()} | {:error, term()}
  def status(%Scope{project: project}, parent_task_id) when is_binary(parent_task_id) do
    case Repo.get_by(Task, id: parent_task_id, project_id: project.id) do
      %Task{} = parent -> {:ok, status_map(parent)}
      nil -> {:error, :not_found}
    end
  end

  @spec on_task_updated(Scope.t(), Task.t(), Task.t()) :: :ok
  def on_task_updated(%Scope{} = scope, %Task{} = previous, %Task{} = updated) do
    if updated.status in @terminal and previous.status != updated.status do
      notify_lead(scope, updated)
    else
      :ok
    end
  rescue
    _ -> :ok
  catch
    _, _ -> :ok
  end

  defp create_children(scope, context, parent, lead, goal, lanes, auto_accept?) do
    Enum.reduce_while(lanes, {:ok, []}, fn lane, {:ok, acc} ->
      case create_child(scope, context, parent, lead, goal, lane, auto_accept?) do
        {:ok, child} -> {:cont, {:ok, acc ++ [child]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_child(scope, context, parent, lead, goal, lane, auto_accept?) do
    with {:ok, task} <-
           A2A.create_task(scope, context, %{
             title: bounded(lane.title, 200),
             description: child_description(goal, lane),
             parent_task_id: parent.id,
             metadata: crew_meta("lane", lane.key, lead.id, parent.id)
           }),
         {:ok, _delegation} <- assign_lane(scope, task, lane.session, lane.title, auto_accept?) do
      _ = prompt_specialist(lane.session, task, goal, lane)

      {:ok,
       %{
         key: lane.key,
         role: lane.role,
         title: lane.title,
         session: lane.session,
         task: task
       }}
    end
  end

  defp create_review_task(scope, context, parent, lead, goal, children) do
    with {:ok, review} <-
           A2A.create_task(scope, context, %{
             title: bounded("Review: " <> goal, 200),
             description: """
             Review specialist results for: #{goal}

             Do not merge into the primary worktree. Assignment is not a lease.
             Complete this task only after every lane is acceptable.
             """,
             parent_task_id: parent.id,
             metadata: crew_meta("review", "review", lead.id, parent.id)
           }),
         :ok <- link_review_deps(scope, review, children),
         {:ok, _delegation} <- assign_lane(scope, review, lead, "Review crew results", true) do
      {:ok, Graph.hold_if_waiting(Repo.get!(Task, review.id))}
    end
  end

  defp link_review_deps(scope, review, children) do
    Enum.reduce_while(children, :ok, fn child, :ok ->
      case Graph.add_dependency(scope, review.id, child.id) do
        {:ok, _edge} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp assign_lane(scope, task, recipient, reason, auto_accept?) do
    with {:ok, delegation} <-
           A2A.propose_delegation(scope, %{
             task_id: task.id,
             to_agent_id: recipient.id,
             reason: reason,
             idempotency_key: Ids.generate()
           }) do
      if auto_accept? do
        accept_now(scope.project, recipient, delegation)
      else
        {:ok, delegation}
      end
    end
  end

  defp accept_now(project, recipient, delegation) do
    A2A.accept_delegation(Scope.for_agent(project, recipient), delegation.id, %{
      idempotency_key: Ids.generate(),
      expected_version: delegation.lock_version
    })
  end

  defp notify_lead(%Scope{} = scope, %Task{} = task) do
    meta = orchestration(task)

    cond do
      meta["kind"] != "lane" ->
        :ok

      not is_binary(meta["lead_agent_id"]) ->
        :ok

      true ->
        deliver_review(scope, task, meta)
    end
  end

  defp deliver_review(scope, task, meta) do
    with {:ok, lead} <- Agents.get_session(scope, meta["lead_agent_id"]),
         {:ok, sender} <- sender_for(scope, task) do
      body = review_notice(task, sender)

      _ =
        A2A.send_direct_message(Scope.for_agent(scope.project, sender), %{
          idempotency_key: "crew-review-#{task.id}-#{task.status}",
          context_id: task.context_id,
          task_id: task.id,
          recipient_agent_id: lead.id,
          kind: "coordination",
          body: body
        })

      _ = SessionWorker.prompt(lead.id, body)
      :ok
    else
      _ -> :ok
    end
  end

  defp sender_for(%Scope{agent_session: %Session{} = session}, _task), do: {:ok, session}

  defp sender_for(scope, %Task{assigned_agent_id: id}) when is_binary(id) do
    Agents.get_session(scope, id)
  end

  defp sender_for(_scope, _task), do: {:error, :no_sender}

  defp remember_plan(scope, parent, goal, children, review) do
    text =
      """
      Crew plan for #{goal}
      Parent task: #{parent.id}
      Review task: #{review.id}
      Lanes:
      #{Enum.map_join(children, "\n", fn child -> "- #{child.key} (#{child.role}) task #{child.task.id} -> #{child.session.display_name}" end)}
      """

    _ =
      Search.remember(scope, Namespaces.shared(scope.project.id), %{
        text: text,
        metadata: %{
          "kind" => "crew_plan",
          "parent_task_id" => parent.id,
          "review_task_id" => review.id
        }
      })

    :ok
  end

  defp prompt_lead(lead, parent, goal, children, review) do
    SessionWorker.prompt(
      lead.id,
      """
      You are the lead agent for this crew.

      Goal:
      #{goal}

      Parent task: #{parent.id}
      Review task: #{review.id}
      Specialists:
      #{Enum.map_join(children, "\n", fn child -> "- #{child.title} (#{child.role}) task #{child.task.id} assigned to #{child.session.display_name}" end)}

      Analyze the repository and this goal. Use Agent Hub tools to inspect tasks, inbox, and memory.
      If the default lanes are wrong, call hub_split_work with extra lanes. When a specialist finishes, review their artifacts and handoff. Complete the review task only when the result is acceptable.
      Remember lasting decisions with memory_remember. Do not merge into the primary worktree. Assignment is not a lease.
      """
    )
  end

  defp prompt_specialist(session, task, goal, lane) do
    SessionWorker.prompt(
      session.id,
      """
      You are the #{lane.role} specialist.

      Parent goal:
      #{goal}

      Your task: #{task.title} (#{task.id})
      #{lane.description}

      Work only in your assigned worktree. Claim leases before editing shared files. Do not merge into the primary branch.
      When finished, publish artifacts or a handoff and call hub_complete_task. The lead will review your result.
      """
    )
  end

  defp join_agents(context, sessions) do
    now = Clock.utc_now()
    existing = participant_ids(context.id)

    sessions
    |> Enum.uniq_by(& &1.id)
    |> Enum.reject(&MapSet.member?(existing, &1.id))
    |> Enum.each(fn session ->
      {:ok, _} =
        %Participant{}
        |> Participant.changeset(%{
          id: Ids.generate(),
          context_id: context.id,
          agent_session_id: session.id,
          role: "participant",
          joined_at: now
        })
        |> Repo.insert()
    end)

    :ok
  end

  defp participant_ids(context_id) do
    Participant
    |> where([p], p.context_id == ^context_id)
    |> select([p], p.agent_session_id)
    |> Repo.all()
    |> MapSet.new()
  end

  defp resolve_lead(scope, attrs) do
    session_id = string_attr(attrs, :lead_session_id, "lead_session_id")
    provider = string_attr(attrs, :provider, "provider")

    cond do
      is_binary(session_id) ->
        Agents.get_session(scope, session_id)

      session = find_by_role(scope, "lead") ->
        {:ok, session}

      spawn?(attrs) and is_binary(provider) ->
        start_agent(scope, provider, "Lead", "lead")

      true ->
        {:error, {:missing_agent, "lead"}}
    end
  end

  defp resolve_start_lanes(scope, lead, attrs) do
    provider = string_attr(attrs, :provider, "provider")
    spawn? = spawn?(attrs)

    selected_lanes(attrs)
    |> Enum.reduce_while({:ok, []}, fn spec, {:ok, acc} ->
      case resolve_specialist(scope, lead, spec, provider, spawn?) do
        {:ok, lane} -> {:cont, {:ok, acc ++ [lane]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_split_lanes(scope, attrs) do
    specs = custom_lanes(attrs) || selected_lanes(attrs)

    Enum.reduce_while(specs, {:ok, []}, fn spec, {:ok, acc} ->
      case resolve_existing_lane(scope, spec) do
        {:ok, lane} -> {:cont, {:ok, acc ++ [lane]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp resolve_specialist(scope, lead, spec, provider, spawn?) do
    recipient_id = spec["recipient_agent_id"]

    cond do
      is_binary(recipient_id) and recipient_id != lead.id ->
        with {:ok, session} <- Agents.get_session(scope, recipient_id) do
          {:ok, lane_struct(spec, session)}
        end

      session = find_by_role(scope, spec["role"]) ->
        {:ok, lane_struct(spec, session)}

      spawn? and is_binary(provider) ->
        with {:ok, session} <- start_agent(scope, provider, spec["title"], spec["role"]) do
          {:ok, lane_struct(spec, session)}
        end

      true ->
        {:error, {:missing_agent, spec["role"]}}
    end
  end

  defp resolve_existing_lane(scope, spec) do
    spec = stringify(spec)
    recipient_id = spec["recipient_agent_id"]

    cond do
      is_binary(recipient_id) ->
        with {:ok, session} <- Agents.get_session(scope, recipient_id) do
          {:ok, lane_struct(spec, session)}
        end

      session = find_by_role(scope, spec["role"]) ->
        {:ok, lane_struct(spec, session)}

      true ->
        {:error, {:missing_agent, spec["role"] || "specialist"}}
    end
  end

  defp start_agent(scope, provider, display_name, role) do
    Providers.start_session(project_scope(scope), %{
      provider: provider,
      display_name: display_name,
      role: role
    })
  end

  defp project_scope(%Scope{project: project}), do: Scope.for_project(project)

  defp find_by_role(scope, role) when is_binary(role) do
    scope
    |> Agents.list_sessions()
    |> Enum.find(fn session ->
      session.role == role and session.status not in ["terminated", "terminating", "failed"]
    end)
  end

  defp find_by_role(_scope, _role), do: nil

  defp selected_lanes(attrs) do
    keys =
      attrs
      |> Map.get(:lanes, Map.get(attrs, "lanes", @lane_keys))
      |> List.wrap()
      |> Enum.map(&lane_key/1)
      |> Enum.filter(&(&1 in @lane_keys))
      |> Enum.uniq()

    keys = if keys == [], do: @lane_keys, else: keys
    Enum.filter(default_lanes(), &(&1["key"] in keys))
  end

  defp custom_lanes(attrs) do
    raw = Map.get(attrs, :lanes) || Map.get(attrs, "lanes")

    if is_list(raw) and Enum.any?(raw, &is_map/1) do
      Enum.map(raw, &normalize_lane_spec/1)
    else
      nil
    end
  end

  defp normalize_lane_spec(spec) when is_map(spec) do
    spec = stringify(spec)
    key = spec["key"] || spec["role"] || "lane"
    role = spec["role"] || key

    %{
      "key" => to_string(key),
      "role" => to_string(role),
      "title" => spec["title"] || String.capitalize(to_string(role)),
      "description" => spec["description"] || "",
      "recipient_agent_id" => spec["recipient_agent_id"]
    }
  end

  defp lane_struct(spec, session) do
    spec = stringify(spec)

    %{
      key: spec["key"] || spec["role"],
      role: spec["role"] || spec["key"],
      title: spec["title"] || session.display_name,
      description: spec["description"] || "",
      session: session
    }
  end

  defp lane_payload(lane) do
    %{
      "key" => lane.key,
      "role" => lane.role,
      "title" => lane.title,
      "description" => lane.description,
      "recipient_agent_id" => lane.session.id
    }
  end

  defp lane_key(key) when is_binary(key), do: key
  defp lane_key(%{"key" => key}) when is_binary(key), do: key
  defp lane_key(%{key: key}) when is_binary(key), do: key
  defp lane_key(_), do: nil

  defp fetch_goal(attrs) do
    goal =
      attrs
      |> Map.get(:goal, Map.get(attrs, "goal", ""))
      |> to_string()
      |> String.trim()

    if goal == "", do: {:error, :invalid_goal}, else: {:ok, bounded(goal, 8_000)}
  end

  defp child_description(goal, lane) do
    """
    Parent goal: #{goal}

    #{lane.description}
    """
  end

  defp crew_meta(kind, lane, lead_id, parent_id) do
    %{
      "orchestration" => %{
        "kind" => kind,
        "lane" => lane,
        "lead_agent_id" => lead_id,
        "parent_task_id" => parent_id
      }
    }
  end

  defp orchestration(%Task{metadata: metadata}) when is_map(metadata) do
    metadata["orchestration"] || %{}
  end

  defp result_map(context, parent, review, lead, children) do
    %{
      "context_id" => context.id,
      "parent_task_id" => parent.id,
      "review_task_id" => review.id,
      "lead_agent_id" => lead.id,
      "lanes" =>
        Enum.map(children, fn child ->
          %{
            "key" => child.key,
            "role" => child.role,
            "task_id" => child.task.id,
            "agent_id" => child.session.id,
            "title" => child.task.title
          }
        end)
    }
  end

  defp status_map(%Task{} = parent) do
    children =
      Task
      |> where([t], t.parent_task_id == ^parent.id)
      |> order_by([t], asc: t.inserted_at)
      |> Repo.all()

    %{
      "parent_task_id" => parent.id,
      "status" => parent.status,
      "title" => parent.title,
      "tasks" =>
        Enum.map(children, fn task ->
          meta = orchestration(task)

          %{
            "id" => task.id,
            "title" => task.title,
            "status" => task.status,
            "kind" => meta["kind"],
            "lane" => meta["lane"],
            "assigned_agent_id" => task.assigned_agent_id
          }
        end)
    }
  end

  defp review_notice(task, sender) do
    {done, total, pending} = lane_counts(task)

    progress =
      cond do
        total > 0 and pending == 0 ->
          "All #{total} lanes finished. The review task is ready."

        total > 0 ->
          "#{done}/#{total} lanes finished. #{pending} still open."

        true ->
          "Review the result when the lane is acceptable."
      end

    """
    Crew update: #{sender.display_name} marked #{task.title} as #{task.status}.
    Task id: #{task.id}
    #{progress}
    Request changes or complete the review task only when the result is acceptable.
    Do not merge into the primary worktree.
    """
  end

  defp lane_counts(%Task{parent_task_id: parent_id}) when is_binary(parent_id) do
    children =
      Task
      |> where([t], t.parent_task_id == ^parent_id)
      |> Repo.all()

    lanes = Enum.filter(children, &(orchestration(&1)["kind"] == "lane"))
    total = length(lanes)
    done = Enum.count(lanes, &(&1.status in @terminal))
    {done, total, total - done}
  end

  defp lane_counts(_task), do: {0, 0, 0}

  defp auto_accept?(attrs) do
    truthy?(Map.get(attrs, :auto_accept, Map.get(attrs, "auto_accept", true)))
  end

  defp prompt_lead?(attrs) do
    truthy?(Map.get(attrs, :prompt_lead, Map.get(attrs, "prompt_lead", true)))
  end

  defp spawn?(attrs), do: truthy?(Map.get(attrs, :spawn, Map.get(attrs, "spawn", true)))

  defp truthy?(value) when value in [false, "false", "0", 0, nil], do: false
  defp truthy?(_value), do: true

  defp string_attr(attrs, atom, string) do
    case Map.get(attrs, atom) || Map.get(attrs, string) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      {key, value} -> {to_string(key), value}
    end)
  end

  defp bounded(text, max) do
    if String.length(text) > max do
      String.slice(text, 0, max - 3) <> "..."
    else
      text
    end
  end
end
