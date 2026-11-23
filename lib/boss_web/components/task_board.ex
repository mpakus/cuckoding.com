defmodule BossWeb.TaskBoard do
  use BossWeb, :html

  @columns [
    {"backlog", "Backlog"},
    {"in-progress", "In Progress"},
    {"review", "Review"},
    {"needs-attention", "Needs Attention"},
    {"done", "Done"}
  ]

  attr :entries, :list, required: true
  attr :project_id, :integer, required: true
  attr :live_meta, :map, default: %{}

  def board(assigns) do
    groups = Enum.group_by(assigns.entries, &column(&1.state))
    active_total = Enum.count(assigns.entries, &active_state?(&1.state))

    assigns =
      assigns
      |> assign(
        :columns,
        Enum.map(@columns, fn {id, title} -> {id, title, Map.get(groups, id, [])} end)
      )
      |> assign(:active_total, active_total)

    ~H"""
    <div id="task-board" phx-hook="TaskBoardMotion" class="mt-6 min-w-0">
      <div class="flex flex-wrap items-center justify-between gap-2">
        <h2 id="task-board-heading" tabindex="-1" class="app-panel-heading">Tasks</h2>
        <span
          :if={@active_total > 0}
          id="task-board-live-indicator"
          role="status"
          class="inline-flex items-center gap-2 rounded-sm border border-forest bg-sage px-2.5 py-1 font-mono text-xs font-semibold text-forest"
        >
          <span class="board-live-dot" aria-hidden="true"></span>
          <span>{@active_total} active workflow{if @active_total == 1, do: "", else: "s"}</span>
        </span>
      </div>
      <div
        class="mt-4 max-w-full overflow-x-auto overscroll-x-contain pb-3 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-forest"
        tabindex="0"
        role="region"
        aria-label="Task board"
      >
        <div id="spec-entries" class="grid min-w-[73rem] grid-cols-5 gap-3">
          <section
            :for={{id, title, entries} <- @columns}
            id={"column-#{id}"}
            aria-labelledby={"heading-#{id}"}
            data-column-active={to_string(Enum.any?(entries, &active_state?(&1.state)))}
            class="board-column min-w-0 rounded-sm border border-line bg-paper p-3"
          >
            <h3
              id={"heading-#{id}"}
              class="flex items-center justify-between gap-2 border-b border-line pb-3 text-sm font-semibold"
            >
              <span>{title}</span>
              <span class="flex h-6 min-w-6 items-center justify-center rounded-full bg-surface px-1.5 text-xs font-normal tabular-nums text-muted">
                {length(entries)}
              </span>
            </h3>
            <p :if={entries == []} class="py-8 text-center text-sm text-muted">No tasks</p>
            <ul class="mt-3 space-y-3">
              <li
                :for={entry <- entries}
                id={"spec-#{entry.id}"}
                data-task-card={entry.task_id}
                data-task-state={entry.state}
                data-task-column={id}
              >
                <% meta = Map.get(@live_meta, entry.task_id, %{}) %>
                <% active? = active_state?(entry.state) %>
                <.link
                  id={"task-#{entry.task_id}"}
                  patch={~p"/projects/#{@project_id}/tasks/#{entry.task_id}"}
                  data-active={to_string(active?)}
                  class={[
                    "board-card block rounded-sm border bg-surface p-3 hover:border-control-line focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-forest",
                    if(active?, do: "border-forest shadow-xs", else: "border-line")
                  ]}
                >
                  <div class="flex items-start justify-between gap-2">
                    <h4 class="break-words text-sm font-semibold">{entry.title}</h4>
                    <span
                      :if={active?}
                      class="board-live-dot mt-1 shrink-0"
                      aria-hidden="true"
                    ></span>
                  </div>
                  <div class="mt-2 flex flex-wrap items-center gap-1.5 text-xs">
                    <span class="app-badge">{state_label(entry.state)}</span>
                    <span
                      :if={active? && active_agent_badge(entry.state, meta)}
                      class="rounded bg-sage px-2 py-0.5 font-mono text-[10px] font-semibold text-forest"
                    >
                      {active_agent_badge(entry.state, meta)}
                    </span>
                    <span
                      :if={entry.state == "new" && Map.get(meta, :dep_ready?) == true}
                      class="rounded border border-forest/40 bg-sage/60 px-1.5 py-0.5 font-mono text-[10px] font-medium text-forest"
                    >
                      Ready
                    </span>
                    <span
                      :if={entry.state == "new" && Map.get(meta, :waiting_on, []) != []}
                      class="rounded border border-line bg-paper px-1.5 py-0.5 font-mono text-[10px] text-muted"
                    >
                      Waits: {Enum.join(Map.get(meta, :waiting_on, []), ", ")}
                    </span>
                    <span
                      :if={Map.get(meta, :rework_count, 0) > 0}
                      class="rounded bg-peach/70 px-1.5 py-0.5 font-mono text-[10px] font-medium text-ink"
                    >
                      Spec refined ×{Map.get(meta, :rework_count)}
                    </span>
                    <span :if={entry.missing} class="rounded bg-warning-soft px-2 py-1 text-warning">
                      File missing
                    </span>
                  </div>
                  <div
                    :if={active?}
                    class="mt-2.5 space-y-1"
                    aria-hidden="true"
                  >
                    <div class="board-stage-track">
                      <div
                        class="board-stage-fill"
                        style={"width: #{stage_progress_pct(entry.state)}%"}
                      >
                      </div>
                    </div>
                    <p
                      :if={Map.get(meta, :cycle, 0) > 0}
                      class="font-mono text-[10px] text-muted"
                    >
                      Cycle {Map.get(meta, :cycle)} · {stage_step_caption(entry.state)}
                    </p>
                  </div>
                  <p class="mt-2.5 break-all font-mono text-xs text-muted">{entry.relative_path}</p>
                  <p class="mt-1.5 text-xs text-muted">
                    Source revision {entry.latest_revision} · Task snapshot {entry.task_revision}
                  </p>
                  <p
                    :if={entry.latest_revision != entry.task_revision}
                    class="mt-2 text-xs text-warning"
                  >
                    Source changed; the task keeps its saved snapshot.
                  </p>
                </.link>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </div>
    """
  end

  defp active_state?(state),
    do: state in ~w(planning implementing testing reviewing integrating)

  defp active_agent_badge("planning", meta),
    do: Map.get(meta, :analytic_tag) || Map.get(meta, :implementer_tag)

  defp active_agent_badge("implementing", meta), do: Map.get(meta, :implementer_tag)
  defp active_agent_badge("testing", meta), do: Map.get(meta, :implementer_tag)
  defp active_agent_badge("reviewing", meta), do: Map.get(meta, :reviewer_tag)
  defp active_agent_badge("integrating", _meta), do: "Integrating → target"
  defp active_agent_badge(_, _), do: nil

  defp stage_progress_pct("planning"), do: 22
  defp stage_progress_pct("implementing"), do: 50
  defp stage_progress_pct("testing"), do: 68
  defp stage_progress_pct("reviewing"), do: 84
  defp stage_progress_pct("integrating"), do: 95
  defp stage_progress_pct(_), do: 0

  defp stage_step_caption("planning"), do: "Analytic / Architect planning"
  defp stage_step_caption("implementing"), do: "Implementer writing code"
  defp stage_step_caption("testing"), do: "Verifying candidate"
  defp stage_step_caption("reviewing"), do: "Reviewer checking spec"
  defp stage_step_caption("integrating"), do: "Publishing verified commit"
  defp stage_step_caption(_), do: ""

  attr :entries, :list, required: true
  attr :project_id, :integer, required: true

  def references(assigns) do
    ~H"""
    <section
      :if={@entries != []}
      id="reference-history"
      aria-labelledby="reference-history-heading"
      class="mt-6 min-w-0 border-t border-line pt-5"
    >
      <h2 id="reference-history-heading" class="app-panel-heading">Reference history</h2>
      <p class="mt-2 max-w-3xl text-sm text-muted">
        These documents now provide planning context. Their original task states, source revisions and attempts remain available here.
      </p>
      <ul class="mt-3 max-h-80 space-y-2 overflow-y-auto">
        <li
          :for={entry <- @entries}
          id={"reference-#{entry.task_id}"}
          class="flex flex-wrap items-baseline gap-x-3 gap-y-1 text-sm"
        >
          <.link
            id={"task-#{entry.task_id}"}
            patch={~p"/projects/#{@project_id}/tasks/#{entry.task_id}"}
            class="min-w-0 break-words text-forest underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-forest"
          >{entry.title}</.link>
          <span class="text-muted">{state_label(entry.state)} · reference only</span>
          <span class="break-all font-mono text-xs text-muted">{entry.relative_path}</span>
        </li>
      </ul>
    </section>
    """
  end

  attr :entries, :list, required: true
  attr :project_id, :integer, required: true

  def notices(assigns) do
    ~H"""
    <div id="task-notifications" role="status">
      <ul :if={@entries != []} class="mt-4 space-y-2">
        <li
          :for={entry <- @entries}
          id={"task-notification-#{entry.task_id}"}
          class="rounded-sm border border-warning-line px-4 py-3 text-sm text-warning bg-warning-soft"
        >
          <.link
            patch={~p"/projects/#{@project_id}/tasks/#{entry.task_id}"}
            class="break-words font-semibold underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-forest"
          >
            {entry.title} · {state_label(entry.state)}
          </.link>
          <p class="mt-1 break-words">{entry.attention_reason}</p>
        </li>
      </ul>
    </div>
    """
  end

  attr :project_id, :integer, required: true
  attr :selection, :any, required: true
  attr :details, :any, default: nil
  attr :loading, :boolean, default: false
  attr :error, :any, default: nil
  attr :reference_only, :boolean, default: false
  attr :comment_draft, :string, default: ""
  attr :comment_error, :any, default: nil
  slot :source_actions
  slot :run_panel

  def drawer(assigns) do
    requested =
      case assigns.selection do
        {_, revision} -> revision
        _ -> nil
      end

    desired = requested || (assigns.details && assigns.details.pinned_revision.number)
    source_ready = assigns.details && desired == assigns.details.selected_revision.number

    return_focus =
      case assigns.selection do
        {task_id, _} -> "task-#{task_id}"
        _ -> "task-board-heading"
      end

    activity_entries =
      if assigns.details,
        do: Map.get(assigns.details, :activity_entries, []),
        else: []

    latest_activity = List.first(activity_entries)

    assigns =
      assign(assigns,
        desired: desired,
        source_ready: source_ready,
        activity_entries: activity_entries,
        latest_activity: latest_activity,
        workflow_note:
          assigns.details &&
            Map.get(assigns.details, :workflow_note, assigns.details.task.attention_reason),
        return_focus: return_focus
      )

    ~H"""
    <dialog
      id="task-drawer"
      phx-hook="TaskDrawer"
      phx-mounted={JS.ignore_attributes("open")}
      data-return-focus={@return_focus}
      data-revision={@desired}
      aria-labelledby="task-drawer-title"
      class="fixed inset-y-0 right-0 left-auto m-0 h-dvh max-h-none w-full max-w-2xl overflow-hidden border-l border-line bg-paper p-0 text-ink backdrop:bg-ink/35 open:flex open:flex-col"
    >
      <div class="flex max-h-[40dvh] shrink-0 items-start justify-between gap-4 overflow-y-auto border-b border-line bg-surface px-5 py-4 sm:px-6">
        <div class="min-w-0">
          <p class="app-eyebrow mb-2">Task details</p>
          <h2 id="task-drawer-title" class="min-w-0 break-words text-xl font-semibold">
            {if @details, do: @details.task.title, else: "Task details"}
          </h2>
        </div>
        <.link
          id="task-drawer-close"
          data-drawer-close
          patch={~p"/projects/#{@project_id}"}
          autofocus
          class="app-button-secondary shrink-0 px-3 py-2 text-sm"
        >Close</.link>
      </div>
      <div class="min-h-0 flex-1 space-y-6 overflow-y-auto px-5 py-5 sm:px-6">
        <p :if={@loading && !@source_ready} role="status" class="text-sm text-muted">
          Loading task details…
        </p>
        <p
          :if={@error}
          id="task-drawer-error"
          role="alert"
          class="rounded border border-danger-line px-3 py-2 text-sm text-danger bg-danger-soft"
        >
          {if @error == :not_found,
            do: "Task or revision not found in this project.",
            else: "Task details could not be refreshed. Try opening this task again."}
        </p>
        <div :if={@details} class="space-y-6">
          <p
            :if={@reference_only}
            id="task-reference-only"
            role="status"
            class="rounded-sm border border-line bg-sage/50 px-3 py-2 text-sm text-body"
          >
            Reference only. This document is planning context; its saved task and attempt history remain unchanged. New implementation work starts from the documentation plan.
          </p>
          <section
            id="task-current-state"
            aria-label="Current task state"
            class="space-y-2 rounded-sm border border-line bg-surface p-3.5 text-sm"
          >
            <div class="flex flex-wrap items-center justify-between gap-2">
              <span class="text-xs font-semibold uppercase tracking-wider text-muted">
                Current state
              </span>
              <div class="flex flex-wrap items-center gap-2">
                <span class="app-badge">{state_label(@details.task.state)}</span>
                <span
                  :if={@details.spec.missing}
                  class="rounded bg-warning-soft px-2 py-0.5 text-xs text-warning"
                >
                  File missing
                </span>
              </div>
            </div>
            <p :if={@latest_activity} class="text-xs leading-5 text-ink">
              <span class="font-mono font-semibold text-forest">{@latest_activity.author_tag}</span>
              · {@latest_activity.summary}
            </p>
            <p :if={is_nil(@latest_activity)} class="text-xs text-muted">
              Snapshot revision {@details.pinned_revision.number} · {length(@details.revisions)} source revision(s).
            </p>
          </section>
          <div
            :if={@workflow_note}
            id="task-attention"
            role="status"
            class="break-words rounded border border-warning-line px-3 py-2 text-sm text-warning bg-warning-soft"
          >
            <p class="font-semibold">Workflow note</p>
            <p class="mt-1">{@workflow_note}</p>
          </div>
          <dl class="grid gap-4 border-y border-line py-4 text-sm sm:grid-cols-2">
            <div>
              <dt class="text-muted">Task snapshot</dt><dd id="task-snapshot" class="mt-1">
                Revision {@details.pinned_revision.number}
              </dd><dd class="mt-1 break-all font-mono text-xs text-muted">
                {@details.pinned_revision.relative_path}
              </dd>
            </div>
            <div>
              <dt class="text-muted">Latest source</dt><dd id="task-latest-revision" class="mt-1">
                Revision {@details.latest_revision.number}
              </dd><dd class="mt-1 break-all font-mono text-xs text-muted">
                {@details.latest_revision.relative_path}
              </dd>
            </div>
          </dl>
          <p
            :if={@details.latest_revision.id != @details.pinned_revision.id}
            class="text-sm text-warning"
          >
            Source changed; the task keeps its saved snapshot.
          </p>
          <section
            id="task-activity-section"
            aria-labelledby="task-activity-heading"
            class="space-y-3 border-t border-line pt-5"
          >
            <div class="flex items-center justify-between gap-2">
              <h3 id="task-activity-heading" class="app-panel-heading">
                Comments, spec updates &amp; agent logs
              </h3>
              <span class="font-mono text-xs text-muted">{length(@activity_entries)} entries</span>
            </div>
            <form
              :if={!@reference_only}
              id="task-comment-form"
              phx-submit="add_task_comment"
              class="space-y-2 rounded-sm border border-line bg-surface p-3"
            >
              <label for="task-comment-body" class="block text-xs font-medium text-muted">
                Add note or instruction for agents
              </label>
              <textarea
                id="task-comment-body"
                name="body"
                rows="2"
                maxlength="4000"
                placeholder="Add context, acceptance clarifications, or review notes…"
                class="app-field w-full resize-y text-xs"
              >{@comment_draft}</textarea>
              <div class="flex items-center justify-between gap-2">
                <span :if={@comment_error} role="alert" class="text-xs text-danger">
                  {@comment_error}
                </span>
                <button
                  id="submit-task-comment"
                  type="submit"
                  class="app-button-secondary ml-auto px-3 py-1.5 text-xs font-semibold"
                >
                  Post note
                </button>
              </div>
            </form>
            <p :if={@activity_entries == []} class="text-xs text-muted">
              No comments or agent cycle logs yet. Agents record plan, implementation, review, diagnosis, and specification updates here automatically.
            </p>
            <ol
              :if={@activity_entries != []}
              id="task-activity-log"
              class="max-h-80 space-y-2 overflow-y-auto pr-1"
            >
              <li
                :for={entry <- @activity_entries}
                id={"task-entry-#{entry.id}"}
                class="rounded-sm border border-line bg-surface p-3 text-xs"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <div class="flex flex-wrap items-center gap-1.5">
                    <span class="rounded-sm border border-forest/30 bg-sage/60 px-1.5 py-0.5 font-mono text-[11px] font-semibold text-forest">
                      {entry.author_tag}
                    </span>
                    <span class="rounded-sm border border-line bg-paper px-1.5 py-0.5 text-[10px] font-medium text-muted">
                      {entry_kind_label(entry)}
                    </span>
                  </div>
                  <time
                    datetime={DateTime.to_iso8601(entry.inserted_at)}
                    class="font-mono text-[11px] text-muted"
                  >
                    {Calendar.strftime(entry.inserted_at, "%Y-%m-%d %H:%M UTC")}
                  </time>
                </div>
                <p class="mt-1.5 font-medium text-ink">{entry.summary}</p>
                <pre
                  :if={entry.body != "" and entry.body != entry.summary}
                  class="mt-1.5 max-h-40 overflow-y-auto whitespace-pre-wrap break-words rounded-sm border border-line/70 bg-paper p-2 font-sans text-xs leading-5 text-body"
                >{entry.body}</pre>
              </li>
            </ol>
          </section>
          {render_slot(@run_panel)}
          <section aria-labelledby="task-source-heading" class="min-w-0 border-t border-line pt-5">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <h3 id="task-source-heading" class="app-panel-heading">Source</h3>
              <form
                id="task-revision-form"
                phx-change="select_revision"
                class="flex max-w-full flex-wrap items-center gap-2"
              >
                <label for="task-revision" class="text-sm text-muted">Revision</label>
                <select
                  id="task-revision"
                  name="revision"
                  class="app-field max-w-full px-2 py-1 text-sm"
                >
                  <option
                    :for={revision <- @details.revisions}
                    value={revision.number}
                    selected={revision.number == @desired}
                  >
                    Revision {revision.number}{if revision.number == @details.pinned_revision.number,
                      do: " · task snapshot"}
                  </option>
                </select>
              </form>
            </div>
            {render_slot(@source_actions)}
            <pre
              :if={@source_ready}
              id="task-source"
              class="mt-3 max-w-full overflow-x-auto whitespace-pre-wrap break-words rounded-sm border border-line bg-surface p-4 font-mono text-sm leading-6 text-ink"
            >{@details.selected_revision.original_text}</pre>
          </section>
          <section aria-labelledby="task-events-heading" class="border-t border-line pt-5">
            <h3 id="task-events-heading" class="app-panel-heading">Recent events</h3>
            <p class="mt-1 text-xs text-muted">Latest 50 task transitions</p>
            <p :if={@details.events == []} class="mt-3 text-sm text-muted">No task events yet.</p>
            <ol id="task-events" class="mt-3 divide-y divide-line">
              <li :for={event <- @details.events} class="py-3 text-sm">
                <p>
                  Version {event.version} · {state_label(event.from_state)} → {state_label(
                    event.to_state
                  )}
                </p>
                <p :if={event.action == "adopt_revision"} class="mt-1 text-body">
                  Source revision {BossWeb.TaskRevision.number(@details, event.spec_revision_id)} → {BossWeb.TaskRevision.number(
                    @details,
                    event.target_spec_revision_id
                  )} adopted.
                </p>
                <p :if={event.reason} class="mt-1 break-words text-body">{event.reason}</p>
                <time
                  datetime={DateTime.to_iso8601(event.inserted_at)}
                  class="mt-1 block text-xs text-muted"
                >{Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC")}</time>
              </li>
            </ol>
          </section>
        </div>
      </div>
    </dialog>
    """
  end

  defp column(state) when state in ~w(new planning ready), do: "backlog"
  defp column(state) when state in ~w(implementing testing integrating), do: "in-progress"
  defp column(state) when state in ~w(reviewing approved), do: "review"
  defp column("done"), do: "done"
  defp column(_), do: "needs-attention"

  defp state_label(state) when is_binary(state),
    do: state |> String.replace("_", " ") |> String.capitalize()

  defp state_label(_), do: "Unknown"

  defp entry_kind_label(%{kind: "spec_update"}), do: "Spec update"

  defp entry_kind_label(%{kind: "comment", stage: stage}) when is_binary(stage) and stage != "",
    do: "Comment · #{stage}"

  defp entry_kind_label(%{kind: "comment"}), do: "Comment"

  defp entry_kind_label(%{cycle: c, stage: s}) when is_integer(c) and is_binary(s),
    do: "Cycle #{c} · #{s}"

  defp entry_kind_label(%{stage: s}) when is_binary(s) and s != "", do: s
  defp entry_kind_label(_), do: "Log"
end
