defmodule CuckodingWeb.StatusLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.ActivityComponents
  import CuckodingWeb.UsageComponents

  @active_session_states ~w(starting running waiting)
  @active_run_states ~w(running waiting)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Cuckoding.ActivityStream.subscribe(:all)

    activity = Cuckoding.ActivityStream.recent()
    agent_cards = Cuckoding.AgentFloor.list_sessions()

    {:ok,
     assign(socket,
       page_title: "Projects and operations",
       health: Cuckoding.Health.snapshot(),
       project_cards: project_cards(agent_cards),
       resource_summary: resource_summary(agent_cards),
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
      <section aria-labelledby="dashboard-heading" class="space-y-10">
        <header class="flex flex-col gap-5 sm:flex-row sm:items-end sm:justify-between">
          <div class="space-y-3">
            <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">
              Projects and operations
            </p>
            <h1 id="dashboard-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
              Your Cuckoding workspace
            </h1>
            <p class="max-w-2xl text-base leading-7 text-slate-700">
              Open a project, see what every agent is doing, and check the load on your Mac.
            </p>
          </div>
          <.link
            navigate={~p"/projects/new"}
            class="inline-flex min-h-11 items-center justify-center rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Add project
          </.link>
        </header>

        <section aria-labelledby="overview-heading" class="space-y-3">
          <h2 id="overview-heading" class="text-xl font-semibold text-slate-950">
            Application and resources
          </h2>
          <dl class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <div class="rounded-lg border border-slate-200 bg-white p-4">
              <dt class="text-sm font-medium text-slate-600">Application</dt>
              <dd class="mt-1 text-lg font-semibold text-slate-950">
                {status_label(@health.status)}
              </dd>
              <dd class="text-sm text-slate-600">Version {@health.application.version}</dd>
            </div>
            <div class="rounded-lg border border-slate-200 bg-white p-4">
              <dt class="text-sm font-medium text-slate-600">Active agents</dt>
              <dd id="active-agent-count" class="mt-1 text-lg font-semibold text-slate-950">
                {@resource_summary.active_agents}
              </dd>
              <dd class="text-sm text-slate-600">durable sessions</dd>
            </div>
            <div class="rounded-lg border border-slate-200 bg-white p-4">
              <dt class="text-sm font-medium text-slate-600">Measured memory</dt>
              <dd class="mt-1 text-lg font-semibold text-slate-950">
                {format_bytes(@resource_summary.memory_bytes)}
              </dd>
              <dd class="text-sm text-slate-600">latest owned samples</dd>
            </div>
            <div class="rounded-lg border border-slate-200 bg-white p-4">
              <dt class="text-sm font-medium text-slate-600">Owned processes · ports</dt>
              <dd class="mt-1 text-lg font-semibold text-slate-950">
                {@resource_summary.processes} · {@resource_summary.ports}
              </dd>
              <dd class="text-sm text-slate-600">host runner, advisory limits</dd>
            </div>
          </dl>
        </section>

        <section aria-labelledby="projects-heading" class="space-y-4">
          <div class="flex items-center justify-between gap-4">
            <h2 id="projects-heading" class="text-xl font-semibold text-slate-950">Projects</h2>
            <span class="text-sm text-slate-600">{length(@project_cards)} registered</span>
          </div>

          <div
            :if={@project_cards == []}
            id="projects-empty"
            class="rounded-xl border border-dashed border-slate-300 bg-white p-8 text-center"
          >
            <h3 class="text-lg font-semibold text-slate-950">Add your first project</h3>
            <p class="mx-auto mt-2 max-w-xl text-sm leading-6 text-slate-700">
              First register the repository and agents. Then create a board and add tasks.
              Nothing runs during project setup.
            </p>
            <.link
              navigate={~p"/projects/new"}
              class="mt-5 inline-flex min-h-11 items-center rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              Add project
            </.link>
          </div>

          <ul :if={@project_cards != []} class="grid gap-4 lg:grid-cols-2">
            <li
              :for={card <- @project_cards}
              id={"project-#{card.project.id}"}
              class="rounded-xl border border-slate-200 bg-white p-5"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <h3 class="text-lg font-semibold text-slate-950">{card.project.name}</h3>
                  <p class="mt-1 text-sm text-slate-600">
                    {Path.basename(card.project.repo_path)} · {card.project.default_branch}
                  </p>
                </div>
                <span class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-700">
                  {card.project.status}
                </span>
              </div>
              <dl class="mt-5 grid grid-cols-3 gap-3 text-sm">
                <div>
                  <dt class="text-slate-600">Boards</dt><dd class="font-semibold">
                    {length(card.boards)}
                  </dd>
                </div>
                <div>
                  <dt class="text-slate-600">Active agents</dt><dd class="font-semibold">
                    {card.active_agents}
                  </dd>
                </div>
                <div>
                  <dt class="text-slate-600">Attention</dt><dd class="font-semibold">
                    {card.attention}
                  </dd>
                </div>
              </dl>
              <div class="mt-5 flex flex-wrap gap-2">
                <.link
                  navigate={~p"/projects/#{card.project.id}/edit"}
                  class="inline-flex min-h-10 items-center rounded-md border border-slate-300 px-3 text-sm font-medium text-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Edit project
                </.link>
                <.link
                  :for={board <- card.boards}
                  navigate={~p"/boards/#{board.id}"}
                  class="inline-flex min-h-10 items-center rounded-md border border-slate-300 px-3 text-sm font-medium text-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  {board.name}
                </.link>
                <span :if={card.boards == []} class="text-sm text-slate-600">
                  Ready for board setup
                </span>
              </div>
            </li>
          </ul>
        </section>

        <nav aria-label="Workspace views" class="flex flex-wrap gap-3">
          <.link
            navigate={~p"/agents"}
            class="inline-flex min-h-11 items-center rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Open Agent Floor
          </.link>
          <.link
            navigate={~p"/knowledge"}
            class="inline-flex min-h-11 items-center rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Review knowledge
          </.link>
        </nav>

        <section aria-labelledby="approvals-heading" class="space-y-3">
          <h2 id="approvals-heading" class="text-xl font-semibold text-slate-950">Attention</h2>
          <p :if={@pending_approvals == []} class="text-sm text-slate-700">
            No runs need human approval.
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
              :if={item.review["outcome"] == "passed" and @confirming_approval != item.approval.id}
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
                  class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white"
                >
                  Approve and release
                </button>
                <button
                  type="button"
                  phx-click="cancel-release"
                  class="min-h-10 rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950"
                >
                  Cancel
                </button>
              </div>
            </div>
          </article>
        </section>

        <.activity_stream events={@activity} status={@activity_status} />
        <.usage_summary records={@usage_records} />

        <details class="rounded-lg border border-slate-200 bg-white p-5">
          <summary class="cursor-pointer font-semibold text-slate-950">Diagnostics</summary>
          <div class="mt-4 space-y-4">
            <dl class="divide-y divide-slate-200 rounded-lg border border-slate-200">
              <div
                :for={{name, status} <- Enum.sort(@health.dependencies)}
                class="flex items-center justify-between gap-4 px-4 py-3"
              >
                <dt class="font-medium text-slate-800">{dependency_label(name)}</dt>
                <dd class="text-sm text-slate-700">{status_label(status)}</dd>
              </div>
            </dl>
            <nav aria-label="Diagnostics" class="flex flex-wrap gap-3">
              <a
                href={~p"/health"}
                class="inline-flex min-h-10 items-center rounded-md border border-slate-300 px-4 font-medium"
              >Health JSON</a>
              <a
                href={~p"/status"}
                class="inline-flex min-h-10 items-center rounded-md border border-slate-300 px-4 font-medium"
              >Diagnostics JSON</a>
            </nav>
          </div>
        </details>
      </section>
    </Layouts.app>
    """
  end

  defp project_cards(agent_cards) do
    agents_by_project = Enum.group_by(agent_cards, & &1.project.id)

    Enum.map(Cuckoding.Projects.list_projects(), fn project ->
      cards = Map.get(agents_by_project, project.id, [])

      %{
        project: project,
        boards: Cuckoding.Workflows.list_boards(project.id),
        active_agents: Enum.count(cards, &active_session?/1),
        attention:
          cards
          |> Enum.filter(& &1.attention?)
          |> Enum.uniq_by(& &1.run.id)
          |> length()
      }
    end)
  end

  defp resource_summary(cards) do
    active = Enum.filter(cards, &active_session?/1)
    resources = active |> Enum.map(& &1.resource) |> Enum.reject(&is_nil/1)

    %{
      active_agents: length(active),
      memory_bytes: Enum.sum(Enum.map(resources, & &1.memory_bytes)),
      processes: Enum.sum(Enum.map(resources, & &1.process_count)),
      ports: resources |> Enum.flat_map(&(&1.open_ports_json || [])) |> Enum.uniq() |> length()
    }
  end

  defp active_session?(card),
    do: card.session.state in @active_session_states and card.run.state in @active_run_states

  defp format_bytes(0), do: "No active samples"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{div(bytes, 1_024)} KiB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MiB"

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
