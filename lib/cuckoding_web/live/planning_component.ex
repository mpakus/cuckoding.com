defmodule CuckodingWeb.PlanningComponent do
  @moduledoc false
  use CuckodingWeb, :live_component
  import CuckodingWeb.VerificationComponents
  import CuckodingWeb.Dialog
  alias Cuckoding.{Foundation, GitPreview, Planning, PlanningDocuments, Tabulae, Workflows}
  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       brief: "",
       document_paths: "",
       preview_id: nil,
       role_id: "speculator",
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
    setup =
      Planning.setup(socket.assigns.board, socket.assigns.preview_id, socket.assigns.role_id)

    assign(socket,
      setup: setup,
      documents_ready:
        match?(
          {:ok, _},
          PlanningDocuments.selected(socket.assigns.board, socket.assigns.preview_id)
        ),
      preview: PlanningDocuments.latest(socket.assigns.board.id),
      plans: Planning.history(socket.assigns.board.id),
      imported: Tabulae.imported(socket.assigns.board.id),
      confirmed: socket.assigns.confirmed && socket.assigns.consent_token == setup.token
    )
  end

  @impl true
  def handle_event("change", params, socket), do: {:noreply, input(socket, params)}

  def handle_event("planning-role", %{"role_id" => id}, socket)
      when is_binary(id) and byte_size(id) in 1..36 do
    if Enum.any?(socket.assigns.setup.roles, &(&1["id"] == id)) do
      {:noreply,
       socket
       |> assign(
         role_id: id,
         confirmed: false,
         consent_token: nil,
         key: Ecto.UUID.generate(),
         error: nil
       )
       |> refresh()}
    else
      {:noreply,
       assign(socket,
         confirmed: false,
         consent_token: nil,
         key: Ecto.UUID.generate(),
         error: "Choose a saved role from this board's team."
       )}
    end
  end

  def handle_event("scan-folder", _, socket) do
    a = socket.assigns
    outcome = PlanningDocuments.scan(a.key, a.board.arena_id, a.board.id)

    socket =
      case outcome do
        {:ok, %{state: "pending", id: id}} -> assign(socket, :preview_id, id)
        _ -> socket
      end

    {:noreply,
     socket |> result(outcome) |> assign(confirmed: false, consent_token: nil) |> refresh()}
  end

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
        a.preview_id,
        a.role_id
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
          params["role_id"] == socket.assigns.role_id and
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
        message:
          "Added to #{Workflows.column_name(socket.assigns.board, "specs")}. Open Edit task to refine it."
      )

  defp result(socket, {:ok, _}),
    do: assign(socket, key: Ecto.UUID.generate(), error: nil, message: nil)

  defp result(socket, {:error, reason}),
    do:
      assign(socket,
        key: Ecto.UUID.generate(),
        error: message(reason, socket.assigns.board),
        message: nil
      )

  defp active?(command), do: command.state in ~w(pending running cancelling)

  defp runtime_name("cursor"), do: "Cursor"
  defp runtime_name(kind) when kind in [nil, "codex"], do: "Codex"
  defp runtime_name(_), do: "Unknown runtime"

  defp message("already_imported", board),
    do:
      "This suggestion is already in #{Workflows.column_name(board, "specs")}. Edit the existing task."

  defp message("prerequisites_not_imported", board),
    do:
      "Add this suggestion's prerequisites to #{Workflows.column_name(board, "specs")} first. Existing tasks stay unchanged."

  defp message("planned", board),
    do: "Proposals ready · review before adding to #{Workflows.column_name(board, "specs")}."

  defp message(reason, _board), do: message(reason)

  defp message("planning_confirmation_required"),
    do:
      "Add a brief or read project sources, then confirm provider usage. Briefs allow up to 8,000 bytes."

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
    <div id="planning-controls">
      <div class="team-actions">
        <button
          type="button"
          class={["button", @empty && "primary"]}
          id="open-planning"
          phx-click={JS.dispatch("cc:open", to: "#brief-planning")}
        >Create tasks</button>
        <span :if={Enum.any?(@plans, &active?/1) || (@preview && active?(@preview))} role="status">Task preparation is active · open Create tasks for progress or Cancel.</span>
      </div>
      <.modal id="brief-planning" title="Create tasks">
        <p>
          Read the project sources or describe the work. Your planning role creates editable tasks with acceptance criteria and verification instructions from your specs. Speculator is the default. Then press Start.
        </p>
        <p class="fine-print">
          Read docs/ first, then eligible text and source files. Up to 16 files, 16 KiB each and 64 KiB total; hidden, generated and known credential paths are excluded. No Git or agent runs during this local read. Review sources before sending private text.
        </p>
        <button
          type="button"
          class="button"
          phx-click="scan-folder"
          phx-target={@myself}
          disabled={@busy}
        >
          Read project folder
        </button>
        <details id="planning-role" phx-mounted={JS.ignore_attributes("open")}>
          <summary>Planning role · {@setup.role["name"]}</summary>
          <.form
            for={%{}}
            id="planning-role-form"
            class="role-fields"
            phx-change="planning-role"
            phx-target={@myself}
          >
            <label for="planning-role-select">Use a saved role from this board's team</label>
            <select id="planning-role-select" name="role_id" disabled={@busy}>
              <option
                :if={!Enum.any?(@setup.roles, &(&1["id"] == @role_id))}
                value={@role_id}
                selected
                disabled
              >
                Selected role unavailable
              </option>
              <option :for={role <- @setup.roles} value={role["id"]} selected={role["id"] == @role_id}>
                {role["name"]}
              </option>
            </select>
            <p class="fine-print">
              This changes only the next task-planning request. Team assignments and battle stages stay as saved.
            </p>
          </.form>
        </details>
        <p class="fine-print">
          {@setup.role["name"]} · {Cuckoding.Agents.display(@setup.role["agent"])} · {if @setup.payload,
            do: @setup.payload["model"],
            else: "model unavailable"}
        </p>
        <p :if={!@setup.token && is_nil(@preview_id)} class="notice">
          Choose a connected Codex or Cursor agent and model for the selected planning role in Team.
          After saving roles in Team, open Board team and choose Use saved team.
        </p>
        <details id="planning-documents" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
          <summary>Choose specific documents instead</summary>
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
        </details>
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
          <div :if={scan = get_in(@preview.payload, ["observation", "scan"])} id="folder-scan-summary">
            <p class="fine-print">
              {length(get_in(@preview.payload, ["observation", "files"]) || [])} source snapshots · {scan[
                "visited"
              ]} entries inspected · policy {@preview.payload["policy"]}
            </p>
            <p :if={scan["limited"]} class="notice">
              Some sources exceeded the read limits. This is a partial view of the project; narrow the scope with specific documents if needed.
            </p>
            <p :for={{reason, count} <- Enum.sort(scan["skipped"])} class="fine-print">
              Skipped: {String.replace(reason, "_", " ")} · {count}
            </p>
            <p :if={get_in(@preview.payload, ["observation", "files"]) == []} class="notice">
              No eligible source text was found. Describe the work below to plan from a brief.
            </p>
          </div>
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
        <p id="document-selection" class="fine-print">
          {cond do
            is_nil(@preview_id) ->
              "Brief only. No document snapshots selected."

            @setup.token ->
              "Selected document snapshots will be sent with the brief. Preview expires after five minutes."

            @documents_ready ->
              "Snapshots are ready locally. Check the selected planning role's connection before sending."

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
          <input type="hidden" name="role_id" value={@role_id} />
          <label for="planning-brief">Describe the work · optional with source snapshots · up to 8,000 bytes</label>
          <textarea id="planning-brief" name="brief" rows="5" maxlength="8000">{@brief}</textarea>
          <label class="confirm-executable">
            <input
              type="checkbox"
              name="confirmed"
              value="true"
              checked={@confirmed}
              disabled={!@setup.token || @busy}
            />
            Send this brief, selected document snapshots and the saved {@setup.role["name"]} instructions to {Cuckoding.Agents.display(
              @setup.role["agent"]
            )}. This may use my account allowance.
          </label>
          <p class="fine-print">
            One turn creates up to six validated cards in {Workflows.column_name(@board, "specs")}, with their prerequisites and sources. Existing tasks stay unchanged. No tools, live project-file access or battle execution.
          </p>
          <p :if={@error} id="planning-error" role="alert" class="notice">{@error}</p>
          <p :if={@message} role="status">{@message}</p>
          <button
            type="submit"
            class="button primary"
            disabled={!@setup.token || @busy}
            phx-disable-with="Starting…"
          >Create tasks</button>
        </.form>
        <p :if={@plans != []} class="fine-print">
          Recent planning requests · active first · retained locally
        </p>
        <article :for={plan <- @plans} id={"plan-#{plan.id}"} class="team-role">
          <h3>{get_in(plan.payload, ["role", "name"]) || "Planning role"} · {plan.state}</h3>
          <p class="fine-print">
            {plan.payload["role"] && plan.payload["role"]["name"]} · {runtime_name(
              plan.payload["kind"]
            )} · {plan.payload["model"]} · {Calendar.strftime(
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
          <p :if={!active?(plan)} role="status">
            {if plan.result == "planned" && plan.payload["card_creation"] == "automatic-v1",
              do: "Tasks created · edit them on the board, then Start when ready.",
              else: message(plan.result, @board)}
          </p>
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
              <p class="draft-copy">Acceptance criteria and checks: {task["criteria"]}</p>
              <.verification entries={Map.get(task, "verification", [])} />
              <p :if={Map.get(task, "depends_on", []) != []} class="fine-print">
                Prerequisites: {Enum.map_join(
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
                :if={plan.payload["card_creation"] != "automatic-v1"}
                type="button"
                class="button"
                phx-click="import"
                phx-target={@myself}
                phx-value-id={plan.id}
                phx-value-index={index}
                disabled={Map.has_key?(@imported, {plan.id, index})}
              >
                {if Map.has_key?(@imported, {plan.id, index}),
                  do: "Added to #{Workflows.column_name(@board, "specs")}",
                  else: "Add to #{Workflows.column_name(@board, "specs")}"}
              </button>
              <p :if={plan.payload["card_creation"] == "automatic-v1"} class="fine-print">
                Created on the board
              </p>
            </article>
          </div>
        </article>
      </.modal>
    </div>
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
