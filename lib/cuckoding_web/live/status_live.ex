defmodule CuckodingWeb.StatusLive do
  use CuckodingWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "System status",
       health: Cuckoding.Health.snapshot(),
       experimental_runtimes: Cuckoding.Adapters.Catalog.experimental_options(),
       pending_approvals: Cuckoding.WalkingSkeleton.pending_approvals(),
       confirming_approval: nil,
       release_notice: nil
     )}
  end

  @impl true
  def handle_event("prepare-release", %{"id" => approval_id}, socket) do
    if Enum.any?(socket.assigns.pending_approvals, &(&1.approval.id == approval_id)),
      do: {:noreply, assign(socket, :confirming_approval, approval_id)},
      else: {:noreply, put_flash(socket, :error, "That approval is no longer pending.")}
  end

  def handle_event("cancel-release", _params, socket),
    do: {:noreply, assign(socket, :confirming_approval, nil)}

  def handle_event("approve-release", %{"id" => approval_id}, socket) do
    if socket.assigns.confirming_approval == approval_id do
      case Cuckoding.WalkingSkeleton.approve_and_release(approval_id, "local-user") do
        {:ok, _release} ->
          {:noreply,
           socket
           |> put_flash(:info, "Approved branch pushed to the local bare remote.")
           |> assign(
             pending_approvals: Cuckoding.WalkingSkeleton.pending_approvals(),
             confirming_approval: nil,
             release_notice: "Approved branch pushed to the local bare remote."
           )}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Release failed: #{inspect(reason)}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Confirm the release before approving it.")}
    end
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
            The local Phoenix control plane and walking-skeleton workflow are running.
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

        <section aria-labelledby="approvals-heading" class="space-y-3">
          <h2 id="approvals-heading" class="text-xl font-semibold text-slate-950">
            Human approvals
          </h2>
          <p :if={@pending_approvals == []} class="text-sm text-slate-700">
            No runs are waiting for approval.
          </p>
          <p
            :if={@release_notice}
            class="rounded-md border border-emerald-300 bg-emerald-50 p-4 text-sm text-emerald-950"
            role="status"
          >
            {@release_notice}
          </p>
          <article
            :for={item <- @pending_approvals}
            id={"approval-#{item.approval.id}"}
            class="space-y-3 rounded-lg border border-slate-200 bg-white p-5"
          >
            <div>
              <h3 class="font-semibold text-slate-950">{item.task.title}</h3>
              <p class="text-sm text-slate-700">
                {release_status(item.approval)} · branch <code>{item.run.branch}</code>
              </p>
            </div>
            <button
              :if={@confirming_approval != item.approval.id}
              type="button"
              phx-click="prepare-release"
              phx-value-id={item.approval.id}
              class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              {release_action(item.approval)}
            </button>
            <div
              :if={@confirming_approval == item.approval.id}
              class="space-y-3 rounded-md border border-amber-300 bg-amber-50 p-4"
              role="alert"
            >
              <p class="text-sm text-amber-950">
                Confirm pushing this approved feature branch to its configured local bare remote.
              </p>
              <div class="flex flex-wrap gap-3">
                <button
                  type="button"
                  phx-click="approve-release"
                  phx-value-id={item.approval.id}
                  class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Approve and push
                </button>
                <button
                  type="button"
                  phx-click="cancel-release"
                  class="min-h-10 rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Cancel
                </button>
              </div>
            </div>
          </article>
        </section>

        <fieldset class="space-y-3">
          <legend class="text-xl font-semibold text-slate-950">Experimental runtimes</legend>
          <p class="text-sm leading-6 text-slate-700">
            These runtimes are detected for evaluation but cannot be selected for a stage.
          </p>
          <div class="grid gap-3 sm:grid-cols-2">
            <CuckodingWeb.RuntimeComponents.runtime_option
              :for={runtime <- @experimental_runtimes}
              runtime={runtime}
            />
          </div>
        </fieldset>

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
  defp release_status(%{decision: "approved"}), do: "Approved · release retry available"
  defp release_status(_approval), do: "Waiting for approval"
  defp release_action(%{decision: "approved"}), do: "Retry release"
  defp release_action(_approval), do: "Review release"
  defp status_label(:ok), do: "Operational"
  defp status_label(:degraded), do: "Degraded"
  defp status_label(:unavailable), do: "Unavailable"
end
