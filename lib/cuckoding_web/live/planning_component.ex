defmodule CuckodingWeb.PlanningComponent do
  @moduledoc false
  use Phoenix.LiveComponent
  alias Cuckoding.{Foundation, GitPreview, Planning, PlanningDocuments, Tabulae}

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       brief: "",
       document_paths: "",
       preview_id: nil,
       confirmed: false,
       consent_token: nil,
       key: Ecto.UUID.generate(),
       error: nil,
       message: nil
     )
     |> CuckodingWeb.SessionAuth.guard_events()}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> refresh()}
  end

  defp refresh(socket) do
    setup = Planning.setup(socket.assigns.board, socket.assigns.preview_id)

    assign(socket,
      setup: setup,
      preview: PlanningDocuments.latest(socket.assigns.board.id),
      plans: Planning.history(socket.assigns.board.id),
      imported: Tabulae.imported(socket.assigns.board.id),
      confirmed: socket.assigns.confirmed && socket.assigns.consent_token == setup.token
    )
  end

  @impl true
  def handle_event("change", params, socket), do: {:noreply, input(socket, params)}

  def handle_event("document-paths", %{"paths" => paths}, socket)
      when is_binary(paths) and byte_size(paths) <= 4_000 do
    {:noreply,
     socket
     |> assign(document_paths: paths, preview_id: nil, confirmed: false, consent_token: nil)
     |> refresh()}
  end

  def handle_event("preview-documents", %{"paths" => paths}, socket) do
    a = socket.assigns

    result =
      with {:ok, selected} <- GitPreview.paths(paths),
           do: PlanningDocuments.request(a.key, a.board.arena_id, a.board.id, selected)

    socket =
      case result do
        {:ok, %{state: "pending", id: id}} -> assign(socket, :preview_id, id)
        _ -> socket
      end

    {:noreply,
     socket |> result(result) |> assign(confirmed: false, consent_token: nil) |> refresh()}
  end

  def handle_event("use-documents", _, %{assigns: %{preview: %{id: id}}} = socket) do
    {:noreply,
     socket
     |> assign(preview_id: id, confirmed: false, consent_token: nil)
     |> refresh()}
  end

  def handle_event("brief-only", _, socket) do
    {:noreply,
     socket |> assign(preview_id: nil, confirmed: false, consent_token: nil) |> refresh()}
  end

  def handle_event("generate", params, socket) do
    socket = input(socket, params)
    a = socket.assigns

    result =
      Planning.request(
        a.key,
        a.board.arena_id,
        a.board.id,
        a.brief,
        a.consent_token,
        a.confirmed,
        a.preview_id
      )

    {:noreply,
     socket |> result(result) |> assign(confirmed: false, consent_token: nil) |> refresh()}
  end

  def handle_event("cancel", %{"id" => id}, socket) do
    if Enum.any?([socket.assigns.preview | socket.assigns.plans], &(&1 && &1.id == id)),
      do: Foundation.cancel_probe(id)

    {:noreply, refresh(socket)}
  end

  def handle_event("import", %{"id" => id, "index" => index}, socket)
      when is_binary(index) and byte_size(index) <= 1 do
    a = socket.assigns

    case Integer.parse(index) do
      {index, ""} ->
        result = Tabulae.import_proposal(a.key, a.board.arena_id, a.board.id, id, index)
        {:noreply, socket |> result(result) |> refresh()}

      _ ->
        {:noreply, assign(socket, :error, "This proposal is unavailable.")}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp input(socket, params) do
    brief = params["brief"]

    socket =
      if is_binary(brief) and byte_size(brief) <= 32_000,
        do: assign(socket, :brief, brief),
        else: socket

    assign(socket,
      confirmed:
        is_binary(brief) and byte_size(brief) <= 32_000 and params["confirmed"] == "true" and
          params["setup_token"] == socket.assigns.setup.token and
          not is_nil(socket.assigns.setup.token),
      consent_token: params["setup_token"]
    )
  end

  defp result(socket, {:ok, %{state: "rejected", result: reason}}),
    do: result(socket, {:error, reason})

  defp result(socket, {:ok, %Cuckoding.DraftTaskRevision{}}),
    do:
      assign(socket,
        key: Ecto.UUID.generate(),
        error: nil,
        message: "Added to Specs. Open Edit task to refine it."
      )

  defp result(socket, {:ok, _}),
    do: assign(socket, key: Ecto.UUID.generate(), error: nil, message: nil)

  defp result(socket, {:error, reason}),
    do: assign(socket, key: Ecto.UUID.generate(), error: message(reason), message: nil)

  defp active?(command), do: command.state in ~w(pending running cancelling)

  defp message("planning_confirmation_required"),
    do: "Enter a brief of up to 8,000 bytes and confirm provider usage."

  defp message("planning_setup_changed"),
    do:
      "The team, connection or selected document snapshot changed or expired. Check the selection and confirm again."

  defp message(reason)
       when reason in ~w(invalid_selection invalid_documents selection_limit unsafe_file invalid_text preview_changed folder_changed),
       do:
         "Preview refused. Select up to four safe .md/.txt files, 4,096 bytes each and 12,000 total, then preview again."

  defp message("previewed"), do: "Snapshots saved locally. Review the exact text before sending."

  defp message("profile_busy"),
    do: "Another setup or planning operation is active. Wait or cancel it first."

  defp message("already_imported"),
    do: "This suggestion is already in Specs. Edit the existing task."

  defp message("prerequisites_not_imported"),
    do: "Add this suggestion's prerequisites to Specs first. Existing tasks stay unchanged."

  defp message("planned"), do: "Proposals ready · review before adding to Specs."
  defp message("cancelled"), do: "Planning cancelled. No proposals were imported."

  defp message("interrupted"),
    do: "Planning was interrupted and was not replayed. You can explicitly generate again."

  defp message("cleanup_uncertain"),
    do: "Cleanup could not be confirmed. Inspect Agents before trying again."

  defp message("timeout"),
    do: "Planning reached its two-minute limit. Shorten the brief and try again."

  defp message(_),
    do: "Planning could not produce a valid result. Check Agents, then explicitly try again."

  @impl true
  def render(assigns) do
    ~H"""
    <details
      id="brief-planning"
      class="git-setup"
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
    >
      <summary>Ask Speculator · brief and documents</summary>
      <p class="fine-print">
        {@setup.role["name"]} · {Cuckoding.Agents.display(@setup.role["agent"])} · {if @setup.payload,
          do: @setup.payload["model"],
          else: "model unavailable"} · saved team {@setup.team_id}
      </p>
      <p :if={!@setup.token && is_nil(@preview_id)} class="notice">
        Planning currently requires a Speculator assigned to a connected Codex agent and model. Cursor can be assigned in Team; its planning support is not enabled yet.
        After saving a model on Team, open Tabula team above to adopt that saved revision.
      </p>
      <details id="planning-documents" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
        <summary>Optional documents · preview locally</summary>
        <p class="fine-print">
          Enter up to four Arena-relative .md/.txt paths, one per line. Each file may contain
          4,096 bytes; 12,000 bytes total. Preview saves the exact text in local history.
          Provider consent below sends the snapshot, including any private text you select.
        </p>
        <.form
          for={%{}}
          id="documents-form"
          class="role-fields"
          phx-change="document-paths"
          phx-submit="preview-documents"
          phx-target={@myself}
        >
          <label for="document-paths">Selected document paths</label>
          <textarea
            id="document-paths"
            name="paths"
            rows="3"
            maxlength="1000"
            required
            placeholder="docs/plan.md"
          >{@document_paths}</textarea>
          <button type="submit" class="button" disabled={@busy} phx-disable-with="Reading…">Preview documents</button>
        </.form>
        <article :if={@preview} id="document-preview" class="team-role">
          <h3>Local document preview · {@preview.state}</h3>
          <p class="fine-print">
            Owner: you · local reader · no agent/model · {Calendar.strftime(
              @preview.inserted_at,
              "%Y-%m-%d %H:%M UTC"
            )} · {if active?(@preview),
              do: max(0, DateTime.diff(@now, @preview.inserted_at)),
              else: max(0, DateTime.diff(@preview.updated_at, @preview.inserted_at))}s
          </p>
          <button
            :if={active?(@preview)}
            type="button"
            class="button"
            phx-click="cancel"
            phx-target={@myself}
            phx-value-id={@preview.id}
            disabled={@preview.state == "cancelling"}
          >Cancel preview</button>
          <p :if={!active?(@preview)} role="status">{message(@preview.result)}</p>
          <.documents
            id={"preview-documents-#{@preview.id}"}
            files={get_in(@preview.payload, ["observation", "files"]) || []}
          />
          <button
            :if={@preview.state == "completed" && @preview_id != @preview.id}
            type="button"
            class="button"
            phx-click="use-documents"
            phx-target={@myself}
            disabled={!match?({:ok, _}, PlanningDocuments.selected(@board, @preview.id))}
          >
            Use these snapshots
          </button>
        </article>
      </details>
      <p id="document-selection" class="fine-print">
        {cond do
          is_nil(@preview_id) ->
            "Brief only. No document snapshots selected."

          @setup.token ->
            "Selected document snapshots will be sent with the brief. Preview expires after five minutes."

          true ->
            "Selected snapshot is pending, expired or unavailable. Preview again or use the brief only."
        end}
      </p>
      <button
        :if={@preview_id}
        type="button"
        class="button"
        phx-click="brief-only"
        phx-target={@myself}
      >Use brief only</button>
      <.form
        for={%{}}
        id="planning-form"
        class="role-fields"
        phx-change="change"
        phx-submit="generate"
        phx-target={@myself}
      >
        <input type="hidden" name="setup_token" value={@setup.token || ""} />
        <label for="planning-brief">Describe the work · up to 8,000 bytes</label>
        <textarea id="planning-brief" name="brief" rows="5" maxlength="8000" required>{@brief}</textarea>
        <label class="confirm-executable">
          <input
            type="checkbox"
            name="confirmed"
            value="true"
            checked={@confirmed}
            disabled={!@setup.token || @busy}
          />
          Send this brief, selected document snapshots and the saved Speculator instructions to {Cuckoding.Agents.display(
            @setup.role["agent"]
          )}. This may use my account allowance.
        </label>
        <p class="fine-print">
          One turn, no tools or project-file access. Up to six suggestions; adding a draft does not start a battle.
        </p>
        <p :if={@error} id="planning-error" role="alert" class="notice">{@error}</p>
        <p :if={@message} role="status">{@message}</p>
        <button
          type="submit"
          class="button"
          disabled={!@setup.token || @busy}
          phx-disable-with="Starting…"
        >Generate proposals</button>
      </.form>
      <p :if={@plans != []} class="fine-print">
        Recent planning requests · active first · retained locally
      </p>
      <article :for={plan <- @plans} id={"plan-#{plan.id}"} class="team-role">
        <h3>Speculator · {plan.state}</h3>
        <p class="fine-print">
          {plan.payload["role"] && plan.payload["role"]["name"]} · Codex · {plan.payload["model"]} · {Calendar.strftime(
            plan.inserted_at,
            "%Y-%m-%d %H:%M UTC"
          )} · {if active?(plan),
            do: max(0, DateTime.diff(@now, plan.inserted_at)),
            else: max(0, DateTime.diff(plan.updated_at, plan.inserted_at))}s
        </p>
        <button
          :if={active?(plan)}
          type="button"
          class="button"
          phx-click="cancel"
          phx-target={@myself}
          phx-value-id={plan.id}
          disabled={plan.state == "cancelling"}
        >Cancel planning</button>
        <p :if={!active?(plan)} role="status">{message(plan.result)}</p>
        <details id={"brief-#{plan.id}"} phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
          <summary>Source brief · team {plan.payload["team_revision_id"]}</summary>
          <p class="draft-copy">{plan.payload["brief"]}</p>
          <.documents id={"plan-documents-#{plan.id}"} files={plan.payload["documents"] || []} />
        </details>
        <div :if={proposal = Planning.proposal(plan)}>
          <p class="draft-copy">{proposal["summary"]}</p>
          <article
            :for={{task, index} <- Enum.with_index(proposal["tasks"])}
            id={"proposal-#{plan.id}-#{index}"}
            class="task-card"
          >
            <h4>{index + 1}. {task["title"]}</h4>
            <p class="draft-copy">{task["description"]}</p>
            <p class="draft-copy">Acceptance criteria: {task["criteria"]}</p>
            <p :if={Map.get(task, "depends_on", []) != []} class="fine-print">
              Add prerequisites first: {Enum.map_join(
                task["depends_on"],
                "; ",
                &Enum.at(proposal["tasks"], &1)["title"]
              )}
            </p>
            <div :if={Map.get(task, "sources", []) != []}>
              <p class="fine-print">Cited snapshots · check that these support the suggestion.</p>
              <.documents
                id={"proposal-sources-#{plan.id}-#{index}"}
                files={Planning.sources(plan, index)}
              />
            </div>
            <button
              type="button"
              class="button"
              phx-click="import"
              phx-target={@myself}
              phx-value-id={plan.id}
              phx-value-index={index}
              disabled={Map.has_key?(@imported, {plan.id, index})}
            >
              {if Map.has_key?(@imported, {plan.id, index}),
                do: "Added to Specs",
                else: "Add to Specs"}
            </button>
          </article>
        </div>
      </article>
    </details>
    """
  end

  def documents(assigns) do
    ~H"""
    <details
      :for={{file, index} <- Enum.with_index(@files)}
      id={"#{@id}-#{index}"}
      phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
    >
      <summary>{file["path"]} · {file["bytes"]} bytes</summary>
      <p class="fine-print draft-copy">SHA-256: {file["sha256"]}</p>
      <pre class="draft-copy">{file["text"]}</pre>
    </details>
    """
  end
end
