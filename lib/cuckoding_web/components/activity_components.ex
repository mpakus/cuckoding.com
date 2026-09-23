defmodule CuckodingWeb.ActivityComponents do
  @moduledoc "Accessible public activity timeline components."

  use CuckodingWeb, :html

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
