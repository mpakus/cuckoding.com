defmodule CuckodingWeb.RunLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.ActivityComponents
  import CuckodingWeb.AgentFloorComponents
  import CuckodingWeb.PolicyComponents
  import CuckodingWeb.UsageComponents

  alias Cuckoding.AgentFloor

  @refresh_ms 5_000

  @impl true
  def mount(%{"id" => run_id}, _session, socket) do
    case AgentFloor.get_run(run_id) do
      nil ->
        raise Phoenix.Router.NoRouteError, conn: socket, router: CuckodingWeb.Router

      detail ->
        if connected?(socket) do
          Cuckoding.ActivityStream.subscribe(run_id)
          Process.send_after(self(), :refresh_run, @refresh_ms)
        end

        setups = runtime_setups(detail.run)

        {:ok,
         assign(socket,
           page_title: "Run #{detail.run.sequence}",
           detail: detail,
           runtime_setups: setups,
           task_proposals: task_proposals(detail),
           refresh_pending: false,
           notice: "",
           error: nil
         )}
    end
  end

  @impl true
  def handle_info({:activity_event, stream_id, _sequence}, socket) do
    if stream_id == socket.assigns.detail.run.id and not socket.assigns.refresh_pending do
      Process.send_after(self(), :refresh_run_activity, 250)
      {:noreply, assign(socket, refresh_pending: true)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_run, socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_run, @refresh_ms)
    {:noreply, refresh(socket, "Run data updated.")}
  end

  def handle_info(:refresh_run_activity, socket) do
    {:noreply, refresh(socket, "Run activity updated.")}
  end

  @impl true
  def handle_event("start-guided-run", _params, socket) do
    case start_run(socket.assigns.detail) do
      {:ok, :started} ->
        {:noreply,
         socket
         |> refresh(start_notice(socket.assigns.detail))
         |> assign(error: nil)}

      {:error, :run_scoped_auth_required} ->
        {:noreply,
         assign(socket,
           error: "Run-scoped authentication is not ready. Complete the setup below and retry."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, error: start_error(reason))}
    end
  end

  def handle_event("import-task-proposals", params, socket) do
    proposal_ids = Map.get(params, "proposal_ids", [])

    case Cuckoding.BoardTaskIntake.import(socket.assigns.detail.run.id, proposal_ids) do
      {:ok, tasks} ->
        {:noreply,
         socket
         |> refresh("Imported #{length(tasks)} reviewed proposal(s) as Draft tasks.")
         |> assign(error: nil)}

      {:error, :proposal_selection_required} ->
        {:noreply, assign(socket, error: "Select at least one proposal to import.")}

      {:error, reason} ->
        {:noreply, assign(socket, error: "Proposals could not be imported: #{inspect(reason)}")}
    end
  end

  defp refresh(socket, notice) do
    detail = AgentFloor.get_run(socket.assigns.detail.run.id)

    assign(socket,
      detail: detail,
      runtime_setups: runtime_setups(detail.run),
      task_proposals: task_proposals(detail),
      refresh_pending: false,
      notice: notice
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <article aria-labelledby="run-heading" class="space-y-8">
        <.link
          navigate={back_path(@detail)}
          class="inline-flex min-h-10 items-center rounded underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2"
        >
          Back to {back_label(@detail)}
        </.link>

        <header class="space-y-2">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">
            {state_label(@detail.run.state)} run
          </p>
          <h1 id="run-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
            Run {@detail.run.sequence}: {@detail.task.title}
          </h1>
          <p class="text-slate-700">{@detail.project.name} · <code>{@detail.run.branch}</code></p>
        </header>

        <p role="status" aria-live="polite" class="text-sm text-emerald-900">{@notice}</p>
        <p :if={@error} id="run-error" role="alert" class="text-sm font-medium text-red-800">
          {@error}
        </p>

        <section
          :if={intake?(@detail)}
          id="planning-progress"
          aria-labelledby="planning-progress-heading"
          class="rounded-lg border border-slate-300 bg-white p-5"
        >
          <h2 id="planning-progress-heading" class="text-xl font-semibold text-slate-950">
            Planning progress
          </h2>
          <p role="status" aria-live="polite" aria-atomic="true" class="mt-2 text-slate-700">
            {planning_status(@detail)}
          </p>
        </section>

        <.host_runner_notice />

        <section
          :if={@detail.run.state == "queued"}
          id="runtime-setup"
          aria-labelledby="runtime-setup-heading"
          class="space-y-4 rounded-lg border border-amber-300 bg-amber-50 p-5"
        >
          <h2 id="runtime-setup-heading" class="text-xl font-semibold text-amber-950">
            Verify each role before starting
          </h2>
          <article
            :for={setup <- @runtime_setups}
            class="space-y-2 rounded-md border border-amber-200 bg-white/70 p-4 text-sm text-amber-950"
          >
            <h3 class="font-semibold">
              {role_label(setup.role_key)} · {setup[:connection] || setup.runtime}
            </h3>
            <p :if={setup[:connection]}>{setup.runtime}</p>
            <div :if={setup[:home] || setup[:environment]} class="space-y-2">
              <p>In Terminal, use these run-owned runtime directories:</p>
              <dl class="space-y-2">
                <div :for={{name, value} <- runtime_environment(setup)}>
                  <dt class="font-semibold"><code>{name}</code></dt>
                  <dd class="overflow-x-auto rounded bg-white p-2"><code>{value}</code></dd>
                </div>
              </dl>
              <p>Then run this executable with <code>{setup.login_args}</code>:</p>
              <p class="overflow-x-auto rounded bg-white p-2"><code>{setup.executable}</code></p>
            </div>
            <div :if={setup[:helper]} class="space-y-2">
              <p>Claude Code will use the reviewed run-scoped API key helper:</p>
              <p class="overflow-x-auto rounded bg-white p-2"><code>{setup.helper}</code></p>
            </div>
          </article>
          <button
            type="button"
            phx-click="start-guided-run"
            class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            {start_button_label(@detail)}
          </button>
        </section>

        <section
          :if={intake?(@detail) and @task_proposals != []}
          id="task-proposal-review"
          aria-labelledby="task-proposal-review-heading"
          class="space-y-4 rounded-lg border border-slate-300 bg-white p-5"
        >
          <div>
            <h2 id="task-proposal-review-heading" class="text-xl font-semibold text-slate-950">
              Review proposed tasks
            </h2>
            <p class="mt-1 text-sm text-slate-700">
              Agent output is untrusted. Select only the proposals you want added to the board.
            </p>
          </div>
          <form id="task-proposal-form" phx-submit="import-task-proposals" class="space-y-3">
            <label
              :for={proposal <- @task_proposals}
              class="flex gap-3 rounded-md border border-slate-300 p-4"
            >
              <input
                type="checkbox"
                name="proposal_ids[]"
                value={proposal.id}
                checked={is_nil(proposal.imported_task_id)}
                disabled={not is_nil(proposal.imported_task_id)}
                class="mt-1 size-5"
              />
              <span class="min-w-0 space-y-2">
                <span class="block font-semibold text-slate-950">{proposal.title}</span>
                <span class="block text-sm text-slate-700">{proposal.description}</span>
                <span class="block text-sm text-slate-600">Priority {proposal.priority}</span>
                <span class="block text-sm text-slate-600">
                  Sources: {proposal_sources(proposal)}
                </span>
                <span
                  :if={proposal.imported_task_id}
                  class="block text-sm font-medium text-emerald-900"
                >
                  Imported
                </span>
              </span>
            </label>
            <button
              :if={Enum.any?(@task_proposals, &is_nil(&1.imported_task_id))}
              class="min-h-10 rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              Import selected Draft tasks
            </button>
          </form>
        </section>

        <nav aria-label="Run controls" class="flex flex-wrap gap-3">
          <.link
            :for={session <- @detail.sessions}
            navigate={~p"/agents/#{session.id}"}
            class="inline-flex min-h-10 items-center rounded-md bg-slate-950 px-4 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2"
          >
            Inspect {session.adapter_key} agent
          </.link>
          <span :if={@detail.sessions == []} class="text-sm text-slate-700">No agent control is available until a session is recorded.</span>
        </nav>

        <.run_timeline attempts={@detail.attempts} />

        <section aria-labelledby="preview-heading" class="space-y-3">
          <h2 id="preview-heading" class="text-xl font-semibold text-slate-950">Preview</h2>
          <a
            :if={@detail.environment && @detail.environment.preview_url}
            href={@detail.environment.preview_url}
            target="_blank"
            rel="noreferrer"
            class="inline-flex min-h-10 items-center rounded underline underline-offset-4 focus-visible:outline-2 focus-visible:outline-offset-2"
          >Open loopback preview</a>
          <p
            :if={!@detail.environment || !@detail.environment.preview_url}
            class="text-sm text-slate-700"
          >
            No preview is active.
          </p>
        </section>

        <section aria-labelledby="artifacts-heading" class="space-y-3">
          <h2 id="artifacts-heading" class="text-xl font-semibold text-slate-950">Artifacts</h2>
          <p :if={@detail.artifacts == []} class="text-sm text-slate-700">
            No durable artifacts recorded.
          </p>
          <ul class="divide-y divide-slate-200 rounded-lg border border-slate-300 bg-white">
            <li :for={artifact <- @detail.artifacts} class="flex justify-between gap-4 px-4 py-3">
              <span>{artifact.name}</span><span class="text-slate-600">{artifact.size} bytes</span>
            </li>
          </ul>
        </section>

        <section aria-labelledby="findings-heading" class="space-y-3">
          <h2 id="findings-heading" class="text-xl font-semibold text-slate-950">Findings</h2>
          <p :if={@detail.findings == []} class="text-sm text-slate-700">No findings recorded.</p>
          <ul class="space-y-2">
            <li
              :for={finding <- @detail.findings}
              class="rounded-md border border-slate-300 bg-white p-4"
            >
              <span class="font-semibold">{String.capitalize(finding.severity)}:</span> {finding.summary}
              <span class="text-slate-600">({finding.status})</span>
            </li>
          </ul>
        </section>

        <.usage_summary records={@detail.usage} />
        <.resource_history samples={@detail.resources} />

        <section
          aria-labelledby="knowledge-heading"
          class="rounded-lg border border-dashed border-slate-400 p-5"
        >
          <h2 id="knowledge-heading" class="text-xl font-semibold text-slate-950">Knowledge</h2>
          <p class="mt-2 text-sm text-slate-700">
            Project knowledge usage will appear here after Phase 7 publication and citation records are available.
          </p>
        </section>

        <section aria-labelledby="plugins-heading" class="space-y-3">
          <h2 id="plugins-heading" class="text-xl font-semibold text-slate-950">Plugins</h2>
          <p
            :if={plugin_entries(@detail.run.plugin_snapshot_json) == []}
            class="text-sm text-slate-700"
          >
            No plugins were captured in this run snapshot.
          </p>
          <ul class="list-disc pl-5">
            <li :for={plugin <- plugin_entries(@detail.run.plugin_snapshot_json)}>
              <span class="font-medium">{plugin.key}</span>
              <span :if={plugin.contribution}>: {plugin.contribution} ({plugin.source})</span>
            </li>
          </ul>
          <ul :if={@detail.optimizations != []} class="space-y-2">
            <li :for={record <- @detail.optimizations}>
              {record.plugin_key}: {Cuckoding.Telemetry.Accounting.optimization_label(record)} {record.kind}
            </li>
          </ul>
        </section>

        <.activity_stream events={@detail.activity} status={activity_status(@detail.activity)} />
      </article>
    </Layouts.app>
    """
  end

  defp activity_status(events),
    do: Cuckoding.ActivityStream.status(events, Cuckoding.Clock.wall_now(), 60_000)

  defp plugin_entries(snapshot) when is_map(snapshot) do
    snapshot
    |> Enum.map(fn {key, value} ->
      %{
        key: key,
        contribution: is_map(value) && value["contribution"],
        source: (is_map(value) && value["source"]) || "unlabeled"
      }
    end)
    |> Enum.sort_by(& &1.key)
  end

  defp plugin_entries(snapshot) when is_list(snapshot) do
    Enum.map(snapshot, &%{key: to_string(&1), contribution: nil, source: "unlabeled"})
  end

  defp plugin_entries(_snapshot), do: []
  defp state_label(state), do: state |> String.replace("_", " ") |> String.capitalize()

  defp runtime_setups(%{state: "queued", id: run_id}) do
    case Cuckoding.WalkingSkeleton.load(run_id) do
      {:ok, %{task: %{kind: "board_intake"}}} ->
        case Cuckoding.BoardTaskIntake.runtime_setup(run_id) do
          {:ok, setup} -> [setup]
          {:error, _reason} -> [%{role_key: "configured", runtime: "configured runtime"}]
        end

      _other ->
        case Cuckoding.GuidedRun.runtime_setups(run_id) do
          {:ok, setups} -> setups
          {:error, _reason} -> [%{role_key: "configured", runtime: "configured runtime"}]
        end
    end
  end

  defp runtime_setups(_run), do: []

  defp role_label(role_key), do: role_key |> String.replace("_", " ") |> String.capitalize()

  defp runtime_environment(%{environment: environment}) when is_map(environment),
    do: Enum.sort(environment)

  defp runtime_environment(%{home: home}), do: [{"CODEX_HOME", home}]
  defp runtime_environment(_setup), do: []

  defp start_error(%Cuckoding.Adapters.Types.Error{code: :not_installed}),
    do: "The configured runtime executable is unavailable."

  defp start_error(%Cuckoding.Adapters.Types.Error{code: :unsupported_version}),
    do: "The configured runtime version is not supported by this build."

  defp start_error(:run_not_queued), do: "This run has already started."
  defp start_error(_reason), do: "The workflow could not start. Inspect runtime setup and retry."

  defp start_run(%{task: %{kind: "board_intake"}, run: run}),
    do: Cuckoding.BoardTaskIntake.start(run.id)

  defp start_run(%{run: run}), do: Cuckoding.GuidedRun.start(run.id)

  defp start_notice(%{task: %{kind: "board_intake"}}),
    do: "Task-planning agent started. Durable proposals will appear here for review."

  defp start_notice(_detail), do: "Workflow started. Durable progress will appear here."

  defp task_proposals(%{task: %{kind: "board_intake"}, run: run}) do
    case Cuckoding.BoardTaskIntake.proposals(run.id) do
      {:ok, proposals} -> proposals
      {:error, _reason} -> []
    end
  end

  defp task_proposals(_detail), do: []
  defp intake?(%{task: %{kind: "board_intake"}}), do: true
  defp intake?(_detail), do: false

  defp planning_status(%{run: %{state: "queued"}}),
    do: "Planning run created. Verify agent authentication below, then start analysis."

  defp planning_status(%{run: %{state: "running"}}),
    do: "The agent is analyzing the project. This page updates automatically."

  defp planning_status(%{run: %{state: "waiting"}}),
    do: "Analysis finished. Review the proposed tasks below."

  defp planning_status(%{run: %{state: "done"}}),
    do: "Planning complete. Selected proposals are now Draft tasks on the board."

  defp planning_status(%{run: %{state: state}}) when state in ["blocked", "failed"],
    do: "Planning stopped and needs attention. Review the error and recent activity below."

  defp planning_status(%{run: %{state: "cancelled"}}), do: "Planning was cancelled."
  defp planning_status(_detail), do: "Planning status is updating."
  defp back_path(%{task: %{kind: "board_intake"}, board: board}), do: ~p"/boards/#{board.id}"
  defp back_path(detail), do: ~p"/boards/#{detail.board.id}/tasks/#{detail.task.id}"
  defp back_label(%{task: %{kind: "board_intake"}}), do: "board"
  defp back_label(detail), do: detail.task.title

  defp start_button_label(%{task: %{kind: "board_intake"}}),
    do: "Check authentication and analyze project"

  defp start_button_label(_detail), do: "Check authentication and start workflow"

  defp proposal_sources(proposal) do
    proposal.source_json
    |> Map.get("sources", [])
    |> Enum.map_join(", ", fn source ->
      case source["line"] do
        line when is_integer(line) -> "#{source["path"]}:#{line}"
        _missing -> source["path"]
      end
    end)
  end
end
