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
    <div id="task-board" phx-hook="TaskBoardMotion" class="min-w-0">
      <div class="mb-2.5 flex flex-wrap items-center justify-between gap-2">
        <div class="flex items-center gap-2">
          <h2
            id="task-board-heading"
            tabindex="-1"
            class="text-xs font-semibold uppercase tracking-wider text-muted"
          >
            Board
          </h2>
          <span class="font-mono text-xs tabular-nums text-muted">{length(@entries)}</span>
        </div>
        <span
          :if={@active_total > 0}
          id="task-board-live-indicator"
          role="status"
          class="app-badge"
        >
          <span class="board-live-dot" aria-hidden="true"></span>
          <span>{@active_total} active</span>
        </span>
      </div>

      <div
        class="relative max-w-full overflow-x-auto overscroll-x-contain pb-2"
        tabindex="0"
        role="region"
        aria-label="Task board"
      >
        <div id="spec-entries" class="grid min-w-[54rem] grid-cols-5 gap-2.5 lg:min-w-0">
          <section
            :for={{id, title, entries} <- @columns}
            id={"column-#{id}"}
            aria-labelledby={"heading-#{id}"}
            data-column-active={to_string(Enum.any?(entries, &active_state?(&1.state)))}
            class="board-column flex min-h-[26rem] min-w-0 flex-col p-2.5"
          >
            <h3
              id={"heading-#{id}"}
              class="flex items-center justify-between gap-2 border-b border-line pb-2 text-xs font-semibold text-body"
            >
              <span class="flex items-center gap-2">
                <span class={["h-2 w-2 rounded-full", column_dot_class(id)]} aria-hidden="true"></span>
                <span>{title}</span>
              </span>
              <span class="rounded-full bg-surface px-2 py-0.5 font-mono text-[11px] font-medium tabular-nums text-muted">
                {length(entries)}
              </span>
            </h3>

            <p
              :if={entries == []}
              class="flex flex-1 items-center justify-center py-8 font-mono text-xs text-muted/60"
            >
              Empty
            </p>

            <ul :if={entries != []} class="mt-2.5 space-y-2">
              <li
                :for={entry <- entries}
                id={"spec-#{entry.id}"}
                data-task-card={entry.task_id}
                data-task-state={entry.state}
                data-task-column={id}
              >
                <% meta = Map.get(@live_meta, entry.task_id, %{}) %>
                <% active? = active_state?(entry.state) %>
                <% drifted? = entry.latest_revision != entry.task_revision %>
                <.link
                  id={"task-#{entry.task_id}"}
                  patch={~p"/projects/#{@project_id}/tasks/#{entry.task_id}"}
                  data-active={to_string(active?)}
                  title={entry.relative_path}
                  class="board-card block border border-line p-2.5 no-underline"
                >
                  <div class="flex items-start justify-between gap-2">
                    <h4 class="break-words text-[13px] font-medium leading-snug text-ink">
                      {entry.title}
                    </h4>
                    <span
                      :if={active?}
                      class="board-live-dot mt-1 shrink-0"
                      aria-hidden="true"
                    ></span>
                  </div>

                  <div class="mt-2 flex flex-wrap items-center gap-1 text-[11px]">
                    <span class={card_state_pill_class(entry.state)}>
                      {state_label(entry.state)}
                    </span>

                    <span
                      :if={active? && active_agent_badge(entry.state, meta)}
                      class="max-w-full truncate rounded bg-sage px-1.5 py-0.5 font-mono text-[10px] font-medium text-forest"
                    >
                      {short_agent_badge(active_agent_badge(entry.state, meta))}
                    </span>

                    <span
                      :if={entry.state == "new" && Map.get(meta, :dep_ready?) == true}
                      class="rounded border border-forest/35 bg-sage/60 px-1.5 py-0.5 font-mono text-[10px] text-forest"
                    >
                      Ready
                    </span>

                    <span
                      :if={entry.state == "new" && Map.get(meta, :waiting_on, []) != []}
                      class="max-w-full truncate rounded border border-line bg-paper px-1.5 py-0.5 font-mono text-[10px] text-muted"
                      title={"Waiting on: #{Enum.join(Map.get(meta, :waiting_on, []), ", ")}"}
                    >
                      ⏳ {length(Map.get(meta, :waiting_on, []))} dep{if length(
                                                                          Map.get(
                                                                            meta,
                                                                            :waiting_on,
                                                                            []
                                                                          )
                                                                        ) == 1, do: "", else: "s"}
                    </span>

                    <span
                      :if={Map.get(meta, :rework_count, 0) > 0}
                      class="rounded bg-peach px-1.5 py-0.5 font-mono text-[10px] text-warning"
                    >
                      ↻{Map.get(meta, :rework_count)}
                    </span>

                    <span
                      :if={drifted?}
                      class="rounded border border-warning-line bg-warning-soft px-1.5 py-0.5 font-mono text-[10px] text-warning"
                    >
                      v{entry.task_revision}→v{entry.latest_revision}
                    </span>

                    <span
                      :if={entry.missing}
                      class="rounded border border-warning-line bg-warning-soft px-1.5 py-0.5 font-mono text-[10px] text-warning"
                    >
                      File missing
                    </span>
                  </div>

                  <div
                    :if={active?}
                    class="mt-2 space-y-1"
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

                  <span class="sr-only">
                    {entry.relative_path} · Source revision {entry.latest_revision} · Task snapshot {entry.task_revision}
                    <%= if drifted? do %>
                      Source changed; the task keeps its saved snapshot.
                    <% end %>
                  </span>
                </.link>
              </li>
            </ul>
          </section>
        </div>
      </div>
    </div>
    """
  end

  defp column_dot_class("backlog"), do: "bg-muted"
  defp column_dot_class("in-progress"), do: "bg-forest shadow-[0_0_8px_var(--color-forest)]"
  defp column_dot_class("review"), do: "bg-sky-400"
  defp column_dot_class("needs-attention"), do: "bg-warning"
  defp column_dot_class("done"), do: "bg-emerald-400"
  defp column_dot_class(_), do: "bg-muted"

  defp card_state_pill_class("done"),
    do: "rounded bg-sage px-1.5 py-0.5 font-mono text-[10px] font-medium text-forest"

  defp card_state_pill_class(s) when s in ~w(planning implementing testing reviewing integrating),
    do:
      "rounded border border-forest/40 bg-sage px-1.5 py-0.5 font-mono text-[10px] font-medium text-forest"

  defp card_state_pill_class(s) when s in ~w(blocked failed interrupted needs_input),
    do:
      "rounded border border-warning-line bg-warning-soft px-1.5 py-0.5 font-mono text-[10px] font-medium text-warning"

  defp card_state_pill_class(_),
    do: "rounded border border-line bg-paper px-1.5 py-0.5 font-mono text-[10px] text-muted"

  defp short_agent_badge(tag) when is_binary(tag) do
    case String.split(tag, ":", parts: 2) do
      [_, model] -> model
      _ -> tag
    end
  end

  defp short_agent_badge(other), do: other

  defp active_state?(state),
    do: state in ~w(planning implementing testing reviewing integrating)

  defp active_agent_badge("planning", meta),
    do: Map.get(meta, :analytic_tag) || Map.get(meta, :implementer_tag)

  defp active_agent_badge("implementing", meta), do: Map.get(meta, :implementer_tag)
  defp active_agent_badge("testing", meta), do: Map.get(meta, :implementer_tag)
  defp active_agent_badge("reviewing", meta), do: Map.get(meta, :reviewer_tag)
  defp active_agent_badge("integrating", _meta), do: "Integrating"
  defp active_agent_badge(_, _), do: nil

  defp stage_progress_pct("planning"), do: 22
  defp stage_progress_pct("implementing"), do: 50
  defp stage_progress_pct("testing"), do: 68
  defp stage_progress_pct("reviewing"), do: 84
  defp stage_progress_pct("integrating"), do: 95
  defp stage_progress_pct(_), do: 0

  defp stage_step_caption("planning"), do: "Planning"
  defp stage_step_caption("implementing"), do: "Implementing"
  defp stage_step_caption("testing"), do: "Verifying"
  defp stage_step_caption("reviewing"), do: "Reviewing"
  defp stage_step_caption("integrating"), do: "Integrating"
  defp stage_step_caption(_), do: ""

  attr :entries, :list, required: true
  attr :project_id, :integer, required: true

  def references(assigns) do
    ~H"""
    <section
      :if={@entries != []}
      id="reference-history"
      aria-labelledby="reference-history-heading"
      class="min-w-0"
    >
      <details class="rounded-lg border border-line bg-surface/60 px-3.5 py-2">
        <summary class="flex cursor-pointer items-center justify-between gap-2 text-xs text-muted hover:text-ink">
          <h2 id="reference-history-heading" class="font-medium">
            Reference history
          </h2>
          <span class="font-mono text-[11px]">{length(@entries)} archived</span>
        </summary>
        <ul class="mt-2.5 max-h-60 space-y-1.5 overflow-y-auto border-t border-line pt-2.5 text-xs">
          <li
            :for={entry <- @entries}
            id={"reference-#{entry.task_id}"}
            class="flex flex-wrap items-baseline justify-between gap-2"
          >
            <.link
              id={"task-#{entry.task_id}"}
              patch={~p"/projects/#{@project_id}/tasks/#{entry.task_id}"}
              class="min-w-0 break-words text-forest hover:underline"
            >{entry.title}</.link>
            <span class="font-mono text-[11px] text-muted">
              {state_label(entry.state)} · reference only · {entry.relative_path}
            </span>
          </li>
        </ul>
      </details>
    </section>
    """
  end

  attr :entries, :list, required: true
  attr :project_id, :integer, required: true

  def notices(assigns) do
    ~H"""
    <div id="task-notifications" role="status" class={[@entries == [] && "sr-only"]}>
      <ul :if={@entries != []} class="space-y-1.5">
        <li
          :for={entry <- @entries}
          id={"task-notification-#{entry.task_id}"}
          class="flex flex-wrap items-baseline justify-between gap-2 rounded-lg border border-warning-line bg-warning-soft px-3.5 py-2 text-xs text-warning"
        >
          <.link
            patch={~p"/projects/#{@project_id}/tasks/#{entry.task_id}"}
            class="break-words font-semibold hover:underline"
          >
            {entry.title} · {state_label(entry.state)}
          </.link>
          <p class="min-w-0 break-words text-body">{entry.attention_reason}</p>
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
  attr :advanced_open, :boolean, default: false
  slot :dependencies
  slot :source_actions
  slot :delivery_panel
  slot :manual_panel

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
      class="fixed inset-y-0 right-0 left-auto m-0 h-dvh max-h-none w-full max-w-2xl overflow-hidden p-0 text-ink open:flex open:flex-col"
    >
      <div class="flex shrink-0 items-start justify-between gap-4 border-b border-line bg-surface px-5 py-3.5">
        <div class="min-w-0 space-y-1">
          <div :if={@details} class="flex flex-wrap items-center gap-1.5">
            <span class={card_state_pill_class(@details.task.state)}>
              {state_label(@details.task.state)}
            </span>
            <span class="font-mono text-[11px] text-muted">
              {@details.pinned_revision.relative_path}
            </span>
            <span
              :if={@details.spec.missing}
              class="rounded border border-warning-line bg-warning-soft px-1.5 py-0.5 font-mono text-[10px] text-warning"
            >
              File missing
            </span>
          </div>
          <h2 id="task-drawer-title" class="min-w-0 break-words text-base font-semibold text-ink">
            {if @details, do: @details.task.title, else: "Task details"}
          </h2>
        </div>
        <.link
          id="task-drawer-close"
          data-drawer-close
          patch={~p"/projects/#{@project_id}"}
          autofocus
          class="app-button-secondary shrink-0 px-3 py-1.5 text-xs"
        >Close</.link>
      </div>

      <div class="min-h-0 flex-1 space-y-5 overflow-y-auto px-5 py-4">
        <p :if={@loading && !@source_ready} role="status" class="text-xs text-muted">
          Loading task details…
        </p>

        <p
          :if={@error}
          id="task-drawer-error"
          role="alert"
          class="rounded-md border border-danger-line bg-danger-soft px-3 py-2 text-xs text-danger"
        >
          {if @error == :not_found,
            do: "Task or revision not found in this project.",
            else: "Task details could not be refreshed. Try opening this task again."}
        </p>

        <div :if={@details} class="space-y-5">
          <p
            :if={@reference_only}
            id="task-reference-only"
            role="status"
            class="rounded-md border border-line bg-sage/60 px-3 py-2 text-xs text-body"
          >
            Reference only. This document is planning context; its saved task and attempt history remain unchanged.
          </p>

          <section
            id="task-current-state"
            aria-label="Current task state"
            class="flex flex-wrap items-center justify-between gap-2 rounded-lg border border-line bg-surface px-3.5 py-2.5 text-xs"
          >
            <div class="min-w-0">
              <p :if={@latest_activity} class="truncate text-body">
                <span class="font-mono font-semibold text-forest">{@latest_activity.author_tag}</span>
                · {@latest_activity.summary}
              </p>
              <p :if={is_nil(@latest_activity)} class="font-mono text-muted">
                Snapshot v{@details.pinned_revision.number} · Latest v{@details.latest_revision.number}
              </p>
            </div>
            <span
              :if={@details.latest_revision.id != @details.pinned_revision.id}
              class="rounded border border-warning-line bg-warning-soft px-2 py-0.5 font-mono text-[10px] text-warning"
            >
              Source changed; the task keeps its saved snapshot.
            </span>
          </section>

          <div
            :if={@workflow_note}
            id="task-attention"
            role="status"
            class="break-words rounded-lg border border-warning-line bg-warning-soft px-3.5 py-2.5 text-xs text-warning"
          >
            <p class="font-semibold">Attention</p>
            <p class="mt-0.5 text-body">{@workflow_note}</p>
          </div>

          {render_slot(@dependencies)}

          {render_slot(@delivery_panel)}

          <section
            id="task-activity-section"
            aria-labelledby="task-activity-heading"
            class="space-y-2.5 border-t border-line pt-4"
          >
            <div class="flex items-center justify-between gap-2">
              <h3 id="task-activity-heading" class="app-panel-heading">
                Activity &amp; notes
              </h3>
              <span class="font-mono text-[11px] text-muted">{length(@activity_entries)}</span>
            </div>

            <form
              :if={!@reference_only}
              id="task-comment-form"
              phx-submit="add_task_comment"
              class="flex flex-col gap-2 rounded-lg border border-line bg-surface p-2.5"
            >
              <label for="task-comment-body" class="sr-only">
                Add note or instruction for agents
              </label>
              <textarea
                id="task-comment-body"
                name="body"
                rows="2"
                maxlength="4000"
                placeholder="Leave a note or clarification for Analytic / Implementer / Reviewer…"
                class="app-field w-full resize-y text-xs"
              >{@comment_draft}</textarea>
              <div class="flex items-center justify-between gap-2">
                <span :if={@comment_error} role="alert" class="text-xs text-danger">
                  {@comment_error}
                </span>
                <button
                  id="submit-task-comment"
                  type="submit"
                  class="app-button-secondary ml-auto min-h-7 px-3 py-1 text-xs"
                >
                  Post note
                </button>
              </div>
            </form>

            <ol
              :if={@activity_entries != []}
              id="task-activity-log"
              class="max-h-64 space-y-2 overflow-y-auto pr-1"
            >
              <li
                :for={entry <- @activity_entries}
                id={"task-entry-#{entry.id}"}
                class="rounded-lg border border-line bg-surface p-2.5 text-xs"
              >
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <div class="flex flex-wrap items-center gap-1.5">
                    <span class="rounded bg-sage px-1.5 py-0.5 font-mono text-[10px] font-semibold text-forest">
                      {entry.author_tag}
                    </span>
                    <span class="rounded border border-line bg-paper px-1.5 py-0.5 font-mono text-[10px] text-muted">
                      {entry_kind_label(entry)}
                    </span>
                  </div>
                  <time
                    datetime={DateTime.to_iso8601(entry.inserted_at)}
                    class="font-mono text-[10px] text-muted"
                  >
                    {Calendar.strftime(entry.inserted_at, "%H:%M UTC")}
                  </time>
                </div>
                <p class="mt-1.5 font-medium text-ink">{entry.summary}</p>
                <pre
                  :if={entry.body != "" and entry.body != entry.summary}
                  class="mt-1.5 max-h-36 overflow-y-auto whitespace-pre-wrap break-words rounded border border-line bg-paper p-2 font-sans text-xs leading-5 text-body"
                >{entry.body}</pre>
              </li>
            </ol>
          </section>

          <section aria-labelledby="task-source-heading" class="min-w-0 border-t border-line pt-4">
            <div class="flex flex-wrap items-center justify-between gap-2">
              <h3 id="task-source-heading" class="app-panel-heading">Specification</h3>
              <form
                id="task-revision-form"
                phx-change="select_revision"
                class="flex items-center gap-2"
              >
                <label for="task-revision" class="sr-only">Revision</label>
                <select
                  id="task-revision"
                  name="revision"
                  class="app-field min-h-8 px-2.5 py-1 font-mono text-xs"
                >
                  <option
                    :for={revision <- @details.revisions}
                    value={revision.number}
                    selected={revision.number == @desired}
                  >
                    v{revision.number}{if revision.number == @details.pinned_revision.number,
                      do: " · pinned"}
                  </option>
                </select>
              </form>
            </div>

            {render_slot(@source_actions)}

            <pre
              :if={@source_ready}
              id="task-source"
              class="mt-2.5 max-w-full overflow-x-auto whitespace-pre-wrap break-words rounded-lg border border-line bg-paper p-3.5 font-mono text-xs leading-5 text-body"
            >{@details.selected_revision.original_text}</pre>
          </section>

          <details
            id="task-advanced-diagnostics"
            open={@advanced_open}
            class="rounded-lg border border-line bg-surface/60 p-3"
          >
            <summary class="flex cursor-pointer items-center justify-between text-xs font-medium text-muted hover:text-ink">
              <span>Advanced &amp; manual diagnostics</span>
              <span class="font-mono text-[10px]">runs · revisions · events</span>
            </summary>

            <div class="mt-3 space-y-4 border-t border-line pt-3">
              <dl class="grid gap-3 rounded-md border border-line bg-paper p-2.5 font-mono text-xs sm:grid-cols-2">
                <div>
                  <dt class="text-[10px] uppercase text-muted">Task snapshot</dt>
                  <dd id="task-snapshot" class="mt-0.5 text-ink">
                    Revision {@details.pinned_revision.number}
                  </dd>
                  <dd class="truncate text-[11px] text-muted">
                    {@details.pinned_revision.relative_path}
                  </dd>
                </div>
                <div>
                  <dt class="text-[10px] uppercase text-muted">Latest source</dt>
                  <dd id="task-latest-revision" class="mt-0.5 text-ink">
                    Revision {@details.latest_revision.number}
                  </dd>
                  <dd class="truncate text-[11px] text-muted">
                    {@details.latest_revision.relative_path}
                  </dd>
                </div>
              </dl>

              {render_slot(@manual_panel)}

              <section aria-labelledby="task-events-heading" class="border-t border-line pt-3">
                <h3 id="task-events-heading" class="text-xs font-semibold text-body">
                  State transition log
                </h3>
                <p :if={@details.events == []} class="mt-1.5 text-xs text-muted">
                  No task events yet.
                </p>
                <ol
                  id="task-events"
                  class="mt-2 max-h-48 divide-y divide-line overflow-y-auto text-xs"
                >
                  <li :for={event <- @details.events} class="py-2">
                    <div class="flex flex-wrap items-center justify-between gap-2">
                      <span class="font-mono text-ink">
                        v{event.version} · {state_label(event.from_state)} → {state_label(
                          event.to_state
                        )}
                      </span>
                      <time
                        datetime={DateTime.to_iso8601(event.inserted_at)}
                        class="font-mono text-[10px] text-muted"
                      >
                        {Calendar.strftime(event.inserted_at, "%Y-%m-%d %H:%M UTC")}
                      </time>
                    </div>
                    <p :if={event.action == "adopt_revision"} class="mt-0.5 text-muted">
                      Source revision {BossWeb.TaskRevision.number(@details, event.spec_revision_id)} → {BossWeb.TaskRevision.number(
                        @details,
                        event.target_spec_revision_id
                      )} adopted.
                    </p>
                    <p :if={event.reason} class="mt-0.5 break-words text-body">{event.reason}</p>
                  </li>
                </ol>
              </section>
            </div>
          </details>
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
