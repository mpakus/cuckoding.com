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
        workers: Dashboard.workers()
      )

  defp state(nil), do: "Not started"

  defp state(battle),
    do: if(Backoff.pending?(battle), do: "Waiting to retry", else: label(battle.state))

  defp label(value), do: value |> String.replace("_", " ") |> String.capitalize()
  defp elapsed(worker, now), do: max(DateTime.diff(now, worker.started_at), 0)

  @impl true
  def render(assigns) do
    ~H"""
    <section id={@id} class="panel dashboard" aria-labelledby="home-arenas">
      <div class="panel-heading">
        <h2 id="home-arenas">Inside the Arena.</h2>
        <.link navigate={~p"/arenas"} class="text-link">All Arenas ↗</.link>
      </div>
      <div id="dashboard-workers" aria-label="Active battle workers">
        <p :if={@workers == []} class="fine-print">
          No battle worker is running. Open an Arena to create tasks or Start.
        </p>
        <article :for={worker <- @workers} id={"worker-#{worker.id}"} class="worker-row">
          <span class="worker-mark" aria-hidden="true">◇</span>
          <div>
            <.link
              navigate={~p"/arenas/#{worker.arena_id}/tabulae/#{worker.tabula_id}"}
              class="text-link"
            >{worker.arena_name}</.link>
            <p>{worker.binding["name"] || "Local host"} · {label(worker.stage)}</p>
            <p class="fine-print">
              {worker.binding["agent_name"] || "Native service"}
              <span :if={worker.binding["model"]}> · {worker.binding["kind"]} · requested {worker.binding[
                "model"
              ]}</span>
              · {elapsed(worker, @now)}s elapsed
            </p>
          </div>
          <span class="worker-state">Running</span>
        </article>
      </div>
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
