defmodule CuckodingWeb.StatusLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.ActivityComponents
  import CuckodingWeb.UsageComponents

  @active_session_states ~w(starting running waiting)
  @active_run_states ~w(running waiting)
  @refresh_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Cuckoding.ActivityStream.subscribe(:all)
      Process.send_after(self(), :refresh_dashboard, @refresh_ms)
    end

    activity = Cuckoding.ActivityStream.recent()

    {:ok,
     socket
     |> assign(
       page_title: "Projects and operations",
       confirming_approval: nil,
       confirming_completion: nil,
       release_notice: nil,
       refresh_pending: false,
       activity_filter: "all",
       operation_filter: %{"state" => "all", "project" => "all", "query" => ""},
       activity: activity,
       activity_status:
         Cuckoding.ActivityStream.status(activity, Cuckoding.Clock.wall_now(), 60_000)
     )
     |> load_dashboard()}
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

    socket =
      assign(socket,
        activity: activity,
        activity_status:
          Cuckoding.ActivityStream.status(activity, Cuckoding.Clock.wall_now(), 60_000)
      )

    if socket.assigns.refresh_pending do
      {:noreply, socket}
    else
      Process.send_after(self(), :refresh_dashboard_activity, 250)
      {:noreply, assign(socket, refresh_pending: true)}
    end
  end

  def handle_info(:refresh_dashboard, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_dashboard, @refresh_ms)
    {:noreply, socket |> assign(refresh_pending: false) |> load_dashboard()}
  end

  def handle_info(:refresh_dashboard_activity, socket) do
    {:noreply, socket |> assign(refresh_pending: false) |> load_dashboard()}
  end

  @impl true
  def handle_event("filter-activity", %{"category" => category}, socket)
      when category in ~w(all agent workflow system) do
    {:noreply, assign(socket, :activity_filter, category)}
  end

  def handle_event("filter-operations", %{"filter" => filter}, socket) do
    filter = %{
      "state" => filter_value(filter["state"], ~w(all active attention done)),
      "project" =>
        filter_value(
          filter["project"],
          Enum.map(socket.assigns.project_cards, & &1.project.id) ++ ["all"]
        ),
      "query" => filter |> Map.get("query", "") |> String.trim() |> String.slice(0, 100)
    }

    {:noreply, assign(socket, :operation_filter, filter)}
  end

  @impl true
  def handle_event("prepare-release", %{"id" => approval_id}, socket) do
    if Enum.any?(socket.assigns.pending_approvals, &(&1.approval.id == approval_id)),
      do: {:noreply, assign(socket, :confirming_approval, approval_id)},
      else: {:noreply, put_flash(socket, :error, "That approval is no longer pending.")}
  end

  def handle_event("cancel-release", _params, socket),
    do: {:noreply, assign(socket, :confirming_approval, nil)}

  def handle_event("prepare-local-completion", %{"id" => approval_id}, socket) do
    if Enum.any?(socket.assigns.pending_approvals, &(&1.approval.id == approval_id)),
      do: {:noreply, assign(socket, :confirming_completion, approval_id)},
      else: {:noreply, put_flash(socket, :error, "That completion choice is no longer pending.")}
  end

  def handle_event("cancel-local-completion", _params, socket),
    do: {:noreply, assign(socket, :confirming_completion, nil)}

  def handle_event("complete-locally", %{"id" => approval_id}, socket) do
    if socket.assigns.confirming_completion == approval_id do
      case Cuckoding.WalkingSkeleton.complete_locally(approval_id, "local-user") do
        {:ok, _completion} ->
          {:noreply,
           socket
           |> put_flash(:info, "Run completed locally. No branch was pushed.")
           |> assign(
             pending_approvals: Cuckoding.WalkingSkeleton.pending_approvals(),
             confirming_completion: nil,
             release_notice: "Run completed locally. No branch was pushed."
           )}

        {:error, _reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Local completion could not be recorded. Open the run and verify its Review evidence before retrying."
           )}
      end
    else
      {:noreply, put_flash(socket, :error, "Confirm local completion before closing the run.")}
    end
  end

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

        {:error, _reason} ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Release handoff could not be completed. Open the run timeline, review its release evidence, and retry."
           )}
      end
    else
      {:noreply, put_flash(socket, :error, "Confirm the release before approving it.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active="projects">
      <section aria-labelledby="dashboard-heading" class="dashboard space-y-8">
        <div class="dashboard-intro">
          <header class="workspace-hero">
            <img
              class="workspace-hero-art"
              src={~p"/assets/images/workspace-portal.webp"}
              width="1536"
              height="1024"
              alt=""
              fetchpriority="high"
            />
            <div class="workspace-hero-copy">
              <p class="eyebrow">
                Projects and operations
              </p>
              <h1 id="dashboard-heading">
                Your Cuckoding workspace
              </h1>
              <p class="hero-description">
                Open a project, see what every agent is doing, and check the load on your Mac.
              </p>
              <.link
                navigate={~p"/projects/new"}
                class="hero-action"
              >
                Add project <span aria-hidden="true">↗</span>
              </.link>
            </div>
          </header>
          <section class="workspace-glance" aria-labelledby="glance-heading">
            <h2 id="glance-heading" class="eyebrow">At a glance</h2>
            <dl>
              <div class="glance-primary">
                <dt>Active agents</dt><dd id="glance-agents">{@resource_summary.active_agents}</dd>
              </div>
              <div class="glance-row">
                <dt>Registered projects</dt><dd id="glance-projects">{length(@project_cards)}</dd>
              </div>
              <div class="glance-row">
                <dt>Pending approvals</dt><dd id="glance-approvals">{length(@pending_approvals)}</dd>
              </div>
            </dl>
            <a href="#overview-heading" class="glance-health"><span aria-hidden="true">◇</span> {status_label(
              @health.status
            )} <span aria-hidden="true">↗</span></a>
          </section>
        </div>

        <nav aria-label="Dashboard sections" class="dashboard-sections">
          <a href="#projects-heading">Projects ({length(@project_cards)})</a>
          <a href="#activity-heading">Live activity</a>
          <a href="#operations-heading">Operations</a>
          <a href="#approvals-heading">Approvals ({length(@pending_approvals)})</a>
        </nav>

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
              Register a project, create a board and tasks, then assign agents and start. Nothing runs during project setup.
            </p>
            <.link
              navigate={~p"/projects/new"}
              class="mt-5 inline-flex min-h-11 items-center rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
            >Add project</.link>
          </div>
          <ul :if={@project_cards != []} class="grid gap-4 lg:grid-cols-2">
            <li
              :for={card <- @project_cards}
              id={"project-#{card.project.id}"}
              class="project-card rounded-xl border border-slate-200 bg-white p-5"
            >
              <div class="flex items-start justify-between gap-4">
                <div>
                  <h3 class="text-lg font-semibold text-slate-950">{card.project.name}</h3>
                  <p class="mt-1 text-sm text-slate-600">
                    {Path.basename(card.project.repo_path)} · {card.project.default_branch}
                  </p>
                </div>
                <div class="flex flex-wrap gap-2">
                  <span class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-700">{card.project.status}</span>
                  <span class="rounded-full bg-slate-100 px-3 py-1 text-xs font-medium text-slate-700">{project_operation_label(
                    card.autopilot.state
                  )}</span>
                </div>
              </div>
              <p :if={card.autopilot.last_issue} class="mt-3 text-sm text-amber-900">
                {Cuckoding.ProjectAutopilot.issue_message(card.autopilot.last_issue)}
              </p>
              <dl class="mt-5 grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
                <div>
                  <dt class="text-slate-600">Boards</dt><dd class="font-semibold">
                    {length(card.boards)}
                  </dd>
                </div>
                <div>
                  <dt class="text-slate-600">Tasks</dt><dd class="font-semibold">
                    {card.task_count}
                  </dd>
                </div>
                <div>
                  <dt class="text-slate-600">Active agents</dt><dd class="font-semibold">
                    {card.active_agents}
                  </dd>
                </div>
                <div>
                  <dt class="text-slate-600">Run attention</dt><dd class="font-semibold">
                    {card.attention}
                  </dd>
                </div>
              </dl>
              <div class="mt-5">
                <h4 class="text-sm font-semibold text-slate-950">Task states</h4>
                <dl class="mt-2 grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
                  <div
                    :for={
                      state <-
                        ~w(blocked done running waiting ready draft failed paused hibernated cancelled archived)
                    }
                    :if={
                      state in ~w(blocked done running waiting ready draft failed) or
                        Map.get(card.task_states, state, 0) > 0
                    }
                    id={"project-state-#{card.project.id}-#{state}"}
                    class="task-state rounded-md bg-slate-50 px-3 py-2"
                    data-state={state}
                  >
                    <dt class="text-slate-600">{project_state_label(state)}</dt>
                    <dd class="font-semibold text-slate-950">
                      {Map.get(card.task_states, state, 0)}
                    </dd>
                  </div>
                </dl>
              </div>
              <div class="mt-5 flex flex-wrap gap-2">
                <.link
                  navigate={~p"/projects/#{card.project.id}/edit"}
                  class="inline-flex min-h-10 items-center rounded-md border border-slate-300 px-3 text-sm font-medium text-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  {if card.autopilot.state == "running",
                    do: "Monitor project",
                    else: "Set up or start project"}
                </.link>
                <.link
                  :for={board <- card.boards}
                  navigate={~p"/boards/#{board.id}"}
                  class="inline-flex min-h-10 items-center rounded-md border border-slate-300 px-3 text-sm font-medium text-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2"
                >Open {board.name}</.link>
                <.link
                  :if={card.boards == []}
                  navigate={~p"/projects/#{card.project.id}/edit#boards-heading"}
                  class="inline-flex min-h-10 items-center rounded-md border border-slate-300 px-3 text-sm font-medium text-slate-900 focus-visible:outline-2 focus-visible:outline-offset-2"
                >Create board</.link>
              </div>
            </li>
          </ul>
        </section>

        <section aria-labelledby="activity-heading" class="space-y-4">
          <div class="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 id="activity-heading" class="text-xl font-semibold text-slate-950">
                Recent activity
              </h2>
              <p class="mt-1 text-sm text-slate-700">
                Live from committed events and active agent sessions. Activity mix covers the latest {length(
                  @activity
                )} events.
              </p>
            </div>
            <.link
              navigate={~p"/agents"}
              class="inline-flex min-h-10 items-center rounded-md border border-slate-400 bg-white px-4 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
            >Open Agent Floor</.link>
          </div>
          <div id="agent-activity-chart" class="rounded-xl border border-slate-200 bg-white p-5">
            <div class="flex flex-wrap items-baseline justify-between gap-2">
              <h3 class="font-semibold text-slate-950">Live agent activity</h3>
              <p class="text-sm text-slate-600">Last 12 UTC minutes · refreshes every 5 seconds</p>
            </div>
            <p class="mt-1 text-sm text-slate-700">
              Distinct current agent sessions with a measured owned-process sample in each minute. Gaps mean no sample, not zero agents.
            </p>
            <p
              :if={Enum.all?(@sampled_activity, &is_nil(&1.count))}
              class="mt-4 text-sm text-slate-600"
            >
              No samples from currently active agents yet.
            </p>
            <svg viewBox="0 0 576 140" class="activity-chart mt-4 h-44 w-full" aria-hidden="true">
              <line x1="0" y1="112" x2="576" y2="112" stroke="currentColor" class="text-slate-300" />
              <g :for={{bucket, index} <- Enum.with_index(@sampled_activity)}>
                <rect
                  :if={is_integer(bucket.count)}
                  x={index * 48 + 10}
                  y={112 - sample_bar_height(bucket.count, @sampled_activity)}
                  width="28"
                  height={sample_bar_height(bucket.count, @sampled_activity)}
                  rx="5"
                  fill="currentColor"
                />
                <text
                  :if={rem(index, 3) == 0 or index == 11}
                  x={index * 48 + 24}
                  y="132"
                  text-anchor="middle"
                  font-size="11"
                  fill="currentColor"
                >
                  {bucket.minute}
                </text>
              </g>
            </svg>
            <details class="mt-2 text-sm">
              <summary class="min-h-10 cursor-pointer font-medium text-slate-900">
                View minute-by-minute data
              </summary>
              <table class="mt-2 w-full text-left">
                <caption class="sr-only">Measured current-agent activity by UTC minute</caption><thead>
                  <tr>
                    <th scope="col" class="py-2">UTC minute</th><th scope="col" class="py-2">
                      Sessions sampled
                    </th>
                  </tr>
                </thead><tbody>
                  <tr :for={bucket <- @sampled_activity}>
                    <th scope="row" class="py-1 font-normal">{bucket.minute}</th><td class="py-1">
                      {if is_nil(bucket.count), do: "No sample", else: bucket.count}
                    </td>
                  </tr>
                </tbody>
              </table>
            </details>
          </div>
          <div class="grid gap-4 xl:grid-cols-2">
            <div class="rounded-xl border border-slate-200 bg-white p-5">
              <h3 class="font-semibold text-slate-950">Activity mix</h3>
              <p class="mt-1 text-sm text-slate-600">Select a category to filter the event log.</p>
              <div class="mt-4 space-y-3">
                <button
                  :for={
                    {category, label} <- [
                      {"agent", "Agent & process"},
                      {"workflow", "Workflow"},
                      {"system", "System"}
                    ]
                  }
                  type="button"
                  phx-click="filter-activity"
                  phx-value-category={category}
                  aria-pressed={to_string(@activity_filter == category)}
                  class="block w-full rounded-lg px-2 py-2 text-left hover:bg-slate-50 aria-pressed:bg-slate-100 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  <span class="flex justify-between gap-3 text-sm font-medium"><span>{label}</span><span>{activity_count(
                    @activity,
                    category
                  )}</span></span>
                  <meter
                    class="mt-2 block h-3 w-full"
                    min="0"
                    max={max(length(@activity), 1)}
                    value={activity_count(@activity, category)}
                    aria-hidden="true"
                  />
                </button>
              </div>
              <button
                type="button"
                phx-click="filter-activity"
                phx-value-category="all"
                aria-pressed={to_string(@activity_filter == "all")}
                class="mt-3 min-h-10 rounded-md border border-slate-300 px-3 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
              >All events ({length(@activity)})</button>
              <table class="sr-only">
                <caption>Activity mix for the latest {length(@activity)} events</caption><tbody>
                  <tr :for={
                    {category, label} <- [
                      {"agent", "Agent & process"},
                      {"workflow", "Workflow"},
                      {"system", "System"}
                    ]
                  }>
                    <th scope="row">{label}</th><td>{activity_count(@activity, category)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
            <div class="rounded-xl border border-slate-200 bg-white p-5">
              <div class="flex items-center justify-between gap-3">
                <h3 class="font-semibold text-slate-950">Agents right now</h3><span class="text-sm text-slate-600">{@resource_summary.active_agents} active</span>
              </div>
              <p :if={@active_sessions == []} class="mt-4 text-sm text-slate-700">
                No agents are running or waiting for input.
              </p>
              <ul :if={@active_sessions != []} class="mt-4 divide-y divide-slate-200">
                <li
                  :for={card <- @active_sessions}
                  class="flex flex-wrap items-center justify-between gap-3 py-3 text-sm"
                >
                  <div>
                    <p class="font-medium text-slate-950">{card.project.name} · {card.task.title}</p><p class="text-slate-600">
                      {state_label(card.attempt.role_key)} · {state_label(card.session.adapter_key)} · {card.session.actual_model ||
                        card.session.requested_model || "Model not reported"}
                    </p>
                    <p class="text-slate-600">
                      {state_label(card.session.state)} · {if card.attempt.started_at,
                        do: "Stage started",
                        else: "Session created"} {elapsed(
                        card.attempt.started_at || card.session.inserted_at
                      )} ago
                    </p>
                  </div>
                  <.link
                    navigate={~p"/runs/#{card.run.id}"}
                    class="inline-flex min-h-10 items-center rounded-md border border-slate-300 px-3 font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
                  >Inspect</.link>
                </li>
              </ul>
            </div>
          </div>
          <details class="rounded-xl border border-slate-200 bg-white p-5">
            <summary class="cursor-pointer font-semibold text-slate-950">
              Event log ({length(visible_activity(@activity, @activity_filter))})
            </summary>
            <div class="mt-4">
              <.activity_stream
                events={visible_activity(@activity, @activity_filter)}
                status={@activity_status}
                heading="Committed events"
                heading_id="activity-log-heading"
                heading_level="h3"
                empty_message="No events match this category in the latest activity."
              />
            </div>
          </details>
        </section>

        <section aria-labelledby="operations-heading" class="space-y-4">
          <div class="flex flex-wrap items-end justify-between gap-3">
            <div>
              <h2 id="operations-heading" class="text-xl font-semibold text-slate-950">
                Operations
              </h2>
              <p class="mt-1 text-sm text-slate-700">
                Follow current and recent runs. Queued runs still need authentication and an explicit start.
              </p>
            </div>
            <.link
              navigate={~p"/agents"}
              class="inline-flex min-h-10 items-center rounded-md border border-slate-400 bg-white px-4 text-sm font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              Open Agent Floor
            </.link>
          </div>

          <form
            id="operation-filters"
            phx-change="filter-operations"
            class="grid gap-3 rounded-xl border border-slate-200 bg-white p-4 sm:grid-cols-3"
          >
            <div>
              <label for="operation-state" class="block text-sm font-medium text-slate-700">State</label><select
                id="operation-state"
                name="filter[state]"
                class="mt-1 min-h-10 w-full rounded-md border border-slate-300 px-3"
              ><option value="all" selected={@operation_filter["state"] == "all"}>All states</option><option
                value="active"
                selected={@operation_filter["state"] == "active"}
              >
                Active & queued
              </option><option value="attention" selected={@operation_filter["state"] == "attention"}>
                Needs attention
              </option><option value="done" selected={@operation_filter["state"] == "done"}>
                Done
              </option></select>
            </div>
            <div>
              <label for="operation-project" class="block text-sm font-medium text-slate-700">Project</label><select
                id="operation-project"
                name="filter[project]"
                class="mt-1 min-h-10 w-full rounded-md border border-slate-300 px-3"
              ><option value="all" selected={@operation_filter["project"] == "all"}>
                All projects
              </option><option
                :for={card <- @project_cards}
                value={card.project.id}
                selected={@operation_filter["project"] == card.project.id}
              >
                {card.project.name}
              </option></select>
            </div>
            <div>
              <label for="operation-query" class="block text-sm font-medium text-slate-700">Find run</label><input
                id="operation-query"
                name="filter[query]"
                value={@operation_filter["query"]}
                type="search"
                placeholder="Task, board, or project"
                class="mt-1 min-h-10 w-full rounded-md border border-slate-300 px-3"
              />
            </div>
          </form>
          <p role="status" class="text-sm text-slate-600">
            Showing {length(visible_operations(@operations, @operation_filter))} of {length(
              @operations
            )} recent runs.
          </p>
          <p
            :if={@operations == []}
            id="operations-empty"
            class="rounded-xl border border-dashed border-slate-300 bg-white p-6 text-sm text-slate-700"
          >
            No runs yet. Open a project board, add a task, and mark it Ready to prepare its first run.
          </p>
          <p
            :if={@operations != [] and visible_operations(@operations, @operation_filter) == []}
            id="operations-filter-empty"
            class="rounded-xl border border-dashed border-slate-300 bg-white p-6 text-sm text-slate-700"
          >
            No recent runs match these filters.
          </p>
          <div
            :if={visible_operations(@operations, @operation_filter) != []}
            id="operation-list"
            role="region"
            aria-label="Operations table"
            tabindex="0"
            class="overflow-x-auto rounded-xl border border-slate-200 bg-white focus-visible:outline-2"
          >
            <table class="min-w-[60rem] w-full divide-y divide-slate-200 text-left text-sm">
              <caption class="sr-only">
                Latest 50 runs, filtered by state, project, and search
              </caption><thead class="bg-slate-50 text-slate-700">
                <tr>
                  <th scope="col" class="px-4 py-3">Task / project</th><th
                    scope="col"
                    class="px-4 py-3"
                  >
                    State
                  </th><th scope="col" class="px-4 py-3">Actions</th><th scope="col" class="px-4 py-3">
                    Role / runtime
                  </th><th
                    scope="col"
                    class="px-4 py-3"
                  >
                    Created
                  </th><th scope="col" class="px-4 py-3">Measured memory</th>
                </tr>
              </thead><tbody class="divide-y divide-slate-200">
                <tr
                  :for={operation <- visible_operations(@operations, @operation_filter)}
                  id={"operation-#{operation.run.id}"}
                >
                  <th scope="row" class="px-4 py-3 font-medium text-slate-950">
                    <span class="block">{operation.task.title}</span><span class="block font-normal text-slate-600">{operation.project.name} · {operation.board.name}</span>
                  </th><td class="px-4 py-3">
                    <span class="font-medium">{state_label(operation.run.state)}</span><span
                      :if={operation.run.wait_reason}
                      class="block text-amber-950"
                    >{operation.run.wait_reason}</span>
                  </td><td class="px-4 py-3">
                    <div class="flex gap-2">
                      <.link
                        navigate={~p"/runs/#{operation.run.id}"}
                        class="inline-flex min-h-10 items-center rounded-md bg-slate-950 px-3 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
                      >Inspect run</.link><.link
                        navigate={~p"/boards/#{operation.board.id}/tasks/#{operation.task.id}"}
                        class="inline-flex min-h-10 items-center rounded-md border border-slate-300 px-3 font-medium focus-visible:outline-2 focus-visible:outline-offset-2"
                      >Task</.link>
                    </div>
                  </td><td class="px-4 py-3">
                    {operation_role(operation)}<span class="block text-slate-600">{operation_runtime(
                      operation
                    )}</span>
                  </td><td class="whitespace-nowrap px-4 py-3">
                    {elapsed(operation.run.inserted_at)} ago
                  </td><td class="px-4 py-3">{operation_memory(operation)}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </section>

        <section aria-labelledby="overview-heading" class="space-y-4">
          <div>
            <h2 id="overview-heading" class="text-xl font-semibold text-slate-950">
              Application and resources
            </h2><p class="mt-1 text-sm text-slate-700">
              Current control-plane health and measured agent load. Host limits are advisory, not enforced.
            </p>
          </div>
          <div class="grid gap-4 lg:grid-cols-2">
            <div class="rounded-xl border border-slate-200 bg-white p-5">
              <h3 class="font-semibold text-slate-950">Application</h3>
              <p class="mt-3 text-2xl font-semibold text-slate-950">{status_label(@health.status)}</p>
              <p class="text-sm text-slate-600">Version {@health.application.version}</p>
              <dl class="mt-5 divide-y divide-slate-200 text-sm">
                <div
                  :for={{name, status} <- Enum.sort(@health.dependencies)}
                  class="flex justify-between gap-4 py-2"
                >
                  <dt>{dependency_label(name)}</dt><dd class="font-medium">{status_label(status)}</dd>
                </div>
              </dl>
            </div>
            <div class="rounded-xl border border-slate-200 bg-white p-5">
              <h3 class="font-semibold text-slate-950">Resources</h3>
              <dl class="mt-4 grid grid-cols-2 gap-4 text-sm">
                <div>
                  <dt class="text-slate-600">Active agents</dt><dd
                    id="active-agent-count"
                    class="text-2xl font-semibold text-slate-950"
                  >
                    {@resource_summary.active_agents}
                  </dd>
                </div>
                <div>
                  <dt class="text-slate-600">Measured memory</dt><dd class="text-2xl font-semibold text-slate-950">
                    {format_bytes(@resource_summary.memory_bytes)}
                  </dd>
                </div>
                <div>
                  <dt class="text-slate-600">Owned processes</dt><dd class="text-2xl font-semibold text-slate-950">
                    {@resource_summary.processes}
                  </dd>
                </div>
                <div>
                  <dt class="text-slate-600">Open ports</dt><dd class="text-2xl font-semibold text-slate-950">
                    {@resource_summary.ports}
                  </dd>
                </div>
              </dl>
              <p class="mt-4 text-sm text-slate-600">
                Latest measurements from active agent sessions; no sample means unavailable, not zero usage.
              </p>
            </div>
          </div>
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
            <div
              :if={
                item.review["outcome"] == "passed" and
                  @confirming_approval != item.approval.id and
                  @confirming_completion != item.approval.id
              }
              class="flex flex-wrap gap-3"
            >
              <button
                type="button"
                phx-click="prepare-release"
                phx-value-id={item.approval.id}
                class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                {release_action(item.approval)}
              </button>
              <button
                type="button"
                phx-click="prepare-local-completion"
                phx-value-id={item.approval.id}
                class="min-h-10 rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                Complete locally
              </button>
            </div>
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
            <div
              :if={@confirming_completion == item.approval.id}
              class="space-y-3 rounded-md border border-amber-300 bg-amber-50 p-4"
              role="alert"
            >
              <p class="text-sm text-amber-950">
                Complete this reviewed task without pushing the feature branch or creating a pull request? The branch, worktree, and evidence stay on this machine.
              </p>
              <div class="flex flex-wrap gap-3">
                <button
                  type="button"
                  phx-click="complete-locally"
                  phx-value-id={item.approval.id}
                  class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white"
                >
                  Confirm local completion
                </button>
                <button
                  type="button"
                  phx-click="cancel-local-completion"
                  class="min-h-10 rounded-md border border-slate-400 bg-white px-4 font-medium text-slate-950"
                >
                  Keep reviewing
                </button>
              </div>
            </div>
          </article>
        </section>

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
      boards = Cuckoding.Workflows.list_boards(project.id)
      tasks = Enum.flat_map(boards, &Cuckoding.Workflows.list_tasks(&1.id))

      %{
        project: project,
        autopilot: Cuckoding.ProjectAutopilot.settings(project.id),
        boards: boards,
        task_count: length(tasks),
        task_states: Enum.frequencies_by(tasks, & &1.state),
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

  defp load_dashboard(socket) do
    agent_cards = Cuckoding.AgentFloor.list_sessions()
    active_sessions = Enum.filter(agent_cards, &active_session?/1)

    assign(socket,
      health: Cuckoding.Health.snapshot(),
      activity_status:
        Cuckoding.ActivityStream.status(
          socket.assigns.activity,
          Cuckoding.Clock.wall_now(),
          60_000
        ),
      project_cards: project_cards(agent_cards),
      operations: Cuckoding.AgentFloor.list_operations(50),
      active_sessions: active_sessions,
      sampled_activity:
        Cuckoding.AgentFloor.sampled_activity(Enum.map(active_sessions, & &1.session.id)),
      resource_summary: resource_summary(agent_cards),
      pending_approvals: Cuckoding.WalkingSkeleton.pending_approvals(),
      usage_records: Cuckoding.Telemetry.Accounting.recent_usage()
    )
  end

  defp active_session?(card),
    do: card.session.state in @active_session_states and card.run.state in @active_run_states

  defp filter_value(value, allowed), do: if(value in allowed, do: value, else: "all")

  defp activity_category(event) do
    cond do
      event.correlation["agent_session_id"] ||
          String.starts_with?(event.event_type, ["agent.", "process.", "provider."]) ->
        "agent"

      String.starts_with?(event.event_type, [
        "run.",
        "stage.",
        "stage_attempt.",
        "task.",
        "board."
      ]) ->
        "workflow"

      true ->
        "system"
    end
  end

  defp activity_count(events, category),
    do: Enum.count(events, &(activity_category(&1) == category))

  defp sample_bar_height(count, buckets) do
    maximum = Enum.reduce(buckets, 0, fn bucket, current -> max(bucket.count || 0, current) end)
    if maximum == 0, do: 0, else: max(div(count * 100, maximum), 4)
  end

  defp visible_activity(events, "all"), do: events

  defp visible_activity(events, category),
    do: Enum.filter(events, &(activity_category(&1) == category))

  defp visible_operations(operations, filter) do
    Enum.filter(operations, fn operation ->
      state_matches?(operation.run.state, filter["state"]) and
        (filter["project"] == "all" or operation.project.id == filter["project"]) and
        (filter["query"] == "" or
           String.contains?(
             String.downcase(
               "#{operation.task.title} #{operation.board.name} #{operation.project.name}"
             ),
             String.downcase(filter["query"])
           ))
    end)
  end

  defp state_matches?(_state, "all"), do: true
  defp state_matches?(state, "active"), do: state in ~w(queued running paused hibernated)
  defp state_matches?(state, "attention"), do: state in ~w(waiting blocked failed)
  defp state_matches?(state, "done"), do: state in ~w(done released)

  defp project_operation_label("running"), do: "Running"
  defp project_operation_label("attention"), do: "Needs attention"
  defp project_operation_label("done"), do: "Done"
  defp project_operation_label(_state), do: "Paused"
  defp project_state_label("done"), do: "Completed"
  defp project_state_label(state), do: state_label(state)

  defp format_bytes(0), do: "No active samples"
  defp format_bytes(bytes) when bytes < 1_048_576, do: "#{div(bytes, 1_024)} KiB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MiB"

  defp operation_role(%{attempt: %{role_key: role_key}}), do: state_label(role_key)
  defp operation_role(_operation), do: "Waiting for launch"
  defp operation_runtime(%{session: %{adapter_key: adapter}}), do: state_label(adapter)
  defp operation_runtime(_operation), do: "Not started"

  defp operation_memory(%{resource: %{memory_bytes: bytes}}), do: format_bytes(bytes)
  defp operation_memory(_operation), do: "No sample"

  defp elapsed(inserted_at) do
    seconds = max(DateTime.diff(Cuckoding.Clock.wall_now(), inserted_at, :second), 0)

    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3_600 -> "#{div(seconds, 60)}m"
      true -> "#{div(seconds, 3_600)}h #{div(rem(seconds, 3_600), 60)}m"
    end
  end

  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()

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
