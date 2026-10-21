defmodule CuckodingWeb.DashboardComponent do
  @moduledoc false
  use CuckodingWeb, :live_component
  alias Cuckoding.Battles.Backoff
  alias Cuckoding.Dashboard

  @impl true
  def mount(socket) do
    {:ok, socket |> assign(page_number: 0) |> CuckodingWeb.SessionAuth.guard_events()}
  end

  @impl true
  def update(assigns, socket), do: {:ok, socket |> assign(assigns) |> reload()}

  @impl true
  def handle_event("older-arenas", _, socket) do
    page = socket.assigns.page_number + if(socket.assigns.page.more?, do: 1, else: 0)
    {:noreply, socket |> assign(:page_number, page) |> reload()}
  end

  def handle_event("newer-arenas", _, socket),
    do:
      {:noreply,
       socket |> assign(:page_number, max(socket.assigns.page_number - 1, 0)) |> reload()}

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp reload(socket),
    do:
      assign(socket,
        page: Dashboard.arenas(socket.assigns.page_number),
        work: Dashboard.work()
      )

  defp state(nil), do: "Not started"

  defp state(battle),
    do: if(Backoff.pending?(battle), do: "Waiting to retry", else: label(battle.state))

  defp label(value), do: value |> String.replace("_", " ") |> String.capitalize()
  defp elapsed(worker, now), do: max(DateTime.diff(now, worker.started_at), 0)

  defp work_state("pending"), do: "Queued"
  defp work_state("cancelling"), do: "Finishing cleanup"
  defp work_state(_), do: "Running"

  defp work_label("plan_tabula"), do: "Creating tasks"
  defp work_label("discover_tools"), do: "Finding installed agents"
  defp work_label("preview_documents"), do: "Reading selected documents"
  defp work_label("accept_spec"), do: "Saving specification"
  defp work_label("choose_arena_folder"), do: "Choosing project folder"
  defp work_label("disconnect_agent"), do: "Disconnecting agent"
  defp work_label("probe_" <> _), do: "Checking executable"
  defp work_label("inspect_codex"), do: "Checking connection"
  defp work_label("inspect_cursor"), do: "Checking connection"
  defp work_label("login_" <> _), do: "Authorizing account"
  defp work_label("logout_" <> _), do: "Signing out"
  defp work_label("check_codex_model"), do: "Checking model access"
  defp work_label("check_codex_isolation"), do: "Checking isolation"
  defp work_label(value), do: label(value)

  defp work_path(%{arena_id: arena, tabula_id: board})
       when not is_nil(arena) and not is_nil(board),
       do: ~p"/arenas/#{arena}/tabulae/#{board}"

  defp work_path(%{arena_id: arena}) when not is_nil(arena), do: ~p"/arenas/#{arena}"
  defp work_path(%{agent_id: "codex"}), do: ~p"/agents/codex"

  defp work_path(%{agent_id: id}) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> ~p"/agents/#{id}"
      _ -> ~p"/agents"
    end
  end

  attr :id, :string, required: true
  attr :work, :map, required: true
  attr :now, :any, required: true
  attr :scoped, :boolean, default: false

  def work_rows(assigns) do
    ~H"""
    <div id={@id} aria-label="Saved active work">
      <p :if={@work.rows == []} class="fine-print">
        No active work is recorded{if @scoped, do: " for this board", else: ""}.
      </p>
      <article :for={worker <- @work.rows} id={@id <> "-" <> worker.id} class="worker-row">
        <span class="worker-mark" aria-hidden="true">◇</span>
        <div>
          <.link navigate={work_path(worker)} class="text-link">
            {worker.arena_name || worker.binding["agent_name"] || "Local setup"}
          </.link>
          <p>{worker.binding["name"] || "Local host"} · {work_label(worker.stage)}</p>
          <p class="fine-print">
            {worker.binding["agent_name"] || "Native service"}
            <span :if={worker.binding["kind"]}> · {worker.binding["kind"]}</span>
            <span :if={worker.binding["model"]}> · requested {worker.binding["model"]}</span>
            · {elapsed(worker, @now)}s since queued
          </p>
        </div>
        <span class="worker-state">{work_state(worker.state)}</span>
      </article>
      <p :if={@work.more?} class="fine-print">
        Showing the oldest 20 active records. Open Agents or an Arena for more.
      </p>
      <p :if={@work.rows != []} class="fine-print">
        Saved state and wall time; this does not prove a process is still running.
      </p>
    </div>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="panel dashboard" aria-labelledby="home-arenas">
      <div class="panel-heading">
        <h2 id="home-arenas">Inside the Arena.</h2>
        <.link navigate={~p"/arenas"} class="text-link">All Arenas ↗</.link>
      </div>
      <.work_rows id="dashboard-workers" work={@work} now={@now} />
      <div class="dashboard-arenas">
        <article :for={row <- @page.rows} id={"arena-#{row.arena.id}"} class="arena-summary">
          <div class="panel-heading">
            <h3>{row.arena.name}</h3><span class="worker-state">{state(row.battle)}</span>
          </div>
          <p class="fine-print">
            {if row.battle,
              do: "#{row.completed} / #{row.total} battle tasks completed",
              else: "#{row.total} saved #{if row.total == 1, do: "task", else: "tasks"}"}
          </p>
          <progress
            :if={row.battle && row.total > 0}
            value={row.completed}
            max={row.total}
            aria-label={"#{row.arena.name} task completion"}
          >{row.completed} / {row.total}</progress>
          <p
            :if={row.battle && row.battle.state == "needs_attention" && !Backoff.pending?(row.battle)}
            class="fine-print"
          >
            Needs attention · {label(row.battle.reason || "inspect saved result")}
          </p>
          <.link
            navigate={
              if row.board,
                do: ~p"/arenas/#{row.arena.id}/tabulae/#{row.board.id}",
                else: ~p"/arenas/#{row.arena.id}"
            }
            class="button"
          >Open Arena ↗</.link>
        </article>
      </div>
      <div :if={@page.more? || @page_number > 0} class="team-actions" aria-label="Arena pages">
        <button
          type="button"
          class="button"
          phx-click="newer-arenas"
          phx-target={@myself}
          disabled={@page_number == 0}
        >Newer Arenas</button>
        <span>Page {@page_number + 1}</span>
        <button
          type="button"
          class="button"
          phx-click="older-arenas"
          phx-target={@myself}
          disabled={!@page.more?}
        >Older Arenas</button>
      </div>
      <.live_component
        module={CuckodingWeb.ActivityComponent}
        id="workspace-activity"
        arena_id={nil}
        session_id={@session_id}
        now={@now}
      />
    </section>
    """
  end
end
