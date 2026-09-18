defmodule CuckodingWeb.KnowledgeLineageLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.KnowledgeComponents

  alias Cuckoding.Knowledge

  @refresh_ms 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)

    {:ok,
     socket
     |> assign(page_title: "Knowledge lineage", notice: "")
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, socket |> assign(notice: "Knowledge lineage updated.") |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <section aria-labelledby="knowledge-lineage-heading" class="space-y-8">
        <.knowledge_nav current="lineage" />

        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">
            Provenance and outcomes
          </p>
          <h1
            id="knowledge-lineage-heading"
            class="text-3xl font-semibold tracking-tight text-slate-950"
          >
            Lineage and Usage
          </h1>
          <p class="max-w-3xl text-slate-700">
            Follow reviewed evidence into durable items, later runs, citations, acceptance, and contradiction.
          </p>
        </header>

        <p role="status" aria-live="polite" class="min-h-6 text-sm text-emerald-900">{@notice}</p>

        <section aria-labelledby="lineage-graph-heading" class="space-y-4">
          <div>
            <h2 id="lineage-graph-heading" class="text-xl font-semibold text-slate-950">
              Lineage graph
            </h2>
            <p class="text-sm text-slate-700">
              Showing the newest {length(@lineage.rows)} of {@lineage.total_lineages} reviewed lineages. Every node opens its durable record.
            </p>
          </div>

          <p :if={@lineage.rows == []} class="rounded-md border border-slate-300 p-5 text-slate-700">
            No reviewed lineages yet.
          </p>

          <ol :if={@lineage.rows != []} class="space-y-4" aria-label="Knowledge lineage graph">
            <li :for={row <- @lineage.rows}>
              <article class="grid items-stretch gap-2 rounded-lg border border-slate-300 bg-white p-4 lg:grid-cols-[1fr_auto_1fr_auto_1fr_auto_1fr_auto_1fr]">
                <.lineage_node
                  href={~p"/runs/#{row.source_run_id}"}
                  label="Evidence"
                  value={short_id(row.source_run_id)}
                />
                <span aria-hidden="true" class="self-center text-center text-slate-500">→</span>
                <.lineage_node
                  href={"/knowledge#candidate-#{row.candidate.id}"}
                  label="Candidate"
                  value={row.candidate.title}
                />
                <span aria-hidden="true" class="self-center text-center text-slate-500">→</span>
                <.lineage_node
                  href={"#lineage-item-#{row.item.id}"}
                  label="Item"
                  value={"#{row.item.kind} v#{row.item.version}"}
                />
                <span aria-hidden="true" class="self-center text-center text-slate-500">→</span>
                <.lineage_node href={run_href(row)} label="Runs" value={"#{length(row.runs)} linked"} />
                <span aria-hidden="true" class="self-center text-center text-slate-500">→</span>
                <.lineage_node
                  href={"#lineage-item-#{row.item.id}"}
                  label="Outcomes"
                  value={outcome_label(row)}
                />
              </article>
            </li>
          </ol>

          <div :if={@lineage.rows != []} class="overflow-x-auto">
            <table class="min-w-full border-collapse text-left text-sm">
              <caption class="sr-only">
                Accessible table alternative for the knowledge lineage graph
              </caption>
              <thead>
                <tr class="border-b border-slate-300">
                  <th scope="col" class="p-3">Evidence run</th>
                  <th scope="col" class="p-3">Candidate</th>
                  <th scope="col" class="p-3">Item</th>
                  <th scope="col" class="p-3">Using runs</th>
                  <th scope="col" class="p-3">Outcomes</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={row <- @lineage.rows}
                  id={"lineage-item-#{row.item.id}"}
                  class="border-b border-slate-200"
                >
                  <td class="p-3">
                    <.link navigate={~p"/runs/#{row.source_run_id}"} class="underline">{short_id(
                      row.source_run_id
                    )}</.link>
                  </td>
                  <td class="p-3">
                    <a href={"/knowledge#candidate-#{row.candidate.id}"} class="underline">{row.candidate.title}</a>
                  </td>
                  <th scope="row" class="p-3 font-medium text-slate-950">
                    {row.item.title}
                    <span class="block text-xs font-normal text-slate-600">
                      {row.project_name} · {row.item.scope} · {row.item.status}
                    </span>
                  </th>
                  <td class="p-3">
                    <ul class="space-y-1">
                      <li :for={usage_run <- Enum.take(row.runs, 3)}>
                        <.link navigate={~p"/runs/#{usage_run.run_id}"} class="underline">{short_id(
                          usage_run.run_id
                        )}</.link>
                      </li>
                    </ul>
                    <span :if={length(row.runs) > 3} class="text-xs text-slate-600">
                      and {length(row.runs) - 3} more
                    </span>
                  </td>
                  <td class="p-3">{outcome_label(row)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section aria-labelledby="usage-heading" class="space-y-4">
          <h2 id="usage-heading" class="text-xl font-semibold text-slate-950">Usage summary</h2>
          <p class="text-sm text-slate-700">Latest 200 used items, aggregated in SQLite.</p>
          <p :if={@lineage.usages == []} class="text-sm text-slate-700">
            No usage has been recorded.
          </p>
          <div :if={@lineage.usages != []} class="overflow-x-auto">
            <table class="min-w-full border-collapse text-left text-sm">
              <caption class="sr-only">
                Knowledge usage counts, outcomes, recency, and retrieval rank
              </caption>
              <thead>
                <tr class="border-b border-slate-300">
                  <th scope="col" class="p-3">Item</th>
                  <th scope="col" class="p-3">Injected</th>
                  <th scope="col" class="p-3">Retrieved</th>
                  <th scope="col" class="p-3">Cited</th>
                  <th scope="col" class="p-3">Acceptance</th>
                  <th scope="col" class="p-3">Contradicted</th>
                  <th scope="col" class="p-3">Last used</th>
                  <th scope="col" class="p-3">Rank</th>
                </tr>
              </thead>
              <tbody>
                <tr
                  :for={row <- @lineage.usages}
                  id={"usage-item-#{row.item.id}"}
                  class="border-b border-slate-200"
                >
                  <th scope="row" class="p-3 font-medium text-slate-950">{row.item.title}</th>
                  <td class="p-3 tabular-nums">{row.injected}</td>
                  <td class="p-3 tabular-nums">{row.retrieved}</td>
                  <td class="p-3 tabular-nums">{row.cited}</td>
                  <td class="p-3">{acceptance_rate(row)}</td>
                  <td class="p-3 tabular-nums">{row.contradicted}</td>
                  <td class="p-3">{format_time(row.last_used_at)}</td>
                  <td class="p-3 tabular-nums">{row.current_rank || "—"}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <div class="grid gap-8 lg:grid-cols-2">
          <.item_list
            id="unused-heading"
            title="Unused items"
            empty="Every item has usage."
            rows={@lineage.unused}
          />
          <section aria-labelledby="contradicted-heading" class="space-y-4">
            <h2 id="contradicted-heading" class="text-xl font-semibold text-slate-950">
              Contradicted items
            </h2>
            <p :if={@lineage.contradicted == []} class="text-sm text-slate-700">
              No contradictions recorded.
            </p>
            <ul class="divide-y divide-slate-200 rounded-lg border border-slate-300 bg-white">
              <li :for={row <- @lineage.contradicted} class="p-4">
                <p class="font-medium text-slate-950">{row.item.title}</p>
                <p class="text-sm text-slate-700">
                  {row.count} contradiction(s) · last {format_time(row.last_at)}
                </p>
              </li>
            </ul>
          </section>
        </div>

        <section aria-labelledby="skills-heading" class="space-y-4">
          <h2 id="skills-heading" class="text-xl font-semibold text-slate-950">Published skills</h2>
          <p :if={@lineage.skills == []} class="text-sm text-slate-700">No skills published.</p>
          <div :if={@lineage.skills != []} class="overflow-x-auto">
            <table class="min-w-full border-collapse text-left text-sm">
              <caption class="sr-only">Published knowledge skill packages</caption>
              <thead>
                <tr class="border-b border-slate-300">
                  <th scope="col" class="p-3">Skill</th><th scope="col" class="p-3">Version</th><th
                    scope="col"
                    class="p-3"
                  >
                    Source item
                  </th><th scope="col" class="p-3">Published</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @lineage.skills} class="border-b border-slate-200">
                  <th scope="row" class="p-3 font-medium text-slate-950">{row.skill.name}</th>
                  <td class="p-3">{row.skill.version}</td>
                  <td class="p-3">{row.item.title}</td>
                  <td class="p-3">{format_time(row.skill.published_at)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, required: true

  defp lineage_node(assigns) do
    ~H"""
    <a
      href={@href}
      class="rounded-md border border-slate-300 p-3 focus-visible:outline-2 focus-visible:outline-offset-2"
    >
      <span class="block text-xs font-semibold uppercase tracking-wide text-slate-600">{@label}</span>
      <span class="mt-1 block break-words font-medium text-slate-950">{@value}</span>
    </a>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :empty, :string, required: true
  attr :rows, :list, required: true

  defp item_list(assigns) do
    ~H"""
    <section aria-labelledby={@id} class="space-y-4">
      <h2 id={@id} class="text-xl font-semibold text-slate-950">{@title}</h2>
      <p :if={@rows == []} class="text-sm text-slate-700">{@empty}</p>
      <ul class="divide-y divide-slate-200 rounded-lg border border-slate-300 bg-white">
        <li :for={item <- @rows} class="p-4">
          <p class="font-medium text-slate-950">{item.title}</p>
          <p class="text-sm text-slate-700">{item.kind} · {item.scope} · {item.status}</p>
        </li>
      </ul>
    </section>
    """
  end

  defp load(socket), do: assign(socket, lineage: Knowledge.knowledge_lineage())

  defp outcome_label(row) do
    accepted = Map.get(row.usage_counts, "accepted", 0)
    contradicted = Map.get(row.usage_counts, "contradicted", 0)
    "#{accepted} accepted · #{contradicted} contradicted"
  end

  defp acceptance_rate(%{accepted: accepted, contradicted: contradicted}) do
    total = accepted + contradicted
    if total == 0, do: "Not rated", else: "#{round(accepted / total * 100)}%"
  end

  defp run_href(%{runs: [%{run_id: run_id} | _rest]}), do: "/runs/#{run_id}"
  defp run_href(row), do: "/runs/#{row.source_run_id}"
  defp short_id(id), do: String.slice(id, 0, 8)
  defp format_time(nil), do: "Pending"
  defp format_time(time), do: Calendar.strftime(time, "%Y-%m-%d %H:%M UTC")
end
