defmodule CuckodingWeb.WorkflowComponent do
  @moduledoc false
  use CuckodingWeb, :live_component
  import CuckodingWeb.Dialog
  alias Cuckoding.Workflows

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(
       key: Ecto.UUID.generate(),
       scope: nil,
       names: nil,
       error: nil,
       notice: nil,
       dirty: false,
       stale: false,
       valid_input: true,
       discard_pending: false
     )
     |> CuckodingWeb.SessionAuth.guard_events()}
  end

  @impl true
  def update(assigns, socket) do
    scope = {assigns.board.arena_id, assigns.board.id}

    cond do
      is_nil(socket.assigns.scope) ->
        {:ok, socket |> assign(assigns) |> assign(:scope, scope) |> load_saved()}

      socket.assigns.scope == scope ->
        revision = Workflows.current(assigns.board)
        changed = revision.revision != socket.assigns.latest_revision

        {:ok,
         socket
         |> assign(assigns)
         |> assign(
           latest_revision: revision.revision,
           stale: socket.assigns.stale or revision.revision != socket.assigns.base_revision,
           key: if(changed, do: Ecto.UUID.generate(), else: socket.assigns.key),
           history:
             if(changed, do: Workflows.history(assigns.board.id), else: socket.assigns.history),
           blocker: Workflows.blocker(assigns.board)
         )}

      true ->
        {:ok, invalidate(socket)}
    end
  end

  defp load_saved(socket) do
    revision = Workflows.current(socket.assigns.board)
    names = Workflows.labels(revision.definition)

    assign(socket,
      names: names,
      base_names: names,
      base_revision: revision.revision,
      latest_revision: revision.revision,
      history: Workflows.history(socket.assigns.board.id),
      blocker: Workflows.blocker(socket.assigns.board),
      key: Ecto.UUID.generate(),
      stale: false,
      dirty: false,
      valid_input: true,
      discard_pending: false,
      error: nil
    )
  end

  @impl true
  def handle_event("change", params, socket) do
    {:noreply,
     if(current_form?(params, socket.assigns),
       do: input(socket, params),
       else: invalidate(socket)
     )}
  end

  def handle_event("recover", params, socket) do
    socket = if same_scope?(params, socket.assigns), do: input(socket, params), else: socket
    {:noreply, invalidate(socket)}
  end

  def handle_event("save", params, socket) do
    if current_form?(params, socket.assigns) and not socket.assigns.stale do
      socket = input(socket, params)
      a = socket.assigns
      {arena, board} = a.scope

      result =
        if a.valid_input,
          do: Workflows.save_labels(a.key, arena, board, a.base_revision, a.names),
          else: {:error, "invalid_workflow"}

      socket =
        case result do
          {:ok, _} ->
            socket |> load_saved() |> assign(:notice, "Column names saved. No work was started.")

          {:error, reason} ->
            assign(socket,
              error: message(reason),
              key: Ecto.UUID.generate(),
              stale: reason in ["stale_workflow", :key_conflict]
            )
        end

      {:noreply, socket}
    else
      {:noreply, invalidate(socket)}
    end
  end

  def handle_event("reload", %{"key" => key}, socket) when key == socket.assigns.key do
    {:noreply,
     if(socket.assigns.dirty,
       do: assign(socket, :discard_pending, true),
       else: load_saved(socket)
     )}
  end

  def handle_event("discard", %{"key" => key}, socket)
      when key == socket.assigns.key and socket.assigns.discard_pending do
    {:noreply, socket |> load_saved() |> assign(:notice, nil)}
  end

  def handle_event("keep", _, socket), do: {:noreply, assign(socket, :discard_pending, false)}
  def handle_event(_, _, socket), do: {:noreply, socket}

  defp input(socket, %{"labels" => names}) when is_map(names) do
    unused = Enum.map(Map.keys(socket.assigns.base_names), &("_unused_" <> &1))
    names = Map.reject(names, fn {key, value} -> key in unused and value == "" end)

    if Enum.sort(Map.keys(names)) == Enum.sort(Map.keys(socket.assigns.base_names)) and
         Enum.all?(Map.values(names), &(is_binary(&1) and byte_size(&1) <= 160)) do
      assign(socket,
        names: names,
        dirty: names != socket.assigns.base_names,
        valid_input: true,
        error: nil,
        notice: nil,
        discard_pending: false
      )
    else
      assign(socket, valid_input: false, error: message("invalid_workflow"))
    end
  end

  defp input(socket, _),
    do: assign(socket, valid_input: false, error: message("invalid_workflow"))

  defp current_form?(params, a),
    do:
      same_scope?(params, a) and params["key"] == a.key and
        params["base_revision"] == to_string(a.base_revision)

  defp same_scope?(params, a),
    do: {params["arena_id"], params["tabula_id"]} == a.scope

  defp invalidate(socket),
    do:
      assign(socket,
        stale: true,
        key: Ecto.UUID.generate(),
        discard_pending: false,
        error:
          "This form changed or reconnected. Your draft is kept; reload saved names before saving."
      )

  defp message("planning_active"),
    do: "Finish or cancel this board's task planning before changing its columns."

  defp message("battle_active"),
    do: "Finish or Stop this board's battle before changing its columns."

  defp message("workflow_unchanged"), do: "These names are already saved."

  defp message("invalid_workflow"),
    do: "Use five different names, each 1–40 characters on one line."

  defp message(_), do: "The saved workflow changed. Your draft is kept; reload saved names."

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :columns, Workflows.default_definition()["columns"])

    ~H"""
    <div id={@id}>
      <.modal id="board-workflow" title="Board columns">
        <p class="fine-print">
          Rename this board's columns. Their roles, order and review rules stay the same.
          This starts no agent and does not change past battles.
        </p>
        <p :if={@stale} role="status" class="notice">
          Saved names changed or the form reconnected. Your draft is kept.
        </p>
        <p :if={@blocker} id="workflow-busy" role="status">{message(@blocker)}</p>
        <p :if={@error} id="workflow-error" role="alert" class="notice">{@error}</p>
        <p :if={@notice} id="workflow-notice" role="status">{@notice}</p>
        <.form
          for={%{}}
          id="workflow-form"
          class="role-fields"
          phx-target={@myself}
          phx-change="change"
          phx-submit="save"
          phx-auto-recover="recover"
        >
          <input type="hidden" name="key" value={@key} />
          <input type="hidden" name="base_revision" value={@base_revision} />
          <input type="hidden" name="arena_id" value={elem(@scope, 0)} />
          <input type="hidden" name="tabula_id" value={elem(@scope, 1)} />
          <div :for={column <- @columns} class="field">
            <label for={"workflow-#{column["key"]}"}>{column["name"]} label</label>
            <input
              id={"workflow-#{column["key"]}"}
              type="text"
              name={"labels[#{column["key"]}]"}
              value={@names[column["key"]]}
              required
              maxlength="40"
            />
          </div>
          <button
            class="button primary"
            disabled={@stale or not @dirty or not is_nil(@blocker)}
            phx-disable-with="Saving…"
          >Save column names</button>
        </.form>
        <button
          type="button"
          class="button"
          phx-target={@myself}
          phx-click="reload"
          phx-value-key={@key}
        >Reload saved names</button>
        <div
          :if={@discard_pending}
          id="workflow-discard"
          role="group"
          aria-label="Discard unsaved names"
        >
          <p>Your unsaved names will be replaced with the saved version.</p>
          <button type="button" class="button" phx-target={@myself} phx-click="keep">Keep editing</button>
          <button
            type="button"
            class="button"
            phx-target={@myself}
            phx-click="discard"
            phx-value-key={@key}
          >Discard draft and reload</button>
        </div>
        <details
          :if={@history != []}
          id="workflow-history"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Column history</summary>
          <article :for={revision <- @history} id={"workflow-revision-#{revision.revision}"}>
            <p class="fine-print">
              {Calendar.strftime(revision.inserted_at, "%Y-%m-%d %H:%M UTC")} · version {revision.revision}
            </p>
            <p>{Enum.map_join(revision.definition["columns"], " → ", & &1["name"])}</p>
          </article>
        </details>
      </.modal>
    </div>
    """
  end
end
