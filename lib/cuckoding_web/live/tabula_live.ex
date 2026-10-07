defmodule CuckodingWeb.TabulaLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.Tabulae
  alias CuckodingWeb.Layouts

  @impl true
  def mount(params, _, socket) do
    arena = Tabulae.arena(params["arena_id"])
    board = if arena, do: Tabulae.get(arena.id, params["id"])

    if arena && (is_nil(params["id"]) || board) do
      if connected?(socket), do: Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")

      {:ok,
       socket
       |> assign(
         arena: arena,
         board: board,
         board_name: "",
         board_key: Ecto.UUID.generate(),
         board_error: nil,
         error: nil,
         message: nil,
         pending_edit: nil
       )
       |> draft(nil)
       |> refresh()}
    else
      {:ok,
       socket |> put_flash(:error, "Arena or Tabula unavailable.") |> redirect(to: "/arenas")}
    end
  end

  @impl true
  def handle_event("board-change", %{"name" => name}, socket)
      when is_binary(name) and byte_size(name) <= 320,
      do: {:noreply, assign(socket, :board_name, name)}

  def handle_event("create", params, socket) do
    socket =
      if is_binary(params["name"]) and byte_size(params["name"]) <= 320,
        do: assign(socket, :board_name, params["name"]),
        else: socket

    case Tabulae.create(socket.assigns.board_key, socket.assigns.arena.id, params["name"]) do
      {:ok, board} ->
        {:noreply, push_navigate(socket, to: ~p"/arenas/#{board.arena_id}/tabulae/#{board.id}")}

      {:error, reason} ->
        {:noreply, assign(socket, board_error: message(reason), board_key: Ecto.UUID.generate())}
    end
  end

  def handle_event("change", params, socket), do: {:noreply, input(socket, params)}

  def handle_event("save", params, socket) do
    socket = input(socket, params)

    result =
      if socket.assigns.form_matches && socket.assigns.board do
        Tabulae.save(
          socket.assigns.key,
          socket.assigns.arena.id,
          socket.assigns.board.id,
          socket.assigns.task_id,
          socket.assigns.revision,
          socket.assigns.content
        )
      else
        {:error, "stale_form"}
      end

    case result do
      {:ok, revision} ->
        {:noreply,
         socket
         |> assign(error: nil, message: "Task saved · revision #{revision.revision}.")
         |> draft(nil)
         |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, error: message(reason), key: Ecto.UUID.generate())}
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    if id == "new" || Enum.any?(socket.assigns.tasks, &(&1.id == id)) do
      if socket.assigns.dirty do
        {:noreply, assign(socket, :pending_edit, id)}
      else
        {:noreply, select_task(socket, id)}
      end
    else
      {:noreply, assign(socket, :error, message("scope_missing"))}
    end
  end

  def handle_event("discard", _, socket) do
    if socket.assigns.pending_edit,
      do: {:noreply, select_task(socket, socket.assigns.pending_edit)},
      else: {:noreply, socket}
  end

  def handle_event("keep", _, socket), do: {:noreply, assign(socket, :pending_edit, nil)}
  def handle_event(_, _, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:updated, socket), do: {:noreply, refresh(socket)}
  def handle_info(:session_expired, socket), do: {:noreply, redirect(socket, to: "/locked")}

  defp refresh(socket) do
    board = socket.assigns.board

    assign(socket,
      boards: Tabulae.list(socket.assigns.arena.id),
      tasks: if(board, do: Tabulae.tasks(board.id), else: []),
      history:
        if(board && socket.assigns.revision > 0,
          do: Tabulae.history(board.id, socket.assigns.task_id),
          else: []
        )
    )
  end

  defp select_task(socket, id) do
    task = Enum.find(socket.assigns.tasks, &(&1.id == id))
    socket |> draft(task) |> assign(error: nil, message: nil, pending_edit: nil) |> refresh()
  end

  defp draft(socket, task) do
    content =
      if task,
        do: Tabulae.content(task),
        else: %{"title" => "", "description" => "", "criteria" => "", "column" => "specs"}

    assign(socket,
      task_id: if(task, do: task.id, else: Ecto.UUID.generate()),
      revision: if(task, do: task.revision, else: 0),
      content: content,
      original: content,
      dirty: false,
      form_matches: true,
      key: Ecto.UUID.generate()
    )
  end

  defp input(socket, params) do
    content = Map.take(params, ~w(title description criteria column))
    bounded = Enum.all?(content, fn {_, v} -> is_binary(v) and byte_size(v) <= 32_000 end)

    matches =
      socket.assigns.board != nil and params["task_id"] == socket.assigns.task_id and
        params["revision"] == to_string(socket.assigns.revision) and
        params["tabula_id"] == socket.assigns.board.id

    if bounded && map_size(content) == 4 do
      assign(socket,
        content: content,
        dirty: content != socket.assigns.original,
        form_matches: socket.assigns.form_matches && matches,
        message: nil
      )
    else
      assign(socket, form_matches: false, error: message("invalid_task"))
    end
  end

  defp role_name(board, key) do
    case Enum.find(board.team_revision.definition["roles"], &(&1["id"] == key)) do
      nil -> "System result"
      role -> role["name"]
    end
  end

  defp message("invalid_board"), do: "Enter a Tabula name of 1–80 characters."

  defp message("invalid_task"),
    do: "Enter a title (1–120 characters), description (up to 8,000) and criteria (up to 4,000)."

  defp message("criteria_required"),
    do: "ToDo needs a description and acceptance criteria. Your draft is kept."

  defp message("stale_task"),
    do:
      "This task changed elsewhere. Your draft is kept; copy it before loading the current task."

  defp message("stale_form"),
    do:
      "This recovered form belongs to another editor. Your text is kept; copy it before starting a new draft."

  defp message("stage_unavailable"),
    do: "Delivery stages require battle execution, which is not available yet."

  defp message(_), do: "This Arena, Tabula or task is unavailable. Your draft is kept."

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={:arenas} title={@arena.name} flash={@flash}>
      <section class="panel" aria-labelledby="tabula-title">
        <p class="eyebrow">04 / TABULA</p>
        <h2 id="tabula-title">{if @board, do: @board.name, else: "Plan your next battle."}</h2>
        <p>
          Draft work locally. In Process, Review and Completed unlock with future battle execution.
        </p>
        <div class="team-actions" aria-label="Tabulae">
          <.link
            :for={board <- @boards}
            navigate={~p"/arenas/#{@arena.id}/tabulae/#{board.id}"}
            class="button"
            aria-current={if @board && @board.id == board.id, do: "page"}
          >{board.name}</.link>
        </div>
        <details
          id="create-tabula"
          open={is_nil(@board)}
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Create a Tabula</summary>
          <.form
            for={%{}}
            id="tabula-form"
            phx-change="board-change"
            phx-submit="create"
            class="role-fields"
          >
            <label for="tabula-name">Tabula name</label>
            <input
              id="tabula-name"
              name="name"
              type="text"
              value={@board_name}
              maxlength="80"
              required
            />
            <p class="fine-print">
              Inherits Arena team revision {@arena.team_revision_id}. No agent access is granted.
            </p>
            <p :if={@board_error} role="alert" class="notice">{@board_error}</p>
            <button type="submit" class="button" phx-disable-with="Creating…">Create Tabula</button>
          </.form>
        </details>
        <p :if={@error && is_nil(@board)} role="alert" class="notice">{@error}</p>
        <p :if={@message} role="status">{@message}</p>
        <div
          :if={@board}
          id="tabula-board"
          class="tabula-scroll"
          tabindex="0"
          role="region"
          aria-label="Task columns; scroll horizontally for delivery stages"
        >
          <div class="tabula-columns">
            <section
              :for={column <- @board.definition["columns"]}
              id={"column-#{column["key"]}"}
              class="tabula-column"
              aria-labelledby={"heading-#{column["key"]}"}
            >
              <h3 id={"heading-#{column["key"]}"}>{column["name"]}</h3>
              <p class="fine-print">{role_name(@board, column["role"])}</p>
              <p :if={column["key"] not in ~w(specs todo)} class="fine-print">
                Unavailable until battles
              </p>
              <p
                :if={
                  column["key"] in ~w(specs todo) &&
                    not Enum.any?(@tasks, &(&1.column == column["key"]))
                }
                class="fine-print"
              >
                No tasks yet
              </p>
              <article
                :for={task <- Enum.filter(@tasks, &(&1.column == column["key"]))}
                id={"task-#{task.id}"}
                class="task-card"
              >
                <h4>{task.title}</h4>
                <p class="fine-print">Draft · revision {task.revision} · no active agent</p>
                <button
                  type="button"
                  class="button"
                  phx-click="edit"
                  phx-value-id={task.id}
                  aria-label={"Edit #{task.title}"}
                >Edit task</button>
              </article>
            </section>
          </div>
        </div>
        <p :if={@board} class="fine-print">
          Team revision {@board.team_revision_id} · workflow 1 · manual planning only. ToDo does not authorize execution.
        </p>
      </section>
      <section :if={@board} class="panel" aria-labelledby="draft-title">
        <h2 id="draft-title">
          {if @revision == 0, do: "New task", else: "Edit task · revision #{@revision}"}
        </h2>
        <button type="button" class="button" phx-click="edit" phx-value-id="new">New draft</button>
        <div :if={@pending_edit} role="alert" class="notice">
          <p>Discard your unsaved edits and open the selected draft?</p>
          <button type="button" class="button" phx-click="keep">Keep editing</button>
          <button type="button" class="button" phx-click="discard">Discard unsaved edits</button>
        </div>
        <.form
          for={%{}}
          id="draft-form"
          phx-change="change"
          phx-submit="save"
          class="role-fields"
          aria-describedby={if @error, do: "draft-error"}
        >
          <input name="task_id" type="hidden" value={@task_id} />
          <input name="revision" type="hidden" value={@revision} />
          <input name="tabula_id" type="hidden" value={@board.id} />
          <label for="draft-title-input">Task title</label>
          <input
            id="draft-title-input"
            type="text"
            name="title"
            value={@content["title"]}
            maxlength="120"
            required
          />
          <label for="draft-description">Description</label>
          <textarea id="draft-description" name="description" rows="5" maxlength="8000">{@content["description"]}</textarea>
          <label for="draft-criteria">Acceptance criteria</label>
          <textarea id="draft-criteria" name="criteria" rows="4" maxlength="4000">{@content["criteria"]}</textarea>
          <label for="draft-column">Column</label>
          <select id="draft-column" name="column">
            <option value="specs" selected={@content["column"] == "specs"}>
              Specs · refine the task
            </option>
            <option value="todo" selected={@content["column"] == "todo"}>ToDo · planned work</option>
          </select>
          <p class="fine-print">
            ToDo needs a description and criteria. These are database drafts; project files stay untouched.
          </p>
          <p :if={@error} id="draft-error" role="alert" class="notice">{@error}</p>
          <button type="submit" class="button primary" phx-disable-with="Saving…">Save task</button>
        </.form>
        <details
          :if={@history != []}
          id="draft-history"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Saved history · latest five revisions</summary>
          <article :for={revision <- @history} class="team-role">
            <h3>Revision {revision.revision} · {revision.content["column"]}</h3>
            <p class="fine-print">{Calendar.strftime(revision.inserted_at, "%Y-%m-%d %H:%M UTC")}</p>
            <h4>{revision.content["title"]}</h4>
            <p class="draft-copy">{revision.content["description"]}</p>
            <p class="draft-copy">{revision.content["criteria"]}</p>
          </article>
        </details>
      </section>
    </Layouts.workspace>
    """
  end
end
