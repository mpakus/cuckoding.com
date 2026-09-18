defmodule CuckodingWeb.KnowledgeGrowthLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.KnowledgeComponents

  alias Cuckoding.Knowledge

  @refresh_ms 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)

    {:ok,
     socket
     |> assign(page_title: "Knowledge growth", notice: "")
     |> load()}
  end

  @impl true
  def handle_info(:refresh, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh, @refresh_ms)
    {:noreply, socket |> assign(notice: "Knowledge growth updated.") |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <section aria-labelledby="knowledge-growth-heading" class="space-y-8">
        <.knowledge_nav current="growth" />

        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">Reviewed memory</p>
          <h1
            id="knowledge-growth-heading"
            class="text-3xl font-semibold tracking-tight text-slate-950"
          >
            Knowledge Growth
          </h1>
          <p class="max-w-3xl text-slate-700">
            Server-side counts show what the knowledge base contains, how it changed, and how much has been used.
          </p>
        </header>

        <p role="status" aria-live="polite" class="min-h-6 text-sm text-emerald-900">{@notice}</p>

        <section aria-labelledby="coverage-heading" class="space-y-4">
          <h2 id="coverage-heading" class="text-xl font-semibold text-slate-950">Coverage</h2>
          <dl class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
            <.metric label="All items" value={@growth.coverage.total} />
            <.metric label="Used by runs" value={@growth.coverage.used} />
            <.metric label="Project scoped" value={@growth.coverage.project} />
            <.metric label="Global scoped" value={@growth.coverage.global} />
          </dl>
        </section>

        <section aria-labelledby="inventory-heading" class="space-y-4">
          <h2 id="inventory-heading" class="text-xl font-semibold text-slate-950">
            Items by kind and status
          </h2>
          <p :if={@growth.item_counts == []} class="text-sm text-slate-700">
            No knowledge items have been indexed.
          </p>
          <div :if={@growth.item_counts != []} class="overflow-x-auto">
            <table class="min-w-full border-collapse text-left text-sm">
              <caption class="sr-only">Knowledge item counts grouped by kind and status</caption>
              <thead>
                <tr class="border-b border-slate-300">
                  <th scope="col" class="p-3">Kind</th>
                  <th scope="col" class="p-3">Status</th>
                  <th scope="col" class="p-3 text-right">Items</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @growth.item_counts} class="border-b border-slate-200">
                  <th scope="row" class="p-3 font-medium text-slate-950">{row.kind}</th>
                  <td class="p-3">{row.status}</td>
                  <td class="p-3 text-right tabular-nums">{row.count}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section aria-labelledby="timeline-heading" class="space-y-4">
          <h2 id="timeline-heading" class="text-xl font-semibold text-slate-950">Items over time</h2>
          <p class="text-sm text-slate-700">Showing the latest 180 daily kind/status groups.</p>
          <p :if={@growth.timeline == []} class="text-sm text-slate-700">No timeline data yet.</p>
          <div :if={@growth.timeline != []} class="overflow-x-auto">
            <table class="min-w-full border-collapse text-left text-sm">
              <caption class="sr-only">Daily knowledge item growth by kind and status</caption>
              <thead>
                <tr class="border-b border-slate-300">
                  <th scope="col" class="p-3">Date</th>
                  <th scope="col" class="p-3">Kind</th>
                  <th scope="col" class="p-3">Status</th>
                  <th scope="col" class="p-3 text-right">Added</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @growth.timeline} class="border-b border-slate-200">
                  <th scope="row" class="p-3 font-medium text-slate-950">{row.day}</th>
                  <td class="p-3">{row.kind}</td>
                  <td class="p-3">{row.status}</td>
                  <td class="p-3 text-right tabular-nums">{row.count}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section aria-labelledby="review-coverage-heading" class="space-y-4">
          <h2 id="review-coverage-heading" class="text-xl font-semibold text-slate-950">
            Review queue coverage
          </h2>
          <p :if={@growth.review_counts == []} class="text-sm text-slate-700">
            No candidates have been extracted.
          </p>
          <ul :if={@growth.review_counts != []} class="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            <li :for={row <- @growth.review_counts} class="rounded-md border border-slate-300 p-4">
              <span class="font-medium text-slate-950">{row.kind}</span>
              <span class="block text-sm text-slate-700">{row.decision}: {row.count}</span>
            </li>
          </ul>
        </section>

        <section aria-labelledby="consolidations-heading" class="space-y-4">
          <h2 id="consolidations-heading" class="text-xl font-semibold text-slate-950">
            Consolidation history
          </h2>
          <p class="text-sm text-slate-700">Showing the latest 100 project jobs.</p>
          <p :if={@growth.consolidations == []} class="text-sm text-slate-700">
            No consolidation jobs have run.
          </p>
          <div :if={@growth.consolidations != []} class="overflow-x-auto">
            <table class="min-w-full border-collapse text-left text-sm">
              <caption class="sr-only">Recent project knowledge consolidation jobs</caption>
              <thead>
                <tr class="border-b border-slate-300">
                  <th scope="col" class="p-3">Project</th>
                  <th scope="col" class="p-3">State</th>
                  <th scope="col" class="p-3">Revision</th>
                  <th scope="col" class="p-3">Index hash</th>
                </tr>
              </thead>
              <tbody>
                <tr :for={row <- @growth.consolidations} class="border-b border-slate-200">
                  <th scope="row" class="p-3 font-medium text-slate-950">{row.project_name}</th>
                  <td class="p-3">{row.job.state}</td>
                  <td class="p-3 tabular-nums">{row.job.revision}</td>
                  <td class="max-w-48 truncate p-3 font-mono" title={row.content_hash || "Pending"}>
                    {row.content_hash || "Pending"}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>
      </section>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true

  defp metric(assigns) do
    ~H"""
    <div class="rounded-lg border border-slate-300 bg-white p-4">
      <dt class="text-sm text-slate-600">{@label}</dt>
      <dd class="text-3xl font-semibold text-slate-950">{@value}</dd>
    </div>
    """
  end

  defp load(socket), do: assign(socket, growth: Knowledge.knowledge_growth())
end
