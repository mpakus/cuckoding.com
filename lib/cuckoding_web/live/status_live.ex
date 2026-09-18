defmodule CuckodingWeb.StatusLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.ActivityComponents
  import CuckodingWeb.UsageComponents

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Cuckoding.ActivityStream.subscribe(:all)
    activity = Cuckoding.ActivityStream.recent()

    {:ok,
     assign(socket,
       page_title: "System status",
       health: Cuckoding.Health.snapshot(),
       boards: Cuckoding.Workflows.list_boards(),
       experimental_runtimes: Cuckoding.Adapters.Catalog.experimental_options(),
       pending_approvals: Cuckoding.WalkingSkeleton.pending_approvals(),
       confirming_approval: nil,
       release_notice: nil,
       usage_records: Cuckoding.Telemetry.Accounting.recent_usage(),
       activity: activity,
       activity_status:
         Cuckoding.ActivityStream.status(activity, Cuckoding.Clock.wall_now(), 60_000)
     )}
  end

  @impl true
  def handle_info({:activity_event, stream_id, _sequence}, socket) do
    acknowledged =
      socket.assigns.activity
      |> Enum.filter(&(&1.stream_id == stream_id))
      |> Enum.map(& &1.sequence)
      |> Enum.max(fn -> 0 end)

    activity =
      (socket.assigns.activity ++ Cuckoding.ActivityStream.list(stream_id, acknowledged))
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&{DateTime.to_unix(&1.occurred_at, :microsecond), &1.id})
      |> Enum.take(-20)

    {:noreply,
     assign(socket,
       activity: activity,
       activity_status:
         Cuckoding.ActivityStream.status(activity, Cuckoding.Clock.wall_now(), 60_000)
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
           |> put_flash(:info, "Approved release handoff completed.")
           |> assign(
             pending_approvals: Cuckoding.WalkingSkeleton.pending_approvals(),
             confirming_approval: nil,
             release_notice: "Approved release handoff completed."
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
            <div
              :if={item.review["outcome"] == "passed"}
              class="space-y-4 rounded-md border border-slate-200 bg-slate-50 p-4 text-sm text-slate-800"
            >
              <div>
                <h4 class="font-semibold text-slate-950">Candidate diff</h4>
                <p>
                  <code>{item.review["evidence"]["base_sha"]}</code>
                  → <code>{item.review["evidence"]["head_sha"]}</code>
                </p>
                <ul class="mt-1 list-disc pl-5">
                  <li :for={path <- item.review["changed_paths"]}><code>{path}</code></li>
                </ul>
              </div>
              <div>
                <h4 class="font-semibold text-slate-950">Tests</h4>
                <ul class="mt-1 list-disc pl-5">
                  <li :for={result <- item.review["evidence"]["tests"]}>
                    <code>{result["command"]}</code>: {result["status"]} ({result["passed"]} passed, {result[
                      "failed"
                    ]} failed)
                  </li>
                </ul>
              </div>
              <div>
                <h4 class="font-semibold text-slate-950">Artifacts</h4>
                <ul class="mt-1 list-disc pl-5">
                  <li :for={artifact <- item.review["evidence"]["artifacts"]}>
                    <code>{artifact["path"]}</code> · {artifact["type"]}
                  </li>
                </ul>
              </div>
              <div>
                <h4 class="font-semibold text-slate-950">Knowledge citations</h4>
                <ul class="mt-1 list-disc pl-5">
                  <li :for={citation <- item.review["evidence"]["knowledge_citations"]}>
                    <code>{citation["path"]}</code>
                  </li>
                </ul>
              </div>
            </div>
            <p
              :if={item.review["outcome"] == "failed"}
              class="rounded-md border border-red-300 bg-red-50 p-4 text-sm text-red-950"
              role="alert"
            >
              Evidence validation failed: {item.review["error"]}
            </p>
            <button
              :if={
                item.review["outcome"] == "passed" and
                  @confirming_approval != item.approval.id
              }
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
                Confirm the host-side push and draft pull-request handoff for this candidate.
              </p>
              <div class="flex flex-wrap gap-3">
                <button
                  type="button"
                  phx-click="approve-release"
                  phx-value-id={item.approval.id}
                  class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Approve and release
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

        <.activity_stream events={@activity} status={@activity_status} />

        <.usage_summary records={@usage_records} />

        <section aria-labelledby="boards-heading" class="space-y-3">
          <h2 id="boards-heading" class="text-xl font-semibold text-slate-950">Boards</h2>
          <p :if={@boards == []} class="text-sm text-slate-700">No boards yet.</p>
          <ul :if={@boards != []} class="grid gap-3 sm:grid-cols-2">
            <li :for={board <- @boards}>
              <.link
                navigate={~p"/boards/#{board.id}"}
                class="flex min-h-10 items-center rounded-md border border-slate-300 bg-white px-4 font-medium text-slate-950 underline decoration-slate-400 underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                {board.name}
              </.link>
            </li>
          </ul>
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
