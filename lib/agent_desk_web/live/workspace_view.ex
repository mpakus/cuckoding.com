defmodule AgentDeskWeb.WorkspaceView do
  @moduledoc false

  @status_tones %{
    "working" => "desk-status-working",
    "starting" => "desk-status-starting",
    "waiting" => "desk-status-waiting",
    "blocked" => "desk-status-blocked",
    "interrupted" => "desk-status-interrupted",
    "failed" => "desk-status-failed",
    "completed" => "desk-status-completed",
    "idle" => "desk-status-idle",
    "queued" => "desk-status-queued",
    "terminated" => "desk-status-terminated",
    "terminating" => "desk-status-terminating"
  }
  def provider_ready_mark(status, key) when is_map(status) do
    case status do
      %{^key => %{available: true}} -> " · ready"
      %{^key => %{available: false}} -> " · missing"
      _ -> ""
    end
  end

  def provider_ready_mark(_status, _key), do: ""
  def yesno(true), do: "yes"
  def yesno(_), do: "no"

  def session_name(sessions, id) do
    case Enum.find(sessions, &(&1.id == id)) do
      nil -> "Unknown agent"
      session -> session.display_name
    end
  end

  def tab_label(session, sessions) when is_list(sessions) do
    name = session.display_name || "Agent"
    dupes = Enum.count(sessions, &(&1.display_name == name))

    if dupes > 1 do
      "#{name} · #{String.slice(session.id, 0, 4)}"
    else
      name
    end
  end

  def worktree_for(worktrees, session_id) do
    Enum.find(worktrees || [], &(&1.agent_session_id == session_id))
  end

  def session_task(tasks, session_id) do
    Enum.find(tasks || [], &(&1.assigned_agent_id == session_id))
  end

  @terminal_task_statuses ~w(completed failed cancelled rejected)

  def task_forest(tasks) when is_list(tasks) do
    ids = MapSet.new(tasks, & &1.id)
    grouped = Enum.group_by(tasks, & &1.parent_task_id)

    tasks
    |> Enum.filter(fn task ->
      is_nil(task.parent_task_id) or not MapSet.member?(ids, task.parent_task_id)
    end)
    |> Enum.map(fn task ->
      children = grouped |> Map.get(task.id, []) |> sort_crew_children()
      %{task: task, children: children}
    end)
    |> Enum.sort_by(&forest_rank/1)
  end

  def task_forest(_), do: []

  def sidebar_task_items(tasks) do
    tasks
    |> task_forest()
    |> Enum.take(5)
    |> Enum.flat_map(fn node ->
      parent = %{
        id: node.task.id,
        task: node.task,
        class: nil,
        note: crew_progress(node.task, node.children)
      }

      children =
        Enum.map(node.children, fn child ->
          %{id: child.id, task: child, class: "pl-3", note: crew_child_note(child)}
        end)

      [parent | children]
    end)
  end

  def crew_kind(%{metadata: %{"orchestration" => %{"kind" => kind}}}) when is_binary(kind),
    do: kind

  def crew_kind(_), do: nil

  def crew_lane(%{metadata: %{"orchestration" => %{"lane" => lane}}}) when is_binary(lane),
    do: lane

  def crew_lane(_), do: nil

  def crew_progress(_parent, children) when not is_list(children) or children == [], do: nil

  def crew_progress(_parent, children) do
    lanes = Enum.filter(children, &(crew_kind(&1) == "lane"))

    if lanes == [] do
      nil
    else
      done = Enum.count(lanes, &(&1.status in @terminal_task_statuses))
      "#{done}/#{length(lanes)} lanes done#{review_progress_bit(children)}"
    end
  end

  def completable_task?(%{status: status})
      when status in ["completed", "failed", "cancelled", "rejected", "blocked"],
      do: false

  def completable_task?(_), do: true

  defp crew_child_note(task), do: crew_lane(task) || crew_kind(task)

  defp review_progress_bit(children) do
    case Enum.find(children, &(crew_kind(&1) == "review")) do
      %{status: status} when status in @terminal_task_statuses -> " · review #{status}"
      %{status: "blocked"} -> " · review waiting"
      %{status: status} -> " · review #{status}"
      _ -> ""
    end
  end

  defp sort_crew_children(children) do
    Enum.sort_by(children, fn task ->
      {crew_child_rank(crew_kind(task)), inserted_unix(task)}
    end)
  end

  defp crew_child_rank("lane"), do: 0
  defp crew_child_rank("review"), do: 1
  defp crew_child_rank(_), do: 2

  defp forest_rank(%{task: task, children: children}) do
    crew? = children != [] or crew_kind(task) == "parent"
    {if(crew?, do: 0, else: 1), -inserted_unix(task)}
  end

  defp inserted_unix(%{inserted_at: %DateTime{} = at}), do: DateTime.to_unix(at, :microsecond)
  defp inserted_unix(_), do: 0

  def session_model(%{settings: %{"model" => model}}) when is_binary(model) and model != "",
    do: model

  def session_model(%{provider_version: version}) when is_binary(version) and version != "",
    do: version

  def session_model(_session), do: nil

  def session_overlap?(previews, session_id) do
    Enum.any?(previews || [], fn {lease, overlaps} ->
      lease.agent_session_id == session_id and overlaps != []
    end)
  end

  def skill_names(skills) when is_list(skills) do
    skills
    |> Enum.map(fn
      %{"name" => name} -> name
      %{"id" => id} -> id
      name when is_binary(name) -> name
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  def skill_names(_), do: []

  def feature_names(features) when is_map(features) do
    features
    |> Enum.filter(fn {_key, value} -> truthy_feature?(value) end)
    |> Enum.map(fn {key, _value} -> to_string(key) end)
    |> Enum.sort()
  end

  def feature_names(_), do: []

  def truthy_feature?(true), do: true
  def truthy_feature?("true"), do: true
  def truthy_feature?(_), do: false

  def agent_filter_keys(agents) do
    agents
    |> Enum.flat_map(fn card -> feature_names(card.features) ++ skill_names(card.skills) end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  def visible_agents(agents, "all"), do: agents

  def visible_agents(agents, filter) when is_binary(filter) do
    Enum.filter(agents, fn card ->
      filter in feature_names(card.features) or filter in skill_names(card.skills)
    end)
  end

  def card_load_summary(card, sessions, tasks) do
    session = session_for_card(sessions, card.agent_id)
    status = (session && session.status) || card.availability
    assigned = Enum.count(tasks || [], &(&1.assigned_agent_id == card.agent_id))
    "#{status} · #{assigned} assigned"
  end

  def filter_dom_id(key) do
    key
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  def grouped_search(results) do
    results
    |> Enum.group_by(&search_group/1)
    |> Enum.sort_by(fn {group, _} -> search_group_rank(group) end)
  end

  def search_group(%{namespace: _}), do: "memory"
  def search_group(%{source: source}), do: source_group(source)
  def search_group(%{"source" => source}), do: source_group(source)
  def search_group(_), do: "other"

  def source_group("project_file"), do: "source"
  def source_group("handoff"), do: "handoffs"
  def source_group("artifact"), do: "artifacts"
  def source_group("event"), do: "history"
  def source_group(source) when source in ["docs", "documentation"], do: "docs"
  def source_group("decision"), do: "decisions"
  def source_group(_), do: "other"

  def search_group_rank("source"), do: 0
  def search_group_rank("docs"), do: 1
  def search_group_rank("decisions"), do: 2
  def search_group_rank("handoffs"), do: 3
  def search_group_rank("history"), do: 4
  def search_group_rank("artifacts"), do: 5
  def search_group_rank("memory"), do: 6
  def search_group_rank(_), do: 7

  def search_group_label("source"), do: "Source code"
  def search_group_label("docs"), do: "Project documentation"
  def search_group_label("decisions"), do: "Decisions"
  def search_group_label("handoffs"), do: "Handoffs"
  def search_group_label("history"), do: "Agent history"
  def search_group_label("artifacts"), do: "Artifacts"
  def search_group_label("memory"), do: "Memory"
  def search_group_label(_), do: "Other"

  def hit_context(hit) do
    hit[:passage] || hit["passage"] || get_in(hit, [:metadata, "path"]) || hit[:source_id]
  end

  def short_sha(nil), do: nil
  def short_sha(sha) when is_binary(sha), do: String.slice(sha, 0, 8)

  def policy_summary(%{policy_report: report}) when is_map(report) do
    failed = List.wrap(report["failed"])
    missing = List.wrap(report["missing"])

    bits =
      []
      |> maybe_join_bit(failed != [], "failed #{Enum.join(failed, ", ")}")
      |> maybe_join_bit(missing != [], "missing #{Enum.join(missing, ", ")}")

    if bits == [], do: nil, else: Enum.join(bits, " · ")
  end

  def policy_summary(_), do: nil

  def maybe_join_bit(bits, true, text), do: bits ++ [text]
  def maybe_join_bit(bits, false, _text), do: bits

  def handoff_files(artifacts, item) do
    case Enum.find(artifacts, &(&1.id == item.artifact_id)) do
      %{metadata: %{"changed_files" => files}} when is_list(files) ->
        files
        |> Enum.map(&handoff_file_name/1)
        |> Enum.reject(&is_nil/1)
        |> Enum.take(12)

      _ ->
        []
    end
  end

  def handoff_file_name(path) when is_binary(path), do: path
  def handoff_file_name(%{"path" => path}) when is_binary(path), do: path
  def handoff_file_name(%{path: path}) when is_binary(path), do: path
  def handoff_file_name(_), do: nil

  def handoff_artifact(artifacts, item), do: Enum.find(artifacts, &(&1.id == item.artifact_id))

  def handoff_commits(item, worktrees, artifacts) do
    worktree = Enum.find(worktrees, &(&1.id == item.worktree_id))
    metadata = handoff_metadata(artifacts, item)

    commits_tuple(
      first_sha(worktree && worktree.base_commit, metadata["base_commit"]),
      first_sha(item.commit_sha, worktree && worktree.head_commit, metadata["head_commit"])
    )
  end

  def handoff_metadata(artifacts, item) do
    case handoff_artifact(artifacts, item) do
      %{metadata: metadata} when is_map(metadata) -> metadata
      _ -> %{}
    end
  end

  def first_sha(a, b, c \\ nil)
  def first_sha(sha, _b, _c) when is_binary(sha), do: sha
  def first_sha(_a, sha, _c) when is_binary(sha), do: sha
  def first_sha(_a, _b, sha) when is_binary(sha), do: sha
  def first_sha(_a, _b, _c), do: nil

  def commits_tuple(base, head) when is_binary(base) or is_binary(head), do: {base, head}
  def commits_tuple(_base, _head), do: nil

  def handoff_warnings(artifacts, item) do
    case handoff_artifact(artifacts, item) do
      %{metadata: %{"warnings" => warnings}} when is_list(warnings) ->
        Enum.map(warnings, &to_string/1)

      _ ->
        []
    end
  end

  def handoff_held_leases(leases, item) do
    Enum.filter(leases, &(&1.agent_session_id == item.agent_session_id))
  end

  def handoff_checks(artifacts, item) do
    case handoff_artifact(artifacts, item) do
      %{metadata: %{"checks" => checks}} when is_list(checks) ->
        Enum.map(checks, &to_string/1)

      _ ->
        []
    end
  end

  def merge_blocked?(item, worktrees) do
    item.policy_status != "passed" or
      match?(%{status: "conflicted"}, Enum.find(worktrees, &(&1.id == item.worktree_id)))
  end

  def selected_queue_item(queue, id) when is_binary(id),
    do: Enum.find(queue, &(&1.id == id)) || List.first(queue)

  def selected_queue_item(queue, _id), do: List.first(queue)

  def default_handoff_id([item | _]), do: item.id
  def default_handoff_id(_), do: nil

  def delegations_with_status(delegations, status),
    do: Enum.filter(delegations, &(&1.status == status))

  def handoff_review_messages(messages, artifacts, item) do
    case handoff_artifact(artifacts, item) do
      %{context_id: context_id, task_id: task_id} ->
        messages
        |> Enum.filter(fn message ->
          (is_binary(context_id) and message.context_id == context_id) or
            (is_binary(task_id) and message.task_id == task_id) or
            message.kind in ["handoff", "warning", "review"]
        end)
        |> Enum.take(12)

      _ ->
        []
    end
  end

  def blocked_lease_id(previews) do
    case Enum.find(previews, fn {_lease, overlaps} -> match?([_ | _], overlaps) end) do
      {lease, _} -> lease.id
      _ -> nil
    end
  end

  def delegation_skills(%{task: %{metadata: %{"skills" => skills}}}) when is_list(skills) do
    Enum.map(skills, &to_string/1)
  end

  def delegation_skills(_), do: []

  def grouped_conversations(messages, inbox) do
    by_id = Map.new(inbox, fn delivery -> {delivery.message && delivery.message.id, delivery} end)

    items =
      Enum.map(messages, fn message ->
        conversation_item(message, Map.get(by_id, message.id))
      end)

    inbox_only =
      inbox
      |> Enum.reject(fn delivery ->
        delivery.message && Enum.any?(messages, &(&1.id == delivery.message.id))
      end)
      |> Enum.map(fn delivery -> conversation_item(delivery.message, delivery) end)
      |> Enum.reject(&is_nil/1)

    (items ++ inbox_only)
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(
      fn {_group, grouped} ->
        grouped |> Enum.map(& &1.inserted_at) |> Enum.max(DateTime)
      end,
      {:desc, DateTime}
    )
  end

  def conversation_item(nil, _delivery), do: nil

  def conversation_item(message, delivery) do
    %{
      id: message.id,
      kind: message.kind,
      scope: message.scope,
      body: message.body,
      parts: message.parts,
      correlation_id: message.correlation_id,
      reply_to_message_id: Map.get(message, :reply_to_message_id),
      delivery_state: (delivery && delivery.state) || "pending",
      inserted_at: message.inserted_at,
      group: conversation_group(message)
    }
  end

  def conversation_group(%{task_id: id}) when is_binary(id), do: {:task, id}
  def conversation_group(%{context_id: id}) when is_binary(id), do: {:context, id}
  def conversation_group(_), do: {:ungrouped, "other"}

  def conversation_label({:task, id}), do: "Task #{short_sha(id)}"
  def conversation_label({:context, id}), do: "Context #{short_sha(id)}"
  def conversation_label({:ungrouped, _}), do: "Other"

  def conversation_dom_id({kind, id}), do: "#{kind}-#{id}"

  def message_refs(%{parts: parts}) when is_list(parts) do
    Enum.flat_map(parts, fn
      %{"kind" => kind, "uri" => uri} -> ["#{kind} #{uri}"]
      %{"path" => path} -> [to_string(path)]
      %{"artifact_id" => id} -> ["artifact #{short_sha(id)}"]
      %{"name" => name} -> [to_string(name)]
      _ -> []
    end)
  end

  def message_refs(_), do: []

  def session_delivery(deliveries, session_id) do
    case Enum.find(deliveries, &(&1.agent_session_id == session_id)) do
      %{state: state} -> state
      _ -> nil
    end
  end

  def session_a2a_context(messages, session_id) do
    case Enum.find(messages, fn message ->
           message.recipient_agent_id == session_id or message.sender_agent_id == session_id
         end) do
      %{context_id: id} when is_binary(id) -> id
      _ -> nil
    end
  end

  def session_for_card(sessions, agent_id) do
    Enum.find(sessions, &(&1.id == agent_id))
  end

  def status_tone(status) when is_binary(status),
    do: Map.get(@status_tones, status, "desk-status-idle")

  def status_tone(_status), do: "desk-status-idle"
end
