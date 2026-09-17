defmodule CuckodingWeb.StatusLive do
  use CuckodingWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "System status",
       health: Cuckoding.Health.snapshot()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <section aria-labelledby="status-heading" class="space-y-8">
        <div class="space-y-3">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">
            Foundation status
          </p>
          <h1 id="status-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
            Cuckoding is ready
          </h1>
          <p class="max-w-2xl text-base leading-7 text-slate-700">
            The local Phoenix control plane is running. Product workflows are intentionally not enabled yet.
          </p>
        </div>

        <div class="rounded-lg border border-emerald-300 bg-emerald-50 p-5" role="status">
          <p class="font-semibold text-emerald-950">
            <span aria-hidden="true">✓</span> Application status: {status_label(@health.status)}
          </p>
          <p class="mt-1 text-sm text-emerald-900">Version {@health.application.version}</p>
        </div>

        <section aria-labelledby="dependencies-heading" class="space-y-3">
          <h2 id="dependencies-heading" class="text-xl font-semibold text-slate-950">Dependencies</h2>
          <dl class="divide-y divide-slate-200 rounded-lg border border-slate-200 bg-white">
            <div
              :for={{name, status} <- Enum.sort(@health.dependencies)}
              class="flex items-center justify-between gap-4 px-5 py-4"
            >
              <dt class="font-medium text-slate-800">{dependency_label(name)}</dt>
              <dd class="text-sm text-slate-700">{status_label(status)}</dd>
            </div>
          </dl>
        </section>

        <nav aria-label="Diagnostics" class="flex flex-wrap gap-3">
          <a
            href={~p"/health"}
            class="inline-flex min-h-10 items-center rounded-md border border-slate-300 bg-white px-4 font-medium text-slate-900 hover:bg-slate-100 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Health JSON
          </a>
          <a
            href={~p"/status"}
            class="inline-flex min-h-10 items-center rounded-md border border-slate-300 bg-white px-4 font-medium text-slate-900 hover:bg-slate-100 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Diagnostics JSON
          </a>
        </nav>
      </section>
    </Layouts.app>
    """
  end

  defp dependency_label(:pubsub), do: "Phoenix PubSub"
  defp dependency_label(:database), do: "SQLite database"
  defp dependency_label(:web_endpoint), do: "Loopback web endpoint"
  defp status_label(:ok), do: "Operational"
  defp status_label(:degraded), do: "Degraded"
  defp status_label(:unavailable), do: "Unavailable"
end
