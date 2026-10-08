defmodule CuckodingWeb.SpecificationComponent do
  @moduledoc false
  use Phoenix.LiveComponent
  use CuckodingWeb, :verified_routes
  alias Cuckoding.{Foundation, Specifications}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(preview: nil, confirmed: false, key: Ecto.UUID.generate(), error: nil)
     |> CuckodingWeb.SessionAuth.guard_events()}
  end

  @impl true
  def update(assigns, socket) do
    changed =
      socket.assigns[:task_id] != assigns.task_id or socket.assigns[:revision] != assigns.revision

    socket = assign(socket, assigns)

    socket =
      if changed, do: assign(socket, preview: nil, confirmed: false, error: nil), else: socket

    {:ok, refresh(socket)}
  end

  defp refresh(socket) do
    a = socket.assigns
    history = Specifications.history(a.board.id, a.task_id)
    preview_current = a.preview != nil and not a.dirty and Specifications.unchanged?(a.preview)

    assign(socket,
      history: history,
      active: Enum.find(history, &(&1.state in ~w(pending running cancelling))),
      preview_current: preview_current,
      confirmed: a.confirmed and preview_current,
      busy: Foundation.pending?()
    )
  end

  @impl true
  def handle_event("preview", _, socket) do
    a = socket.assigns

    result =
      if a.dirty,
        do: {:error, "unsaved"},
        else: Specifications.preview(a.board.arena_id, a.board.id, a.task_id, a.revision)

    socket =
      case result do
        {:ok, preview} -> assign(socket, preview: preview, confirmed: false, error: nil)
        {:error, reason} -> assign(socket, preview: nil, confirmed: false, error: message(reason))
      end

    {:noreply, refresh(socket)}
  end

  def handle_event("change", params, socket), do: {:noreply, input(socket, params)}

  def handle_event("accept", params, socket) do
    socket = input(socket, params)
    a = socket.assigns

    result =
      Specifications.request(
        a.key,
        a.board.arena_id,
        a.board.id,
        a.task_id,
        a.revision,
        if(a.preview, do: a.preview["sha256"]),
        a.confirmed
      )

    error =
      case result do
        {:ok, _} -> nil
        {:error, reason} -> message(reason)
      end

    {:noreply,
     socket |> assign(confirmed: false, key: Ecto.UUID.generate(), error: error) |> refresh()}
  end

  def handle_event("cancel", _, socket) do
    if socket.assigns.active, do: Foundation.cancel_probe(socket.assigns.active.id)
    {:noreply, refresh(socket)}
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp input(socket, params) do
    socket = refresh(socket)
    a = socket.assigns

    confirmed =
      a.preview_current and params["confirmed"] == "true" and
        params["sha256"] == a.preview["sha256"]

    assign(socket, :confirmed, confirmed)
  end

  defp message("criteria_required"),
    do: "Save a description and acceptance criteria before previewing a specification."

  defp message("unsaved"), do: "Save your edits before previewing a specification."
  defp message("setup_busy"), do: "Finish or cancel the active operation first."

  defp message("already_accepted"),
    do: "This task revision already has an accepted specification."

  defp message("confirmation_required"), do: "Review the exact preview and confirm acceptance."

  defp message(status) when status in ~w(stale_task preview_changed),
    do: "The task or a prerequisite changed. Reload the task and preview again."

  defp message("accepted"),
    do: "Specification accepted and saved in ToDo. Reload the task to edit its current revision."

  defp message("cancelled"),
    do: "Acceptance cancelled. Any partial artifact is retained; the task was not moved."

  defp message(_),
    do:
      "Specification unavailable or interrupted. Files are retained; nothing will replay. Preview again to try a new acceptance."

  @impl true
  def render(assigns) do
    ~H"""
    <details id={@id} phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
      <summary>Accepted specifications</summary>
      <p class="fine-print">
        Save an exact Markdown specification in Cuckoding's private storage and move this task to ToDo.
        Your Arena files stay untouched. Acceptance does not authorize an agent or start a battle.
      </p>
      <p :if={@dirty} role="status">Save your edits before previewing a specification.</p>
      <button
        class="button"
        type="button"
        phx-click="preview"
        phx-target={@myself}
        disabled={@dirty || @busy}
      >Preview specification</button>
      <p :if={@error} id="spec-error" role="alert" class="notice">{@error}</p>
      <div :if={@preview} id="spec-preview">
        <p class="fine-print">
          Draft revision {@preview["draft_revision"]} · {byte_size(@preview["markdown"])} bytes · SHA-256: {@preview[
            "sha256"
          ]}
        </p>
        <details id="spec-preview-text" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
          <summary>Exact Markdown text</summary>
          <pre class="draft-copy">{@preview["markdown"]}</pre>
        </details>
        <p :if={!@preview_current} role="status">
          Preview is no longer current. Reload the task and preview again.
        </p>
        <.form
          for={%{}}
          id="spec-accept-form"
          phx-change="change"
          phx-submit="accept"
          phx-target={@myself}
        >
          <input type="hidden" name="sha256" value={@preview["sha256"]} />
          <label class="confirm-executable">
            <input
              name="confirmed"
              type="checkbox"
              value="true"
              checked={@confirmed}
              disabled={!@preview_current || @busy}
            /> I accept this exact task specification and its prerequisite revisions.
          </label>
          <button class="button" disabled={!@preview_current || @busy} phx-disable-with="Saving…">Accept specification</button>
        </.form>
      </div>
      <div :if={@active} role="status" class="notice">
        <p>Specification · {@active.state} · {max(0, DateTime.diff(@now, @active.inserted_at))}s</p>
        <p class="fine-print">Owner: you · local file writer · no agent or model</p>
        <button
          type="button"
          class="button"
          phx-click="cancel"
          phx-target={@myself}
          disabled={@active.state == "cancelling"}
        >Cancel acceptance</button>
      </div>
      <article :for={spec <- @history} id={"spec-#{spec.id}"} class="team-role">
        <p>
          Draft revision {spec.payload["draft_revision"]} · {spec.state} · {Calendar.strftime(
            spec.inserted_at,
            "%Y-%m-%d %H:%M UTC"
          )}
        </p>
        <p :if={spec.state not in ~w(pending running cancelling)}>{message(spec.result)}</p>
        <div :if={spec.state == "completed"}>
          <p>
            {if Specifications.current?(spec),
              do: "Accepted task and prerequisite revisions are current.",
              else:
                "Historical specification: the task or a prerequisite has changed. Accept a new preview before future execution."}
          </p>
          <.link href={~p"/specifications/#{spec.id}/download"} class="button">Download Markdown</.link>
          <button type="button" class="button" phx-click="edit" phx-value-id={@task_id}>Reload task</button>
          <p class="fine-print">
            Downloads verify the stored hash. Missing or changed files are refused.
          </p>
        </div>
      </article>
    </details>
    """
  end
end
