defmodule CuckodingWeb.ActivityComponents do
  @moduledoc "Accessible public activity timeline components."

  use CuckodingWeb, :html

  attr :events, :any, required: true
  attr :window, :list, required: true
  attr :has_older, :boolean, required: true
  attr :has_newer, :boolean, required: true
  attr :browsing, :boolean, required: true
  attr :status, :map, required: true
  attr :run_state, :string, required: true
  attr :run, :map, required: true

  def run_activity(assigns) do
    ~H"""
    <section
      aria-labelledby="activity-heading"
      class="min-w-0 space-y-4 rounded-lg border border-slate-300 bg-white p-5"
    >
      <div class="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 id="activity-heading" tabindex="-1" class="text-xl font-semibold text-slate-950">
            Recent activity
          </h2>
          <p class="mt-1 text-sm text-slate-700">
            Newest first. Scroll for older history, 30 entries at a time.
          </p>
        </div>
        <span class="rounded-full bg-slate-100 px-3 py-1 text-sm font-medium text-slate-800">
          {feed_status(@run_state, @status)}
        </span>
      </div>
      <div class="flex flex-wrap items-center justify-between gap-3">
        <p id="activity-window-status" role="status" class="text-sm text-slate-700">
          <%= if @window == [] do %>
            No activity has been recorded yet.
          <% else %>
            Showing {length(@window)} entries · #{List.last(@window)}–#{hd(@window)}
            <span :if={@browsing}> · Reading history; live updates will not move this view.</span>
          <% end %>
        </p>
        <button
          :if={@browsing}
          id="latest-activity"
          type="button"
          phx-click={JS.push("latest-activity") |> JS.focus(to: "#activity-heading")}
          class="min-h-11 rounded-md border border-slate-300 px-3 text-sm font-medium"
        >
          Show latest activity
        </button>
      </div>
      <div
        tabindex="0"
        role="region"
        aria-label="Run activity history"
        id="run-activity-scroll"
        phx-hook="ActivityHistory"
        class="max-h-[36rem] overflow-y-auto overscroll-contain rounded-lg border border-slate-200 bg-slate-50 p-3 sm:p-4"
      >
        <button
          :if={@has_newer}
          type="button"
          phx-click="newer-activity"
          phx-disable-with="Loading newer activity…"
          class="mb-3 min-h-11 rounded-md border border-slate-300 bg-white px-3 text-sm font-medium"
        >Load newer activity</button>
        <ol
          id="run-activity-events"
          phx-update="stream"
          phx-viewport-top={@has_newer && JS.push("newer-activity", page_loading: true)}
          phx-viewport-bottom={@has_older && JS.push("older-activity", page_loading: true)}
          class={["space-y-3", @has_newer && "pt-[36rem]", @has_older && "pb-[36rem]"]}
        >
          <li
            :for={{dom_id, event} <- @events}
            id={dom_id}
            class="min-w-0 rounded-md border border-slate-200 bg-white p-4"
          >
            <div class="mb-2 flex flex-wrap items-center justify-between gap-x-4 gap-y-1 text-xs text-slate-600">
              <span class="font-medium">#{event.sequence} · {run_context_label(event, @run)}</span>
              <time datetime={DateTime.to_iso8601(event.occurred_at)}>{Calendar.strftime(
                event.occurred_at,
                "%b %d, %H:%M:%S UTC"
              )}</time>
            </div>
            <p class="whitespace-pre-wrap break-words font-medium text-slate-950">
              {event.public_summary}
            </p>
            <div :if={event.metadata["rtk"]} class="mt-2 space-y-2 text-sm leading-6 text-slate-700">
              <p>{shell_result(event)}</p>
              <p>{rtk_explanation(event.metadata["rtk"]["observation"])}</p>
              <a
                href="#run-logs"
                class="inline-flex min-h-10 items-center font-medium underline underline-offset-4"
              >Read command details in the process log</a>
            </div>
            <p :if={event.sleep_gap_ms} class="mt-2 text-sm text-slate-700">
              Sleep gap: {event.sleep_gap_ms} ms
            </p>
          </li>
        </ol>
        <button
          :if={@has_older}
          id="older-activity"
          type="button"
          phx-click="older-activity"
          phx-disable-with="Loading older activity…"
          class="mt-3 min-h-11 rounded-md border border-slate-300 bg-white px-3 text-sm font-medium"
        >Load older activity</button>
        <p :if={!@has_older && @window != []} class="mt-3 text-center text-sm text-slate-600">
          Beginning of this run's history
        </p>
      </div>
    </section>
    """
  end

  defp feed_status(state, _status) when state in ~w(blocked failed),
    do: "Run stopped · history saved"

  defp feed_status(state, _status) when state in ~w(done cancelled archived),
    do: "Run finished · history saved"

  defp feed_status(state, _status) when state in ~w(paused hibernated), do: "Run paused"
  defp feed_status(_state, %{reconciling?: true}), do: "Reconciling after sleep"
  defp feed_status(_state, %{stale?: true}), do: "No recent activity reported"
  defp feed_status(_state, _status), do: "Receiving activity"

  defp run_context_label(event, run) do
    role =
      if event.correlation["role"],
        do: Cuckoding.AgentFloor.role_label(run, event.correlation["role"]),
        else: "Workflow"

    Enum.join(
      Enum.reject([role, event.correlation["runtime"], event.correlation["model"]], &is_nil/1),
      " · "
    )
  end

  defp shell_result(%{event_type: "tool.requested"}),
    do:
      "The agent asked its runtime to execute a shell command. This entry records the request, not its outcome."

  defp shell_result(%{event_type: "tool.denied"}),
    do:
      "The runtime reported that it could not complete this command. Read its process log for the reported reason."

  defp shell_result(%{metadata: %{"exit_code" => 0}}),
    do:
      "The runtime reported exit status 0 for this command. This confirms this command finished successfully, not that the whole workflow passed."

  defp shell_result(%{metadata: %{"exit_code" => code}}) when is_integer(code),
    do:
      "The runtime reported exit status #{code}. Read the process log for the command and its diagnostics; the workflow failure panel shows whether the run stopped."

  defp shell_result(%{metadata: %{"is_error" => true}}),
    do:
      "The runtime reported an error without an exit status. Read the process log for its diagnostics."

  defp shell_result(_event),
    do:
      "No exit status was saved for this entry, so its success or failure is unknown. The original command details may be available in the process log."

  defp rtk_explanation("raw_output_exception"),
    do:
      "RTK proxy was reported: output was intentionally left unfiltered for exact results. This is not a workflow error."

  defp rtk_explanation("rtk_invocation_reported"),
    do: "The command reported using RTK. Output reduction has not been measured."

  defp rtk_explanation("bypass_reported"),
    do:
      "RTK was not detected in the reported command. This is an output-filtering observation, not a workflow error."

  defp rtk_explanation(_observation),
    do: "RTK use could not be determined from this report. Output reduction remains unknown."

  attr :events, :list, required: true
  attr :status, :map, required: true
  attr :heading, :string, default: "Recent activity"
  attr :heading_id, :string, default: "activity-heading"
  attr :heading_level, :string, default: "h2", values: ["h2", "h3"]
  attr :empty_message, :string, default: "No activity has been recorded."

  def activity_stream(assigns) do
    ~H"""
    <section aria-labelledby={@heading_id} class="space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <.dynamic_tag
          tag_name={@heading_level}
          id={@heading_id}
          class="text-lg font-semibold text-slate-950"
        >
          {@heading}
        </.dynamic_tag>
        <p :if={@events != []} class="text-sm text-slate-700" aria-live="polite">
          <span :if={@status.reconciling?}>Reconciling after sleep</span>
          <span :if={!@status.reconciling? && @status.stale?}>Activity is stale</span>
          <span :if={!@status.reconciling? && !@status.stale?}>Activity is current</span>
        </p>
      </div>
      <p :if={@events == []} class="text-sm text-slate-700">{@empty_message}</p>
      <div
        :if={@events != []}
        tabindex="0"
        role="region"
        aria-label="Recent activity table"
        class="overflow-x-auto rounded-lg border border-slate-200 bg-white focus-visible:outline-2"
      >
        <table class="min-w-[40rem] w-full divide-y divide-slate-200 text-left text-sm">
          <caption class="sr-only">
            Durable public activity ordered by committed event sequence
          </caption>
          <thead class="bg-slate-50 text-slate-700">
            <tr>
              <th scope="col" class="px-4 py-3 font-semibold">Sequence</th>
              <th scope="col" class="px-4 py-3 font-semibold">Context</th>
              <th scope="col" class="px-4 py-3 font-semibold">Activity</th>
              <th scope="col" class="px-4 py-3 font-semibold">Time</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-200">
            <tr :for={event <- @events} id={"activity-#{event.id}"}>
              <td class="whitespace-nowrap px-4 py-3 font-mono text-slate-700">
                {event.sequence}
              </td>
              <td class="px-4 py-3 text-slate-700">
                <span>{context_label(event.correlation)}</span>
                <span :if={event.correlation["runtime"]}>
                  · {event.correlation["runtime"]}
                  <span :if={event.correlation["model"]}>/{event.correlation["model"]}</span>
                </span>
              </td>
              <td class="px-4 py-3 text-slate-900">
                <span class="font-medium">{event.public_summary}</span>
                <span :if={event.sleep_gap_ms} class="block text-slate-700">
                  Sleep gap: {event.sleep_gap_ms} ms
                </span>
              </td>
              <td class="whitespace-nowrap px-4 py-3 text-slate-700">
                {Calendar.strftime(event.occurred_at, "%Y-%m-%d %H:%M:%S UTC")}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp context_label(correlation) do
    cond do
      correlation["role"] -> correlation["role"]
      correlation["run_id"] -> "Run"
      correlation["task_id"] -> "Task"
      correlation["board_id"] -> "Board"
      true -> "System"
    end
  end
end
