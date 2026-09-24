defmodule CuckodingWeb.AgentFloorComponents do
  @moduledoc "Accessible Agent Floor, timeline, and resource-detail components."

  use CuckodingWeb, :html

  alias Cuckoding.AgentFloor
  alias Cuckoding.Telemetry.Accounting

  attr :groups, :list, required: true
  attr :cards, :list, required: true
  attr :group_by, :string, required: true

  def agent_floor(assigns) do
    ~H"""
    <div class="space-y-6">
      <div
        id="agent-lanes"
        class="grid gap-5 xl:grid-cols-3"
        aria-label={"Agents grouped by #{@group_by}"}
      >
        <section
          :for={{group, cards} <- @groups}
          id={"agent-lane-#{slug(group)}"}
          aria-labelledby={"agent-lane-#{slug(group)}-heading"}
          class="min-w-0 rounded-lg border border-slate-300 bg-slate-50 p-4"
        >
          <h2 id={"agent-lane-#{slug(group)}-heading"} class="font-semibold text-slate-950">
            {if @group_by == "role", do: state_label(group), else: group}
            <span class="font-normal text-slate-600">({length(cards)})</span>
          </h2>
          <div class="mt-3 space-y-3">
            <article
              :for={card <- cards}
              id={"agent-card-#{card.session.id}"}
              class="space-y-3 rounded-md border border-slate-300 bg-white p-4 shadow-sm"
            >
              <div class="flex flex-wrap items-start justify-between gap-2">
                <div>
                  <h3 class="font-medium text-slate-950">
                    {AgentFloor.role_label(card.run, card.attempt.role_key)}
                  </h3>
                  <p class="text-sm text-slate-700">{card.project.name} · {card.task.title}</p>
                </div>
                <span class={status_classes(card.attention?)}>
                  {if(card.attention?, do: "Needs attention", else: state_label(card.attempt.state))}
                </span>
              </div>

              <dl class="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
                <div>
                  <dt class="text-slate-600">Runtime</dt><dd>{card.session.adapter_key}</dd>
                </div>
                <div>
                  <dt class="text-slate-600">Model</dt><dd>{model(card.session)}</dd>
                </div>
                <div>
                  <dt class="text-slate-600">Active</dt><dd>{duration(card.attempt.active_ms)}</dd>
                </div>
                <div>
                  <dt class="text-slate-600">Wall</dt><dd>{duration(card.attempt.wall_ms)}</dd>
                </div>
              </dl>

              <p :if={card.handoff_from} class="text-sm text-slate-700">
                <span aria-hidden="true">→</span>
                Handoff from {AgentFloor.role_label(card.run, card.handoff_from)}
              </p>
              <p class="text-sm text-slate-700">
                {activity_label(card.activity)}
              </p>
              <p :if={card.resource} class="text-sm text-slate-700">
                RSS {bytes(card.resource.memory_bytes)} · {card.resource.process_count} processes
              </p>
              <p :if={card.usage} class="text-sm font-medium text-slate-900">
                {Accounting.cost_label(card.usage)}
              </p>

              <nav
                aria-label={"Controls for #{AgentFloor.role_label(card.run, card.attempt.role_key)}"}
                class="flex flex-wrap gap-2"
              >
                <.link
                  navigate={~p"/agents/#{card.session.id}"}
                  class="inline-flex min-h-10 items-center rounded-md bg-slate-950 px-3 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Inspect agent
                </.link>
                <.link
                  navigate={~p"/runs/#{card.run.id}"}
                  class="inline-flex min-h-10 items-center rounded-md border border-slate-400 px-3 font-medium text-slate-950 underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Inspect run
                </.link>
              </nav>
            </article>
          </div>
        </section>
      </div>

      <details
        phx-mounted={JS.ignore_attributes("open")}
        class="rounded-lg border border-slate-300 bg-white p-4"
      >
        <summary class="min-h-10 cursor-pointer font-semibold text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2">
          Agent table view
        </summary>
        <div
          tabindex="0"
          role="region"
          aria-label="Agent session table"
          class="mt-3 overflow-x-auto focus-visible:outline-2"
        >
          <table class="min-w-full divide-y divide-slate-200 text-left text-sm">
            <caption class="sr-only">All displayed agent sessions</caption>
            <thead>
              <tr>
                <th class="px-3 py-2">Role</th><th class="px-3 py-2">Project</th><th class="px-3 py-2">
                  Runtime/model
                </th><th class="px-3 py-2">State</th><th class="px-3 py-2">Timing</th><th class="px-3 py-2">
                  Control
                </th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-200">
              <tr :for={card <- @cards}>
                <td class="px-3 py-2">{AgentFloor.role_label(card.run, card.attempt.role_key)}</td>
                <td class="px-3 py-2">{card.project.name}</td>
                <td class="px-3 py-2">{card.session.adapter_key}/{model(card.session)}</td>
                <td class="px-3 py-2">{state_label(card.attempt.state)}</td>
                <td class="px-3 py-2">
                  {duration(card.attempt.active_ms)} active / {duration(card.attempt.wall_ms)} wall
                </td>
                <td class="px-3 py-2">
                  <.link
                    navigate={~p"/agents/#{card.session.id}"}
                    class="underline focus-visible:outline-2"
                  >Inspect</.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </details>
    </div>
    """
  end

  attr :attempts, :list, required: true

  def run_timeline(assigns) do
    ~H"""
    <section aria-labelledby="timeline-heading" class="space-y-3">
      <h2 id="timeline-heading" class="text-xl font-semibold text-slate-950">Timeline</h2>
      <p :if={@attempts == []} class="text-sm text-slate-700">No stage attempts recorded.</p>
      <ol class="space-y-3">
        <li :for={attempt <- @attempts} class="rounded-md border border-slate-300 bg-white p-4">
          <p class="font-medium text-slate-950">{attempt.stage_key} · {attempt.role_key}</p>
          <p class="text-sm text-slate-700">
            {state_label(attempt.state)} · {duration(attempt.active_ms)} active · {duration(
              attempt.wall_ms
            )} wall
          </p>
        </li>
      </ol>
    </section>
    """
  end

  attr :samples, :list, required: true

  def resource_history(assigns) do
    assigns =
      assign(
        assigns,
        :maximum_memory,
        Enum.max([1 | Enum.map(assigns.samples, & &1.memory_bytes)])
      )

    ~H"""
    <section aria-labelledby="resources-heading" class="space-y-3">
      <h2 id="resources-heading" class="text-xl font-semibold text-slate-950">Resources</h2>
      <p :if={@samples == []} class="text-sm text-slate-700">No measured resource samples.</p>
      <div
        :if={@samples != []}
        aria-label="Recent memory trend"
        class="space-y-2 rounded-lg border border-slate-300 bg-white p-4"
      >
        <div
          :for={sample <- Enum.take(@samples, -20)}
          class="grid grid-cols-[7rem_1fr] items-center gap-3 text-xs"
        >
          <span>{Calendar.strftime(sample.sampled_at, "%H:%M:%S")}</span>
          <progress
            value={sample.memory_bytes}
            max={@maximum_memory}
            aria-label={"Memory at #{Calendar.strftime(sample.sampled_at, "%H:%M:%S")}"}
            class="h-3 w-full"
          >
            {sample.memory_bytes} bytes
          </progress>
        </div>
      </div>
      <div :if={@samples != []} class="overflow-x-auto rounded-lg border border-slate-300 bg-white">
        <table class="min-w-full divide-y divide-slate-200 text-left text-sm">
          <caption class="sr-only">Measured resource sample table alternative</caption>
          <thead>
            <tr>
              <th class="px-3 py-2">Time</th><th class="px-3 py-2">CPU</th><th class="px-3 py-2">
                RSS
              </th><th class="px-3 py-2">Processes</th><th class="px-3 py-2">Ports</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-200">
            <tr :for={sample <- @samples}>
              <td class="px-3 py-2">
                {Calendar.strftime(sample.sampled_at, "%Y-%m-%d %H:%M:%S UTC")}
              </td>
              <td class="px-3 py-2">{sample.cpu_nanos} ns</td>
              <td class="px-3 py-2">{bytes(sample.memory_bytes)}</td>
              <td class="px-3 py-2">{sample.process_count}</td>
              <td class="px-3 py-2">{Enum.join(sample.open_ports_json, ", ")}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp status_classes(true),
    do:
      "rounded-full border border-amber-400 bg-amber-50 px-2 py-1 text-xs font-semibold text-amber-950"

  defp status_classes(false),
    do:
      "rounded-full border border-slate-300 bg-slate-50 px-2 py-1 text-xs font-semibold text-slate-800"

  defp activity_label(nil), do: "No recent activity"
  defp activity_label(event), do: event.public_summary
  defp model(session), do: session.actual_model || session.requested_model || "Unknown model"
  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()
  defp duration(milliseconds), do: "#{div(milliseconds || 0, 1_000)}s"
  defp bytes(value) when value < 1_024, do: "#{value} B"
  defp bytes(value) when value < 1_048_576, do: "#{div(value, 1_024)} KiB"
  defp bytes(value), do: "#{div(value, 1_048_576)} MiB"
  defp slug(value), do: value |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-")
end
