defmodule CuckodingWeb.TaskEvidenceComponent do
  @moduledoc false
  use CuckodingWeb, :live_component
  alias Cuckoding.Battles.Evidence

  @impl true
  def mount(socket) do
    {:ok, socket |> reset(nil) |> CuckodingWeb.SessionAuth.guard_events()}
  end

  @impl true
  def update(assigns, socket) do
    scope = {assigns.board.id, assigns.task_id}
    socket = if socket.assigns[:scope] != scope, do: reset(socket, nil), else: socket
    {:ok, socket |> assign(assigns) |> assign(:scope, scope) |> reload()}
  end

  @impl true
  def handle_event("latest", _, socket), do: {:noreply, socket |> reset(nil) |> reload()}

  def handle_event("earlier", _, %{assigns: %{earlier: run}} = socket) when not is_nil(run),
    do: {:noreply, socket |> reset(run.battle_id) |> reload()}

  def handle_event("older", _, socket) do
    a = socket.assigns

    if a.page.more? do
      {:noreply,
       socket
       |> assign(cursors: [List.last(a.page.rows) | a.cursors], page: nil)
       |> reload()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("newer", _, %{assigns: %{cursors: [_, _ | _] = cursors}} = socket),
    do: {:noreply, socket |> assign(cursors: tl(cursors), page: nil) |> reload()}

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp reset(socket, id),
    do: assign(socket, run_id: id, run: nil, earlier: nil, cursors: [nil], page: nil)

  defp reload(socket) do
    a = socket.assigns
    run = Evidence.run(a.board.arena_id, a.board.id, a.task_id, a.run_id)

    if run do
      page =
        if is_nil(a.page) or length(a.cursors) == 1,
          do:
            Evidence.attempts(
              a.board.arena_id,
              a.board.id,
              a.task_id,
              run.battle_id,
              hd(a.cursors)
            ),
          else: a.page

      assign(socket,
        run_id: run.battle_id,
        run: run,
        earlier: Evidence.earlier(a.board.arena_id, a.board.id, a.task_id, run.battle_id),
        page: page
      )
    else
      assign(socket, run: nil, earlier: nil, page: %{rows: [], more?: false})
    end
  end

  defp label(nil), do: "Unknown"
  defp label(value), do: value |> String.replace("_", " ") |> String.capitalize()

  defp stage_label(attempt),
    do:
      if(Cuckoding.Workflows.custom_key?(attempt.stage),
        do: "Read stage · #{attempt.binding["name"]}",
        else: label(attempt.stage)
      )

  defp download_path(assigns) do
    query = if hd(assigns.cursors), do: %{before: hd(assigns.cursors).id}, else: %{}

    ~p"/arenas/#{assigns.board.arena_id}/tabulae/#{assigns.board.id}/tasks/#{assigns.task_id}/executions/#{assigns.run.battle_id}/evidence.json?#{query}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <details
      id={@id}
      class="task-evidence"
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
    >
      <summary>Execution history</summary>
      <p :if={!@run} class="fine-print">This task has not been included in a battle.</p>
      <div :if={@run}>
        <p class="fine-print">
          Battle {label(@run.battle_state)} · task {label(@run.task_state)} · review round {@run.review_round} · {Calendar.strftime(
            @run.started_at,
            "%Y-%m-%d %H:%M:%S UTC"
          )}
        </p>
        <p class="fine-print draft-copy">Battle receipt: <code>{@run.battle_id}</code></p>
        <div class="team-actions" aria-label="Task executions">
          <button
            type="button"
            class="button"
            phx-target={@myself}
            phx-click="earlier"
            disabled={!@earlier}
          >Earlier execution</button>
          <button type="button" class="button" phx-target={@myself} phx-click="latest">Latest execution</button>
          <a class="button" href={download_path(assigns)} download>Download evidence · JSON</a>
        </div>
        <p :if={@dirty || @run.snapshot["revision"] != @draft_revision} class="notice">
          The draft below differs from this frozen execution. Its saved evidence is unchanged.
        </p>
        <details id={@id <> "-scope"} phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
          <summary>Frozen specification · revision {@run.snapshot["revision"]}</summary>
          <p class="draft-copy">{@run.snapshot["description"]}</p>
          <p class="draft-copy">{@run.snapshot["criteria"]}</p>
          <p class="fine-print draft-copy">
            Criteria SHA-256: <code>{@run.snapshot["criteria_sha256"]}</code>
          </p>
        </details>
        <p class="fine-print">
          Public task-stage receipts, newest first. Reports and retained edits do not establish
          completion by themselves. Recovery observations and final review stay in Inspect battle.
        </p>
        <p :if={length(@cursors) > 1} class="fine-print">
          Reading saved attempts. Newer attempts stay on the latest page.
        </p>
        <p :if={@page.rows == []} class="fine-print">
          No task-stage attempt recorded in this execution.
        </p>
        <details
          :for={{attempt, index} <- Enum.with_index(@page.rows)}
          id={"task-evidence-#{attempt.id}"}
          class="team-role"
          open={index == 0}
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>
            {stage_label(attempt)} · {label(attempt.state)} · {Calendar.strftime(
              attempt.started_at,
              "%H:%M:%S UTC"
            )}
          </summary>
          <p class="fine-print">
            {attempt.binding["name"] || "Local host"} · {attempt.binding["agent_name"] ||
              "Native service"}
            <span :if={attempt.binding["model"]}> · {attempt.binding["kind"]} · requested {attempt.binding[
              "model"
            ]}</span>
            · {Calendar.strftime(attempt.started_at, "%H:%M:%S UTC")}
          </p>
          <p :if={attempt.result["provider"]["observed_model"]} class="fine-print">
            Reported runtime model: {attempt.result["provider"]["observed_model"]}
          </p>
          <p :if={attempt.state in ~w(expired interrupted cancelled failed)} class="notice">
            Retained evidence; this is not an accepted completion receipt.
          </p>
          <p :if={attempt.result["status"]} class="fine-print">
            Reported result: {label(attempt.result["status"])}
          </p>
          <p :if={attempt.result["summary"]} class="draft-copy">{attempt.result["summary"]}</p>
          <p
            :if={
              attempt.result["feedback"] && attempt.result["feedback"] != attempt.result["summary"]
            }
            class="draft-copy"
          >
            Review feedback: {attempt.result["feedback"]}
          </p>
          <p :if={attempt.result["candidate_sha"]} class="fine-print draft-copy">
            Candidate: <code>{attempt.result["candidate_sha"]}</code>
          </p>
          <details
            :if={attempt.result["provider"]["tools"] != []}
            id={"task-tools-#{attempt.id}"}
            phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
          >
            <summary>
              File inspection and edits · {length(attempt.result["provider"]["tools"])}
            </summary>
            <ul>
              <li :for={tool <- attempt.result["provider"]["tools"]} class="draft-copy">
                {label(tool["tool"])} · {label(tool["status"])} · <code>{tool["path"]}</code>
                <span :if={tool["sha256"]}> · SHA-256 <code>{tool["sha256"]}</code></span>
              </li>
            </ul>
          </details>
          <ul :if={attempt.result["provider"]["changes"] != []}>
            <li :for={change <- attempt.result["provider"]["changes"]} class="draft-copy">
              Retained edit: <code>{change["path"]}</code> · SHA-256 <code>{change["sha256"]}</code>
            </li>
          </ul>
          <ul :if={attempt.result["checks"] != []}>
            <li :for={check <- attempt.result["checks"]} class="draft-copy">
              Check {check["id"]} · {label(check["status"])} · exit {check["exit_code"]}
              <span :if={check["stdout_sha256"]}> · output SHA-256 <code>{check["stdout_sha256"]}</code></span>
            </li>
          </ul>
          <p class="fine-print draft-copy">
            Attempt: <code>{attempt.id}</code>
            · cleanup {if attempt.result["cleanup_verified"] == true,
              do: "verified",
              else: "unverified"}
          </p>
        </details>
        <div
          :if={@page.more? || length(@cursors) > 1}
          class="team-actions"
          aria-label="Task attempt pages"
        >
          <button
            type="button"
            class="button"
            phx-target={@myself}
            id={@id <> "-newer"}
            phx-click={
              Phoenix.LiveView.JS.push("newer") |> Phoenix.LiveView.JS.focus(to: "##{@id}-page")
            }
            disabled={length(@cursors) == 1}
          >Newer attempts</button>
          <span id={@id <> "-page"} tabindex="-1" aria-live="polite" aria-atomic="true">Page {length(
            @cursors
          )}</span>
          <button
            type="button"
            class="button"
            phx-target={@myself}
            id={@id <> "-older"}
            phx-click={
              Phoenix.LiveView.JS.push("older") |> Phoenix.LiveView.JS.focus(to: "##{@id}-page")
            }
            disabled={!@page.more?}
          >Older attempts</button>
        </div>
      </div>
    </details>
    """
  end
end
