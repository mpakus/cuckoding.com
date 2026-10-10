defmodule CuckodingWeb.BattlePreviewLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.BattlePreview
  alias CuckodingWeb.Layouts

  @impl true
  def mount(%{"arena_id" => arena_id, "id" => id}, _, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
    {:ok, socket |> assign(arena_id: arena_id, board_id: id, timer: nil) |> refresh()}
  end

  defp refresh(socket) do
    case BattlePreview.inspect(socket.assigns.arena_id, socket.assigns.board_id) do
      {:ok, preview} ->
        if socket.assigns.timer, do: Process.cancel_timer(socket.assigns.timer)
        generation = make_ref()

        timer =
          if connected?(socket),
            do: Process.send_after(self(), {:preview_expired, generation}, 60_000)

        assign(socket, preview: preview, stale: nil, generation: generation, timer: timer)

      {:error, _} ->
        redirect(socket, to: "/arenas")
    end
  end

  @impl true
  def handle_event("refresh", _, socket), do: {:noreply, refresh(socket)}
  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:updated, socket), do: {:noreply, assign(socket, :stale, :changed)}

  def handle_info({:preview_expired, generation}, socket) do
    if generation == socket.assigns.generation,
      do: {:noreply, assign(socket, :stale, socket.assigns.stale || :expired)},
      else: {:noreply, socket}
  end

  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  defp label(:unaccepted), do: "Specification needed"
  defp label(:outdated), do: "Prerequisite changed · specification outdated"
  defp label(:artifact_unavailable), do: "Accepted Markdown missing or changed"
  defp label(:accepted), do: "Accepted Markdown verified"
  defp label(:unassigned), do: "Choose an agent and model"
  defp label(:version_required), do: "Check agent version"
  defp label(:connection_required), do: "Refresh connection"
  defp label(:sign_in_required), do: "Sign in to agent"
  defp label(:catalog_stale), do: "Refresh model catalog"
  defp label(:model_missing), do: "Saved model missing from catalog"
  defp label(:model_changed), do: "Saved model changed · reassign explicitly"
  defp label(:check_passed), do: "Model diagnostic passed · repository grant unverified"
  defp label(:untested), do: "Catalog binding available · model access untested"
  defp label(:not_inspected), do: "Inspect Git in Repository setup"
  defp label(:busy), do: "Git operation active · inspect or cancel in Repository setup"
  defp label(:failed), do: "Last Git operation did not confirm a baseline · inspect again"
  defp label(:expired), do: "Git observation expired · inspect again"
  defp label(:observed), do: "Committed HEAD observed"
  defp label(:missing), do: "Git missing · initialize with confirmation in Repository setup"
  defp label(:no_commit), do: "Initial commit needed · preview and confirm in Repository setup"

  defp dependency(tasks, id), do: Enum.find(tasks, &(&1.id == id))

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={:arenas} title={@preview.arena.name} flash={@flash}>
      <section class="panel" aria-labelledby="battle-preview-title">
        <p class="eyebrow">BATTLE PREVIEW · {@preview.board.name}</p>
        <h2 id="battle-preview-title">Inspect the preparation.</h2>
        <p id="execution-unavailable" class="notice">
          Battle execution is not available yet. Review preparation here; no work will start.
        </p>
        <p class="fine-print">
          This reads saved settings and verifies accepted Markdown. It starts no agent,
          reads no Arena files and runs no check or Git command. These observations do not reserve a battle.
        </p>
        <div class="team-actions">
          <button id="refresh-preview" type="button" class="button" phx-click="refresh">Refresh preview</button>
          <.link
            navigate={~p"/arenas/#{@preview.arena.id}/tabulae/#{@preview.board.id}"}
            class="text-link"
          >Back to Tabula ↗</.link>
        </div>
        <p id="preview-time" class="fine-print">
          Observed {Calendar.strftime(@preview.checked_at, "%Y-%m-%d %H:%M:%S UTC")}
        </p>
        <p :if={@stale} id="preview-stale" role="status" class="notice">
          {if @stale == :changed,
            do: "Saved state changed.",
            else: "This preview is over a minute old."} Refresh to inspect current evidence. The details below show the earlier observation.
        </p>
        <p :if={@preview.busy} role="status">
          A setup operation was active at preview time. Inspect its controls on the originating page.
        </p>
        <details
          id="preview-git"
          class="team-role"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Git baseline · {label(@preview.git.status)}</summary>
          <p :if={@preview.git.head} class="arena-path">Last observed HEAD: {@preview.git.head}</p>
          <p :if={@preview.git.at} class="fine-print">
            {Calendar.strftime(@preview.git.at, "%Y-%m-%d %H:%M:%S UTC")} · {@preview.git.result}
          </p>
          <p class="fine-print">
            A recorded HEAD does not prove clean files or the current repository state. Start must revalidate it.
          </p>
          <.link navigate={~p"/arenas/#{@preview.arena.id}" <> "#arena-git"} class="text-link">Repository setup ↗</.link>
        </details>
        <details
          id="preview-team"
          class="team-role"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Assigned team · revision {@preview.team_revision}</summary>
          <article
            :for={role <- @preview.roles}
            id={"preview-role-#{role.definition["id"]}"}
            class="team-role"
          >
            <h3>{role.definition["name"]}</h3>
            <p>{label(role.status)}</p>
            <p class="arena-path">
              {if role.definition["agent"] == "",
                do: "No agent",
                else: Cuckoding.Agents.display(role.definition["agent"])} · {if role.definition[
                                                                                  "model"
                                                                                ] ==
                                                                                  "",
                                                                                do: "No model",
                                                                                else:
                                                                                  role.definition[
                                                                                    "model"
                                                                                  ]}
            </p>
            <p :if={!role.required} class="fine-print">
              Custom role · planning only; no execution slot or grant.
            </p>
          </article>
          <p class="fine-print">
            This is the Tabula's saved team. Changing defaults alone does not replace it.
          </p>
          <.link navigate={~p"/team"} class="text-link">Edit default team ↗</.link>
          <.link navigate={~p"/settings"} class="text-link">Agents ↗</.link>
          <.link
            navigate={~p"/arenas/#{@preview.arena.id}/tabulae/#{@preview.board.id}"}
            class="text-link"
          >Review or adopt team on Tabula ↗</.link>
        </details>
        <details
          id="preview-tasks"
          class="team-role"
          open
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Saved tasks · {length(@preview.tasks)}</summary>
          <p :if={@preview.tasks == []}>No saved tasks. Describe work or add a task on the Tabula.</p>
          <p class="fine-print">
            All saved tasks are shown; no battle membership is frozen. Specifications can be
            accepted during planning. Future Start authority will also cover Speculator preparation.
            Prerequisites describe order, not completed work.
          </p>
          <article :for={task <- @preview.tasks} id={"preview-task-#{task.id}"} class="team-role">
            <h3>{task.title}</h3>
            <p>
              Revision {task.revision} · {if task.column == "todo", do: "ToDo", else: "Specs"} · {label(
                task.spec.status
              )}
            </p>
            <p :if={task.depends_on == []} class="fine-print">No prerequisites.</p>
            <ul :if={task.depends_on != []}>
              <li :for={id <- task.depends_on} class="draft-copy">
                {case dependency(@preview.tasks, id) do
                  nil -> "Prerequisite unavailable"
                  task -> "#{task.title} · revision #{task.revision} · #{label(task.spec.status)}"
                end}
              </li>
            </ul>
            <p :if={task.spec.id} class="arena-path">
              Acceptance: {task.spec.id}<br />SHA-256: {task.spec.sha256}
            </p>
            <.link
              :if={task.spec.status == :accepted}
              href={~p"/specifications/#{task.spec.id}/download"}
              class="text-link"
            >Download verified Markdown ↗</.link>
          </article>
        </details>
        <details
          id="preview-checks"
          class="team-role"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>
            Project checks · revision {@preview.checks.revision} · {length(
              @preview.checks.definition["checks"]
            )} saved
          </summary>
          <p :if={@preview.checks.definition["checks"] == []}>
            No checks declared. An empty list is not passing verification.
          </p>
          <article :for={check <- @preview.checks.definition["checks"]} class="team-role">
            <h3>{check["name"]}</h3>
            <pre class="draft-copy">{Jason.encode!([check["executable"] | check["arguments"]])}</pre>
            <p class="arena-path">
              Directory: {check["directory"]} · timeout {check["timeout_seconds"]}s
            </p>
          </article>
          <p class="fine-print">
            Declarations only. Executable identity, worktree paths and permissions have not been verified; no check result exists.
          </p>
          <.link navigate={~p"/arenas/#{@preview.arena.id}/checks"} class="text-link">Edit project checks ↗</.link>
        </details>
      </section>
    </Layouts.workspace>
    """
  end
end
