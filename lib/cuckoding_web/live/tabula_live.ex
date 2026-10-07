defmodule CuckodingWeb.TabulaLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.{ArenaGit, Foundation, GitPreview, Tabulae, TeamAssignments}
  alias CuckodingWeb.Layouts

  @impl true
  def mount(params, _, socket) do
    arena = Tabulae.arena(params["arena_id"])
    board = if arena, do: Tabulae.get(arena.id, params["id"])

    if arena && (is_nil(params["id"]) || board) do
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Cuckoding.PubSub, "foundation")
        Process.send_after(self(), :tick, 1_000)
      end

      {:ok,
       socket
       |> assign(
         arena: arena,
         board: board,
         board_name: "",
         board_key: Ecto.UUID.generate(),
         board_error: nil,
         git_key: Ecto.UUID.generate(),
         git_error: nil,
         init_confirmed: false,
         confirmed_observation: nil,
         git_paths: nil,
         commit_confirmed: false,
         confirmed_preview: nil,
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
  def handle_event("inspect-git", _, socket) do
    {:noreply, git_request(socket, "inspect")}
  end

  def handle_event("git-change", params, socket), do: {:noreply, git_input(socket, params)}

  def handle_event("init-git", params, socket) do
    {:noreply, socket |> git_input(params) |> git_request("init")}
  end

  def handle_event("cancel-git", _, socket) do
    if socket.assigns.git, do: Foundation.cancel_probe(socket.assigns.git.id)
    {:noreply, refresh(socket)}
  end

  def handle_event("commit-paths-change", %{"paths" => paths}, socket)
      when is_binary(paths) and byte_size(paths) <= 4_000,
      do:
        {:noreply,
         assign(socket, git_paths: paths, commit_confirmed: false, confirmed_preview: nil)}

  def handle_event("preview-git", %{"paths" => paths}, socket) do
    case GitPreview.paths(paths) do
      {:ok, selected} ->
        result = ArenaGit.preview(socket.assigns.git_key, socket.assigns.arena.id, selected)
        {:noreply, socket |> assign(:git_paths, paths) |> git_result(result)}

      _ ->
        {:noreply, assign(socket, :git_error, git_message("invalid_selection"))}
    end
  end

  def handle_event("commit-change", params, socket), do: {:noreply, commit_input(socket, params)}

  def handle_event("commit-git", params, socket) do
    socket = commit_input(socket, params)

    result =
      ArenaGit.request(
        socket.assigns.git_key,
        socket.assigns.arena.id,
        "commit",
        socket.assigns.confirmed_preview,
        socket.assigns.commit_confirmed
      )

    {:noreply, git_result(socket, result)}
  end

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

  def handle_info(:tick, socket) do
    Process.send_after(self(), :tick, 1_000)
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  defp refresh(socket) do
    board = socket.assigns.board
    git = ArenaGit.latest(socket.assigns.arena.id)
    paths = if git, do: git.payload["paths"] || [], else: []

    assign(socket,
      arena_team: TeamAssignments.assigned(socket.assigns.arena),
      board_team: if(board, do: TeamAssignments.assigned(board)),
      git: git,
      git_paths: socket.assigns.git_paths || Enum.join(paths, "\n"),
      setup_busy: Foundation.pending?(),
      now: DateTime.utc_now(),
      boards: Tabulae.list(socket.assigns.arena.id),
      tasks: if(board, do: Tabulae.tasks(board.id), else: []),
      history:
        if(board && socket.assigns.revision > 0,
          do: Tabulae.history(board.id, socket.assigns.task_id),
          else: []
        )
    )
  end

  defp commit_input(socket, params) do
    current = socket.assigns.git

    confirmed =
      ArenaGit.can_commit?(current) and params["observation_id"] == current.id and
        params["commit_confirmed"] == "true" and
        GitPreview.paths(socket.assigns.git_paths) == {:ok, current.payload["paths"]}

    assign(socket, commit_confirmed: confirmed, confirmed_preview: if(confirmed, do: current.id))
  end

  defp git_input(socket, params) do
    current = socket.assigns.git

    confirmed =
      current != nil and params["observation_id"] == current.id and
        ArenaGit.can_initialize?(current) and params["confirmed"] == "true"

    assign(socket,
      init_confirmed: confirmed,
      confirmed_observation: if(confirmed, do: current.id)
    )
  end

  defp git_request(socket, operation) do
    result =
      ArenaGit.request(
        socket.assigns.git_key,
        socket.assigns.arena.id,
        operation,
        if(operation == "init", do: socket.assigns.confirmed_observation),
        socket.assigns.init_confirmed
      )

    git_result(socket, result)
  end

  defp git_result(socket, result) do
    error =
      case result do
        {:ok, %{state: "rejected", result: reason}} -> git_message(reason)
        {:ok, _} -> nil
        {:error, reason} -> git_message(reason)
      end

    socket
    |> assign(
      git_error: error,
      git_key: Ecto.UUID.generate(),
      init_confirmed: false,
      confirmed_observation: nil,
      commit_confirmed: false,
      confirmed_preview: nil
    )
    |> refresh()
  end

  defp git_active?(command), do: command && command.state in ~w(pending running cancelling)

  defp git_message("missing"),
    do: "No Git repository. Initialization is optional and needs your confirmation."

  defp git_message(status) when status in ~w(unborn initialized),
    do: "Git repository has no commits yet. Preview selected files or an empty baseline below."

  defp git_message("previewed"),
    do: "Review the exact file snapshot before creating the first local commit."

  defp git_message("committed"),
    do: "Initial local commit created. Working files were preserved; nothing was pushed."

  defp git_message("invalid_selection"),
    do:
      "Use up to 16 distinct relative file paths, one per line (240 bytes each). Traversal and known credential paths are refused."

  defp git_message("selection_limit"),
    do: "Selection exceeds the limit: 1 MiB per file and 8 MiB total."

  defp git_message("unsafe_file"),
    do:
      "A selected file is missing or unsafe. Only regular files without symlink parents or hardlinks are supported."

  defp git_message("preview_changed"),
    do: "The files or repository changed. Preview again before committing."

  defp git_message("index_present"),
    do:
      "An index already exists. Keep any staged work and handle the initial commit in Git, then inspect again."

  defp git_message("initial_only"),
    do: "This action requires a repository with no HEAD commit. Inspect Git again."

  defp git_message("commit_incomplete"),
    do:
      "Commit setup was interrupted or refused. Objects or staged files may remain. Inspect Git before any manual recovery; nothing will replay."

  defp git_message("existing"),
    do: "Local HEAD commit verified. Working files and index were not inspected or changed."

  defp git_message("confirmation_required"),
    do: "Confirm the displayed Git action and its current preview."

  defp git_message("folder_changed"),
    do: "The registered folder changed or is unavailable. No new Git action is allowed."

  defp git_message("setup_busy"),
    do: "Another setup operation is active. Finish or cancel it first."

  defp git_message("git_unavailable"),
    do: "System Git is unavailable. Check your Apple command-line tools, then inspect again."

  defp git_message("nested_repository"),
    do: "This folder is inside another repository. Select its repository root instead."

  defp git_message(status) when status in ~w(unsupported_layout unsafe_config),
    do:
      "This Git layout or configuration is not supported safely yet. Linked metadata and external configuration are not followed."

  defp git_message("metadata_limit"),
    do: "Git metadata exceeds the inspection limit. Manual planning remains available."

  defp git_message("invalid_repository"),
    do:
      "Git metadata could not be validated. Existing files were preserved; inspect the repository before retrying."

  defp git_message(_),
    do:
      "Git setup needs a fresh inspection. An interrupted initialization may have created metadata; it will not be replayed."

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

  defp role_name(team, key) do
    case Enum.find(team.definition["roles"], &(&1["id"] == key)) do
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
        <.link :if={@board} navigate={~p"/arenas/#{@arena.id}"}>Arena settings</.link>
        <.live_component
          module={CuckodingWeb.TeamAdoptionComponent}
          id="scope-team"
          session_id={@session_id}
          scope={@board || @arena}
          revision={if @board, do: @board_team.id, else: @arena_team.id}
          now={@now}
        />
        <.live_component
          :if={@board}
          module={CuckodingWeb.PlanningComponent}
          id="planning"
          session_id={@session_id}
          board={@board}
          now={@now}
          busy={@setup_busy}
        />
        <details
          id="arena-git"
          class="git-setup"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Repository setup · {if @git, do: @git.state, else: "not inspected"}</summary>
          <p class="arena-path">{@arena.path}</p>
          <p class="fine-print">
            Inspect local Git metadata. This grants no agent access and does not stage, commit or contact a remote.
          </p>
          <p :if={@git_error} role="alert" class="notice">{@git_error}</p>
          <p :if={@git && !git_active?(@git)} role="status">{git_message(@git.result)}</p>
          <p :if={@git && @git.payload["observation"]} class="fine-print">
            Observed {Calendar.strftime(@git.updated_at, "%Y-%m-%d %H:%M:%S UTC")}
            <code :if={@git.payload["observation"]["head"]}>HEAD {@git.payload["observation"]["head"]}</code>
          </p>
          <div :if={git_active?(@git)} role="status" class="notice">
            <p>Git setup · {@git.state} · {max(0, DateTime.diff(@now, @git.inserted_at))}s</p>
            <p class="fine-print">
              Owner: you · system Git · no agent or model · 15-second operation limit
            </p>
            <button
              type="button"
              class="button"
              phx-click="cancel-git"
              disabled={@git.state == "cancelling"}
            >Cancel Git operation</button>
          </div>
          <div class="team-actions">
            <button type="button" class="button" phx-click="inspect-git" disabled={@setup_busy}>Inspect Git</button>
          </div>
          <.form
            :if={ArenaGit.can_initialize?(@git, @now)}
            for={%{}}
            id="git-init-form"
            phx-change="git-change"
            phx-submit="init-git"
          >
            <input type="hidden" name="observation_id" value={@git.id} />
            <label class="confirm-executable">
              <input
                type="checkbox"
                name="confirmed"
                value="true"
                checked={@init_confirmed && @confirmed_observation == @git.id}
              />
              Create .git in this folder with an empty main branch. Keep all existing files; do not make a commit.
            </label>
            <button type="submit" class="button" disabled={@setup_busy} phx-disable-with="Starting…">Initialize Git</button>
          </.form>
          <.form
            :if={@git && @git.state == "completed" && @git.result in ~w(unborn initialized previewed)}
            for={%{}}
            id="git-preview-form"
            class="role-fields"
            phx-change="commit-paths-change"
            phx-submit="preview-git"
          >
            <label for="git-paths">Files for the initial commit · one relative path per line</label>
            <textarea
              id="git-paths"
              name="paths"
              rows="3"
              maxlength="4000"
              aria-describedby="git-paths-help"
            >{@git_paths}</textarea>
            <p id="git-paths-help" class="fine-print">
              For example: docs/plan.md. Leave empty for an empty baseline. Up to 16 files,
              1 MiB each / 8 MiB total. No folders, links or known credential paths.
              Preview reads only these files; no file contents are saved in Cuckoding.
            </p>
            <button class="button" disabled={@setup_busy} phx-disable-with="Reading…">Preview initial commit</button>
          </.form>
          <div :if={@git && @git.result == "previewed"} id="git-preview">
            <p>
              <strong>Initial commit · {length(@git.payload["observation"]["preview"]["files"])} {if length(
                                                                                                       @git.payload[
                                                                                                         "observation"
                                                                                                       ][
                                                                                                         "preview"
                                                                                                       ][
                                                                                                         "files"
                                                                                                       ]
                                                                                                     ) ==
                                                                                                       1,
                                                                                                     do:
                                                                                                       "file",
                                                                                                     else:
                                                                                                       "files"}</strong>
            </p>
            <p class="fine-print">
              Branch: {@git.payload["observation"]["preview"]["branch"]}<br />
              Author / committer: Cuckoding &lt;local@cuckoding.invalid&gt;<br />
              Message: Initialize Arena with Cuckoding
            </p>
            <p :if={@git.payload["observation"]["preview"]["files"] == []}>
              Empty baseline · no working files will be included.
            </p>
            <ul class="git-files">
              <li :for={
                {file, index} <- Enum.with_index(@git.payload["observation"]["preview"]["files"])
              }>
                <code>{file["path"]}</code>
                · {file["bytes"]} bytes · {if file["mode"] == "100755",
                  do: "executable",
                  else: "regular"}
                <details
                  id={"git-hash-#{@git.id}-#{index}"}
                  phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
                >
                  <summary>SHA-256</summary><code>{file["sha256"]}</code>
                </details>
              </li>
            </ul>
            <p class="fine-print">
              Commit exact bytes without Git filters, hooks or signing. Explicit file selection
              also includes ignored files. Files on disk stay unchanged. Nothing is pushed.
              Interrupted work can leave objects or staged files for inspection.
            </p>
            <.form
              :if={ArenaGit.can_commit?(@git, @now)}
              for={%{}}
              id="git-commit-form"
              phx-change="commit-change"
              phx-submit="commit-git"
            >
              <input type="hidden" name="observation_id" value={@git.id} />
              <label class="confirm-executable">
                <input
                  type="checkbox"
                  name="commit_confirmed"
                  value="true"
                  checked={@commit_confirmed && @confirmed_preview == @git.id}
                />
                I reviewed this snapshot and authorize the first local commit, including only these files.
              </label>
              <button class="button" disabled={@setup_busy} phx-disable-with="Committing…">Create initial commit</button>
            </.form>
            <p :if={!ArenaGit.can_commit?(@git, @now)} role="status">
              Preview expired. Preview again before confirming.
            </p>
          </div>
        </details>
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
              Inherits Arena team revision {@arena_team.id}. No agent access is granted.
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
              <p class="fine-print">{role_name(@board_team, column["role"])}</p>
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
          Team revision {@board_team.id} · workflow 1 · planning drafts. ToDo does not authorize execution.
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
