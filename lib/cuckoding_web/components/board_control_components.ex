defmodule CuckodingWeb.BoardControlComponents do
  @moduledoc "Accessible batch controls, progress, and complete accounting."
  use CuckodingWeb, :html

  attr :stats, :map, required: true
  attr :compact, :boolean, default: false

  def panel(assigns) do
    assigns = assign(assigns, :execution, assigns.stats.execution)
    assigns = assign(assigns, :latest_attempt, List.last(assigns.stats.attempts))
    assigns = assign(assigns, :latest_session, List.last(assigns.stats.sessions))

    assigns =
      assign(
        assigns,
        :stage_roles,
        assigns.execution.snapshot_json["workflow"]["definition"]["stages"]
        |> Enum.filter(&(&1["role_kind"] == "agent"))
        |> Enum.map(& &1["role"])
        |> Enum.uniq()
      )

    ~H"""
    <section
      id={"board-control-#{@execution.id}"}
      aria-labelledby={"board-control-heading-#{@execution.id}"}
      class="min-w-0 space-y-4 rounded-xl border border-slate-300 bg-white p-5"
    >
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h2 id={"board-control-heading-#{@execution.id}"} class="text-xl font-semibold">
          Board development
        </h2>
        <.link :if={@compact} navigate={~p"/boards/#{@execution.board_id}"} class="underline">Open board controls</.link>
        <p role="status" aria-live="polite" class="font-medium">
          {label(@execution.state)} · {label(@execution.phase)}
        </p>
      </div>
      <p :if={@execution.issue} role="alert" class="text-amber-900">{issue(@execution.issue)}</p>
      <p :if={@stats.last_event} class="text-sm text-slate-700">{@stats.last_event.public_summary}</p>
      <p class="text-sm">
        Controller decisions: {Enum.count(@stats.runs, &Cuckoding.BoardControl.controller?/1)}/{@execution.snapshot_json[
          "maximum_decisions"
        ]} maximum.
      </p>
      <p :if={@latest_session} class="text-sm">
        Latest runtime: {@latest_session.adapter_key} · requested model: {@latest_session.requested_model ||
          "unavailable"}; observed: {@latest_session.actual_model || "unavailable"}.
      </p>
      <p :if={@latest_attempt} class="text-sm">
        Stage time recorded: {duration(@latest_attempt.active_ms)} active / {duration(
          @latest_attempt.wall_ms
        )} wall; partial while active.
      </p>
      <div
        :if={!@compact}
        id={"board-stage-motion-#{@execution.id}"}
        phx-hook="TaskBoard"
        class="flex flex-wrap gap-3"
        aria-label="Workflow stage progress"
      >
        <div
          :for={role <- @stage_roles}
          class="min-h-20 min-w-32 flex-1 rounded-lg border border-slate-200 p-3"
        >
          <p class="text-sm font-medium">{role_name(role)}</p>
          <p
            :if={@latest_attempt && @latest_attempt.role_key == role}
            id={"board-stage-marker-#{@execution.id}"}
            data-task-id={@execution.id}
            data-task-state={@latest_attempt.stage_key <> ":" <> @latest_attempt.state}
            data-allowed-targets=""
            draggable="false"
            class="mt-2 rounded bg-emerald-100 px-2 py-1 text-sm"
          >
            {label(@latest_attempt.stage_key)} · {label(@latest_attempt.state)}
          </p>
        </div>
      </div>
      <dl class="flex flex-wrap gap-x-6 gap-y-2 text-sm" aria-label="Batch task totals">
        <div>
          <dt>Included</dt><dd>{@stats.included}</dd>
        </div>
        <div :for={
          {state, name} <- [
            {"pending", "Pending"},
            {"active", "Active"},
            {"done", "Completed"},
            {"blocked", "Blocked"},
            {"skipped", "Skipped"},
            {"deferred", "Deferred"}
          ]
        }>
          <dt>{name}</dt><dd>{Map.get(@stats.totals, state, 0)}</dd>
        </div>
      </dl>
      <p class="text-sm">
        Current: {task_name(@stats, @execution.current_task_id) || "Speculator controller"}.
        Next eligible: {if @stats.next, do: @stats.next.snapshot_json["title"], else: "None"}.
      </p>
      <div
        :if={!@compact and @execution.state not in ~w(done finished_with_skips stopped)}
        class="flex flex-wrap gap-2"
        aria-label="Board execution controls"
      >
        <button
          :for={action <- controls(@execution, @stats.next)}
          id={"board-#{action}"}
          type="button"
          phx-click="board-control"
          phx-value-action={action}
          phx-value-revision={@execution.revision}
          phx-disable-with="Requesting…"
          class="min-h-11 rounded-md border border-slate-400 px-4 font-medium"
        >
          {label(action)}
        </button>
      </div>
      <p :if={@execution.pending_action} class="text-sm">
        {label(@execution.pending_action)} remains pending until process suspension or cleanup is verified.
      </p>
      <details
        :if={!@compact}
        id={"board-statistics-#{@execution.id}"}
        phx-mounted={JS.ignore_attributes("open")}
        class="space-y-3"
      >
        <summary class="min-h-11 cursor-pointer font-medium">
          Statistics and evidence for every batch attempt
        </summary>
        <dl class="grid gap-3 text-sm sm:grid-cols-3">
          <div>
            <dt>Wall time (clock elapsed)</dt><dd>{duration(@stats.wall_ms)}</dd>
          </div>
          <div>
            <dt>Recorded active stage time</dt><dd>
              {duration(@stats.active_ms)} · partial while work is active
            </dd>
          </div>
          <div>
            <dt>Recorded board pause time</dt><dd>{duration(@stats.pause_ms)}</dd>
          </div>
          <div>
            <dt>Recorded machine sleep time</dt><dd>
              {duration(@stats.sleep_ms)} · may overlap pauses
            </dd>
          </div>
          <div>
            <dt>Attempts / sessions</dt><dd>{length(@stats.runs)} / {length(@stats.sessions)}</dd>
          </div>
          <div>
            <dt>Review returns</dt><dd>{@stats.review_returns}</dd>
          </div>
          <div>
            <dt>Last activity</dt><dd>
              {if @stats.last_event,
                do: DateTime.to_iso8601(@stats.last_event.occurred_at),
                else: "Unavailable"}
            </dd>
          </div>
        </dl>
        <div class="overflow-x-auto">
          <table class="w-full text-left text-sm">
            <caption class="text-left font-medium">
              Provider-reported token usage, including controller sessions and retries
            </caption>
            <thead>
              <tr>
                <th class="p-2">Dimension</th><th class="p-2">Total</th><th class="p-2">
                  Session coverage
                </th>
              </tr>
            </thead>
            <tbody>
              <tr :for={{name, measure} <- Enum.sort(@stats.tokens)}>
                <th class="p-2 font-normal">{label(name)}</th><td class="p-2">
                  {value(measure.value)}
                </td><td class="p-2">{coverage(measure)}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p :if={@stats.costs == []}>Cost unavailable.</p>
        <p :for={cost <- @stats.costs}>
          {label(cost.source)} cost: {cost.measure.value} micros {cost.currency} · {coverage(
            cost.measure
          )}
        </p>
        <p :if={!@stats.resources.available?}>
          CPU, memory, processes and port telemetry unavailable.
        </p>
        <p :if={@stats.resources.available?} class="text-sm">
          Sampled CPU: {@stats.resources.cpu_nanos} ns; peak sampled process-tree memory: {@stats.resources.peak_memory_bytes} bytes;
          current sampled memory: {value(@stats.resources.current_memory_bytes)} bytes;
          owned active process groups: {@stats.resources.processes}; observed ports: {Enum.join(
            @stats.resources.ports,
            ", "
          )}.
          Sample coverage: {@stats.resources.covered}/{@stats.resources.total} sessions; partial between samples.
          Last sample: {DateTime.to_iso8601(@stats.resources.sampled_at)}; historical observations can be stale.
        </p>
        <div class="overflow-x-auto">
          <table class="w-full text-left text-sm">
            <caption class="text-left font-medium">Fixed batch queue and outcomes</caption>
            <thead>
              <tr>
                <th class="p-2">Task</th><th class="p-2">Priority</th><th class="p-2">
                  Dependencies
                </th><th class="p-2">Outcome</th>
              </tr>
            </thead>
            <tbody>
              <tr :for={item <- @stats.items} id={"batch-item-#{item.id}"}>
                <td class="p-2">
                  <.link
                    navigate={~p"/boards/#{@execution.board_id}/tasks/#{item.task_id}"}
                    class="underline"
                  >{item.snapshot_json["title"]}</.link>
                </td>
                <td class="p-2">{item.snapshot_json["priority"]}</td><td class="p-2">
                  {Enum.map_join(
                    item.snapshot_json["dependencies"],
                    ", ",
                    &(task_name(@stats, &1) || &1)
                  )}
                </td>
                <td class="p-2">
                  {label(item.state)}{if item.reason, do: " · " <> label(item.reason)}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <ul class="space-y-2 text-sm">
          <li :for={run <- @stats.runs} id={"batch-run-#{run.id}"} class="break-words">
            <.link navigate={~p"/runs/#{run.id}"} class="underline">{if Cuckoding.BoardControl.controller?(
                                                                          run
                                                                        ),
                                                                        do: "Speculator controller",
                                                                        else:
                                                                          task_name(
                                                                            @stats,
                                                                            run.task_id
                                                                          )} · attempt {run.sequence} · {label(
              run.state
            )}</.link>
            <span class="block">Branch: {run.branch}; execution base: {run.base_sha}</span>
            <span :for={env <- Enum.filter(@stats.environments, &(&1.run_id == run.id))} class="block">Worktree: {env.worktree_path}</span>
            <.link href={~p"/runs/#{run.id}" <> "#artifacts-heading"} class="mr-3 underline">Specifications, reviews and tests</.link>
            <.link href={~p"/runs/#{run.id}" <> "#run-logs"} class="mr-3 underline">Logs</.link>
            <.link href={~p"/runs/#{run.id}" <> "#preview-heading"} class="underline">Preview</.link>
          </li>
        </ul>
        <ul class="space-y-1 text-sm" aria-label="Stage and model history">
          <li :for={session <- @stats.sessions}>
            {stage_label(@stats, session.stage_attempt_id)} · {label(session.state)} · {session.adapter_key} {session.runtime_version ||
              "version unavailable"} ·
            requested: {session.requested_model || "unavailable"}; observed: {session.actual_model ||
              "unavailable"}
          </li>
        </ul>
      </details>
    </section>
    """
  end

  def controls(%{pending_action: action}, _next) when is_binary(action), do: [action]

  def controls(e, next) do
    recovery = if e.state in ~w(paused attention), do: ~w(resume retry refresh), else: ["pause"]
    recovery ++ if(e.current_task_id || next, do: ~w(skip stop), else: ["stop"])
  end

  def issue(reason),
    do:
      label(reason) <> ". Inspect the retained evidence and use the available recovery controls."

  def label("attention"), do: "Needs attention"
  def label(value), do: value |> to_string() |> String.replace("_", " ") |> String.capitalize()
  defp role_name("spec_writer"), do: "Speculator"
  defp role_name("implementer"), do: "Implementor"
  defp role_name("reviewer"), do: "Reviewer"
  defp role_name(role), do: label(role)

  defp task_name(stats, id) do
    case Enum.find(stats.items, &(&1.task_id == id)) do
      nil -> nil
      item -> item.snapshot_json["title"]
    end
  end

  defp stage_label(stats, id) do
    attempt = Enum.find(stats.attempts, &(&1.id == id))
    run = Enum.find(stats.runs, &(&1.id == attempt.run_id))

    label(attempt.stage_key) <>
      " (" <> Cuckoding.AgentFloor.role_label(run, attempt.role_key) <> ")"
  end

  defp value(nil), do: "Unavailable"
  defp value(value), do: to_string(value)
  defp duration(nil), do: "Unavailable"
  defp duration(ms), do: "#{div(ms, 1000)}s"
  defp coverage(%{value: nil}), do: "Unavailable"

  defp coverage(m),
    do: "#{m.covered}/#{m.total} sessions" <> if(m.partial?, do: " · partial", else: "")
end
