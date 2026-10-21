defmodule CuckodingWeb.TabulaLive do
  use CuckodingWeb, :live_view
  alias Cuckoding.{ArenaGit, Battles, Dashboard, Foundation, GitPreview, Tabulae, TeamAssignments}
  alias CuckodingWeb.Layouts
  import CuckodingWeb.Dialog
  alias Phoenix.LiveView.JS

  @impl true
  def mount(params, _, socket) do
    arena = Tabulae.arena(params["arena_id"])

    board =
      if arena do
        if params["id"],
          do: Tabulae.get(arena.id, params["id"]),
          else: List.first(Tabulae.list(arena.id))
      end

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
         worktree_confirmed: false,
         worktree_observation: nil,
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

  def handle_event("worktree-change", params, socket),
    do: {:noreply, worktree_input(socket, params)}

  def handle_event("prepare-worktree", _, %{assigns: %{setup_busy: true}} = socket),
    do: {:noreply, socket}

  def handle_event("prepare-worktree", params, socket) do
    socket = worktree_input(socket, params)

    result =
      ArenaGit.request(
        socket.assigns.git_key,
        socket.assigns.arena.id,
        "worktree",
        socket.assigns.worktree_observation,
        socket.assigns.worktree_confirmed
      )

    {:noreply, git_result(socket, result)}
  end

  def handle_event("inspect-worktree", _, %{assigns: %{setup_busy: true}} = socket),
    do: {:noreply, socket}

  def handle_event("inspect-worktree", %{"id" => id}, socket) do
    result =
      ArenaGit.request(socket.assigns.git_key, socket.assigns.arena.id, "inspect_worktree", id)

    {:noreply, git_result(socket, result)}
  end

  def handle_event("cancel-worktree-inspection", %{"id" => id}, socket) do
    if Enum.any?(Map.values(socket.assigns.worktree_inspections), &(&1 && &1.id == id)),
      do: Foundation.cancel_probe(id)

    {:noreply, refresh(socket)}
  end

  def handle_event("cancel-worktree", %{"id" => id}, socket) do
    if Enum.any?(socket.assigns.worktrees, &(&1.id == id)), do: Foundation.cancel_probe(id)
    {:noreply, refresh(socket)}
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
      cond do
        not socket.assigns.form_matches or is_nil(socket.assigns.board) ->
          {:error, "stale_form"}

        Battles.locked?(socket.assigns.board.id, socket.assigns.task_id) ->
          {:error, "task_locked"}

        true ->
          Tabulae.save(
            socket.assigns.key,
            socket.assigns.arena.id,
            socket.assigns.board.id,
            socket.assigns.task_id,
            socket.assigns.revision,
            socket.assigns.content
          )
      end

    case result do
      {:ok, revision} ->
        {:noreply,
         socket
         |> assign(error: nil, message: "Task saved · revision #{revision.revision}.")
         |> draft(nil)
         |> push_event("dialog-close", %{id: "draft-editor"})
         |> refresh()}

      {:error, reason} ->
        {:noreply, assign(socket, error: message(reason), key: Ecto.UUID.generate())}
    end
  end

  def handle_event("edit", %{"id" => id} = params, socket) do
    column = if params["column"] == "todo", do: "todo", else: "specs"

    if id == "new" || Enum.any?(socket.assigns.tasks, &(&1.id == id)) do
      if socket.assigns.dirty do
        {:noreply, assign(socket, :pending_edit, {id, column})}
      else
        {:noreply, select_task(socket, id, column)}
      end
    else
      {:noreply, assign(socket, :error, message("scope_missing"))}
    end
  end

  def handle_event("discard", _, socket) do
    case socket.assigns.pending_edit do
      {id, column} -> {:noreply, select_task(socket, id, column)}
      _ -> {:noreply, socket}
    end
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
    editing = board != nil and socket.assigns.revision > 0
    git = ArenaGit.latest(socket.assigns.arena.id)
    worktrees = ArenaGit.worktrees(socket.assigns.arena.id)
    paths = if git, do: git.payload["paths"] || [], else: []

    socket
    |> assign(
      arena_team: TeamAssignments.assigned(socket.assigns.arena),
      board_team: if(board, do: TeamAssignments.assigned(board)),
      saved_team: Cuckoding.Team.current(),
      git: git,
      worktrees: worktrees,
      worktree_inspections: ArenaGit.worktree_inspections(socket.assigns.arena.id, worktrees),
      worktree_confirmed: current_worktree_consent?(socket, git),
      git_paths: socket.assigns.git_paths || Enum.join(paths, "\n"),
      setup_busy: Foundation.pending?(),
      now: DateTime.utc_now(),
      boards: Tabulae.list(socket.assigns.arena.id),
      tasks: if(board, do: Tabulae.tasks(board.id), else: []),
      source:
        if(editing,
          do: Tabulae.source(board.id, socket.assigns.task_id)
        ),
      history:
        if(editing,
          do: Tabulae.history(board.id, socket.assigns.task_id),
          else: []
        )
    )
    |> refresh_board_activity()
    |> refresh_battle()
  end

  defp refresh_board_activity(%{assigns: %{board: nil}} = socket),
    do: assign(socket, board_summary: nil, board_work: nil)

  defp refresh_board_activity(socket) do
    board = socket.assigns.board

    assign(socket,
      board_summary: Dashboard.board(board.arena_id, board.id),
      board_work: Dashboard.work(board.arena_id, board.id)
    )
  end

  defp refresh_battle(%{assigns: %{board: nil}} = socket) do
    assign(socket,
      battle: nil,
      battle_tasks: [],
      battle_projection: %{},
      battle_attempts: [],
      battle_preview: nil,
      editing_locked: false
    )
  end

  defp refresh_battle(socket) do
    board = socket.assigns.board
    battle = Battles.latest(board.arena_id, board.id)

    preview =
      case Battles.preview(board.arena_id, board.id) do
        {:ok, preview} -> preview
        _ -> nil
      end

    assign(socket,
      battle: battle,
      battle_tasks: if(battle, do: Battles.tasks(battle.id), else: []),
      battle_projection: Battles.projections(board.id),
      battle_attempts: if(battle, do: Battles.attempts(battle.id), else: []),
      battle_preview: preview,
      editing_locked:
        socket.assigns.revision > 0 && Battles.locked?(board.id, socket.assigns.task_id)
    )
  end

  defp current_worktree_consent?(socket, git),
    do:
      socket.assigns.worktree_confirmed && ArenaGit.can_prepare?(git) &&
        socket.assigns.worktree_observation == git.id

  defp worktree_input(socket, params) do
    current = socket.assigns.git

    confirmed =
      ArenaGit.can_prepare?(current) and params["observation_id"] == current.id and
        params["key"] == socket.assigns.git_key and params["confirmed"] == "true"

    assign(socket,
      worktree_confirmed: confirmed,
      worktree_observation: if(confirmed, do: current.id)
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
      worktree_confirmed: false,
      worktree_observation: nil,
      git_key: Ecto.UUID.generate(),
      init_confirmed: false,
      confirmed_observation: nil,
      commit_confirmed: false,
      confirmed_preview: nil
    )
    |> refresh()
  end

  defp git_active?(command), do: command && command.state in ~w(pending running cancelling)

  defp inspection_message("worktree_unchanged"),
    do:
      "Ownership, locked detached commit, index entries and raw tracked bytes matched; no extra files observed."

  defp inspection_message("worktree_changed"),
    do:
      "Files or index differ from the prepared commit. Your work is retained. Built-in Git checkout transformations can also cause differences."

  defp inspection_message("worktree_mismatch"),
    do:
      "Ownership, folder identity or Git registration could not be verified. Nothing was changed or removed."

  defp inspection_message(status)
       when status in ~w(cancelled interrupted timeout cleanup_uncertain),
       do:
         "Inspection stopped without a usable observation. Inspect again when ready; nothing is retried automatically."

  defp inspection_message(_),
    do:
      "Inspection could not verify this checkout within the supported configuration and limits. No files were changed."

  defp worktree_inspection(assigns) do
    ~H"""
    <div id={"inspection-#{@preparation.id}"}>
      <button
        type="button"
        class="button"
        phx-click="inspect-worktree"
        phx-value-id={@preparation.id}
        aria-disabled={to_string(@busy)}
      >Inspect worktree</button>
      <div :if={@inspection} role="status">
        <p>
          Inspection · {@inspection.state} · {Calendar.strftime(
            @inspection.updated_at,
            "%Y-%m-%d %H:%M:%S UTC"
          )}
        </p>
        <p :if={git_active?(@inspection)} class="fine-print">
          User · system Git · no model · {max(0, DateTime.diff(@now, @inspection.updated_at))}s elapsed
          · 15s native limit
        </p>
        <p :if={@inspection.result}>{inspection_message(@inspection.result)}</p>
      </div>
      <button
        :if={git_active?(@inspection)}
        type="button"
        class="button"
        phx-click="cancel-worktree-inspection"
        phx-value-id={@inspection.id}
        disabled={@inspection.state == "cancelling"}
      >Cancel inspection</button>
      <p class="fine-print">A dated observation, not permission to execute. Recheck before use;
        files can change immediately. No filters run, and extra file contents are never read.</p>
    </div>
    """
  end

  defp worktree_message(status)
       when status in ~w(worktree_incomplete worktree_exists cancelled interrupted timeout cleanup_uncertain),
       do:
         "Preparation stopped or needs inspection. Its ownership record and any partial checkout or Git metadata are retained. Nothing is retried or deleted automatically."

  defp worktree_message(status), do: git_message(status)

  defp git_message("prepared"),
    do:
      "Detached, locked checkout prepared. This records its creation; starting work requires a separate Arena Start."

  defp git_message("unsafe_tree"),
    do:
      "This commit contains unsupported paths, links, submodules or known credential names. No checkout was created."

  defp git_message("tree_limit"),
    do:
      "The commit exceeds checkout limits: 10,000 files, 8 MiB per file, 64 MiB total or 1 MiB of tree metadata."

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

  defp select_task(socket, "new", column) do
    socket = select_task(socket, "new")
    assign(socket, :content, Map.put(socket.assigns.content, "column", column))
  end

  defp select_task(socket, id, _column), do: select_task(socket, id)

  defp select_task(socket, id) do
    task = Enum.find(socket.assigns.tasks, &(&1.id == id))
    socket |> draft(task) |> assign(error: nil, message: nil, pending_edit: nil) |> refresh()
  end

  defp draft(socket, task) do
    content =
      if task,
        do: Tabulae.content(task),
        else: %{
          "title" => "",
          "description" => "",
          "criteria" => "",
          "column" => "specs",
          "depends_on" => []
        }

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
    dependencies = Map.get(params, "depends_on", socket.assigns.content["depends_on"])

    matches =
      socket.assigns.board != nil and params["task_id"] == socket.assigns.task_id and
        params["revision"] == to_string(socket.assigns.revision) and
        params["tabula_id"] == socket.assigns.board.id

    if bounded && map_size(content) == 4 && bounded_dependencies?(dependencies) do
      content = Map.put(content, "depends_on", List.delete(dependencies, ""))

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

  defp bounded_dependencies?(ids) when is_list(ids),
    do: length(ids) <= 17 and Enum.all?(ids, &(is_binary(&1) and byte_size(&1) <= 36))

  defp bounded_dependencies?(_), do: false

  defp role_name(team, key) do
    case Enum.find(team.definition["roles"], &(&1["id"] == key)) do
      nil -> "System result"
      role -> role["name"]
    end
  end

  defp dependency_label(tasks, id) do
    case Enum.find(tasks, &(&1.id == id)) do
      nil -> id
      task -> "#{task.title} · #{String.slice(id, 0, 8)}"
    end
  end

  defp message("invalid_board"), do: "Enter a Tabula name of 1–80 characters."

  defp message("invalid_task"),
    do:
      "Enter a title (1–120 characters), description (up to 8,000), criteria (up to 4,000) and up to 16 distinct prerequisites."

  defp message("invalid_dependencies"),
    do: "Choose other tasks in this Tabula as prerequisites. Your draft is kept."

  defp message("dependency_cycle"),
    do:
      "These prerequisites create a circular dependency. Your draft is kept; revise the selection."

  defp message("criteria_required"),
    do: "ToDo needs a description and acceptance criteria. Your draft is kept."

  defp message("stale_task"),
    do:
      "This task changed elsewhere. Your draft is kept; copy it before loading the current task."

  defp message("stale_form"),
    do:
      "This recovered form belongs to another editor. Your text is kept; copy it before starting a new draft."

  defp message("stage_unavailable"),
    do: "Delivery stages move automatically through battle execution and independent review."

  defp message("battle_active"),
    do: "This task belongs to the active battle and cannot be edited. Your unsaved text is kept."

  defp message("task_locked"), do: message("battle_active")

  defp message(_), do: "This Arena, Tabula or task is unavailable. Your draft is kept."

  defp task_column(task, projection) do
    case projection[task.id] do
      %{snapshot: %{"revision" => revision}} when revision != task.revision ->
        task.column

      %{state: "pending"} ->
        "todo"

      %{state: state} when state in ~w(specs todo in_process review completed) ->
        state

      %{state: state, context: %{"column" => column}}
      when state in ~w(needs_attention skipped deferred) and
             column in ~w(specs todo in_process review completed) ->
        column

      _ ->
        task.column
    end
  end

  defp task_status(task, projection) do
    case projection[task.id] do
      nil ->
        "Draft · revision #{task.revision}"

      %{snapshot: %{"revision" => revision}} when revision != task.revision ->
        "Draft · revision #{task.revision} · earlier battle retained in Inspect"

      result ->
        "#{String.replace(result.state, "_", " ")} · frozen revision #{result.snapshot["revision"]}"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.workspace active={:arenas} title={@arena.name} flash={@flash}>
      <Layouts.journey
        :if={@board}
        current={if @tasks == [], do: 4, else: 5}
        arena_path={~p"/arenas/#{@arena.id}/tabulae/#{@board.id}"}
      />
      <section class="panel arena-panel" aria-labelledby="tabula-title">
        <div class="panel-heading">
          <div>
            <p class="eyebrow">TABULA · BOARD</p>
            <h2 id="tabula-title">
              {if @board, do: @board.name, else: "Your board is ready to create."}
            </h2>
            <p class="fine-print arena-path">{@arena.path}</p>
          </div>
          <button
            :if={@board}
            type="button"
            id="open-board-team"
            aria-controls="board-team"
            class="button"
            phx-click={JS.dispatch("cc:open", to: "#board-team")}
          >Board team</button>
        </div>
        <p
          :if={@board && @board_team.definition != @saved_team.definition}
          id="board-team-changed"
          class="fine-print"
        >
          Your saved team has changed.
          <button
            type="button"
            aria-controls="board-team"
            class="text-link"
            phx-click={JS.dispatch("cc:open", to: "#board-team")}
          >Review saved team</button>
          to use those assignments here.
        </p>
        <.modal :if={@board} id="board-team" title="Board team">
          <.live_component
            module={CuckodingWeb.TeamAdoptionComponent}
            id="scope-team"
            session_id={@session_id}
            scope={@board}
            expanded={true}
            revision={@board_team.id}
            now={@now}
          />
        </.modal>
        <.live_component
          :if={@board}
          module={CuckodingWeb.PlanningComponent}
          id="planning"
          session_id={@session_id}
          board={@board}
          empty={@tasks == []}
          now={@now}
          busy={@setup_busy}
        />
        <.live_component
          :if={@board}
          module={CuckodingWeb.BattleComponent}
          id="arena-battle"
          session_id={@session_id}
          board={@board}
          preview={@battle_preview}
          battle={@battle}
          battle_tasks={@battle_tasks}
          attempts={@battle_attempts}
          now={@now}
        />
        <details
          :if={@board_summary}
          id="board-activity"
          class="activity retained-activity"
          phx-mounted={JS.ignore_attributes("open")}
        >
          <summary>
            Board activity · {if @board_summary.battle_id,
              do: "#{@board_summary.completed} / #{@board_summary.total} battle tasks completed",
              else:
                "#{@board_summary.total} saved #{if @board_summary.total == 1, do: "task", else: "tasks"}"}
          </summary>
          <CuckodingWeb.DashboardComponent.work_rows
            id="board-workers"
            work={@board_work}
            now={@now}
            scoped={true}
          />
          <p class="fine-print">
            Saved board team · future work uses these assignments. A started battle keeps its frozen team in Inspect.
          </p>
          <ul id="board-saved-team" class="activity-entries">
            <li :for={role <- @board_summary.team}>
              {role["name"]} · {role["agent_name"]} · {if role["model_id"] in [
                                                            nil,
                                                            ""
                                                          ],
                                                          do: "No model selected",
                                                          else: role["model_id"]}
            </li>
          </ul>
        </details>
        <div :if={length(@boards) > 1} class="team-actions" aria-label="Tabulae">
          <.link
            :for={board <- @boards}
            navigate={~p"/arenas/#{@arena.id}/tabulae/#{board.id}"}
            class="button"
            aria-current={if @board && @board.id == board.id, do: "page"}
          >{board.name}</.link>
        </div>
        <p
          :if={
            git_active?(@git) || Enum.any?(@worktrees, &git_active?/1) ||
              Enum.any?(Map.values(@worktree_inspections), &git_active?/1)
          }
          role="status"
          class="notice"
        >
          A repository operation is active. Open Advanced → Repository setup for progress and Cancel.
        </p>
        <details
          id="arena-advanced"
          open={is_nil(@board)}
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Advanced</summary>
          <.link navigate={~p"/arenas/#{@arena.id}/checks"} class="text-link">Extra command checks (optional) ↗</.link>
          <.link
            :if={@board}
            navigate={~p"/arenas/#{@arena.id}/tabulae/#{@board.id}/battle"}
            class="text-link"
          >Battle preview · read only ↗</.link>
          <.live_component
            :if={!@board}
            module={CuckodingWeb.TeamAdoptionComponent}
            id="scope-team"
            session_id={@session_id}
            scope={@arena}
            revision={@arena_team.id}
            now={@now}
          />
          <.live_component
            :if={@board}
            module={CuckodingWeb.TeamAdoptionComponent}
            id="arena-team"
            session_id={@session_id}
            scope={@arena}
            revision={@arena_team.id}
            now={@now}
          />
          <div class="team-actions">
            <button type="button" class="button" phx-click={JS.dispatch("cc:open", to: "#arena-git")}>Repository setup</button>
            <button
              type="button"
              class="button"
              phx-click={JS.dispatch("cc:open", to: "#create-tabula")}
            >Add another board</button>
          </div>
          <.modal id="arena-git" title="Repository setup">
            <p class="arena-path">{@arena.path}</p>
            <p class="fine-print">
              Inspect local Git metadata. This grants no agent access and does not stage, commit or contact a remote.
            </p>
            <p :if={@git_error} role="alert" class="notice">{@git_error}</p>
            <p :if={@git && !git_active?(@git)} role="status">{git_message(@git.result)}</p>
            <p :if={@git && @git.payload["observation"]} class="fine-print">
              Observed {Calendar.strftime(@git.updated_at, "%Y-%m-%d %H:%M:%S UTC")}
              <code :if={@git.payload["observation"]["head"]}>HEAD {@git.payload["observation"][
                "head"
              ]}</code>
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
            <details id="worktree-setup" phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}>
              <summary>Isolated worktrees</summary>
              <p class="fine-print">
                Prepare committed files in a private detached checkout. Unsaved, staged and
                untracked changes stay in your original folder. This adds locked Git worktree
                metadata to the repository. It runs no agents or project checks and does not start a battle.
              </p>
              <.form
                :if={ArenaGit.can_prepare?(@git, @now)}
                for={%{}}
                id="worktree-form"
                phx-change="worktree-change"
                phx-submit="prepare-worktree"
              >
                <input type="hidden" name="observation_id" value={@git.id} />
                <input type="hidden" name="key" value={@git_key} />
                <p>Commit: <code>{@git.payload["observation"]["head"]}</code></p>
                <p>Checkout: <code>{ArenaGit.worktree_path(@git_key)}</code></p>
                <p class="fine-print">Up to 10,000 regular files, 8 MiB each / 64 MiB total;
                  1 MiB of tree metadata. Links, submodules, Git filters and known credential paths are refused.
                  Partial effects are retained for inspection.</p>
                <label class="confirm-executable">
                  <input type="checkbox" name="confirmed" value="true" checked={@worktree_confirmed} />
                  Create this isolated checkout from the displayed commit and retain its Git registration.
                </label>
                <button class="button" aria-disabled={to_string(@setup_busy)}>Prepare worktree</button>
              </.form>
              <p :if={!ArenaGit.can_prepare?(@git, @now)}>
                Inspect Git to confirm a current committed baseline before preparing a worktree.
              </p>
              <ul id="worktree-receipts" class="git-files">
                <li :for={command <- @worktrees} id={"worktree-#{command.id}"}>
                  <strong>{command.state}</strong>
                  · {Calendar.strftime(command.inserted_at, "%Y-%m-%d %H:%M UTC")}
                  <p :if={git_active?(command)} role="status">
                    User · system Git · no model · {max(0, DateTime.diff(@now, command.updated_at))}s elapsed
                    · 15s native limit
                  </p>
                  <button
                    :if={git_active?(command)}
                    type="button"
                    class="button"
                    phx-click="cancel-worktree"
                    phx-value-id={command.id}
                    disabled={command.state == "cancelling"}
                  >
                    {if command.state == "cancelling",
                      do: "Waiting for cleanup…",
                      else: "Cancel preparation"}
                  </button>
                  <p :if={command.result} role="status">{worktree_message(command.result)}</p>
                  <p :if={command.payload["head"]}>Commit: <code>{command.payload["head"]}</code></p>
                  <p :if={command.payload["worktree_path"]}>
                    Retained location: <code>{command.payload["worktree_path"]}</code>
                  </p>
                  <.worktree_inspection
                    :if={command.state == "completed" && command.result == "prepared"}
                    preparation={command}
                    inspection={@worktree_inspections[command.id]}
                    now={@now}
                    busy={@setup_busy}
                  />
                </li>
              </ul>
              <p :if={@worktrees != []} class="fine-print">
                Latest 10 attempts. Older receipts remain in local storage.
                A creation receipt does not verify the checkout's current contents. Worktrees share Git metadata;
                they are not a security sandbox.
              </p>
            </details>
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
              <button
                type="submit"
                class="button"
                disabled={@setup_busy}
                phx-disable-with="Starting…"
              >Initialize Git</button>
            </.form>
            <.form
              :if={
                @git && @git.state == "completed" && @git.result in ~w(unborn initialized previewed)
              }
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
          </.modal>
          <.modal id="create-tabula" title="Add another board">
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
                Uses this Arena’s saved team. Creating a board starts no agents.
              </p>
              <p :if={@board_error} role="alert" class="notice">{@board_error}</p>
              <button type="submit" class="button" phx-disable-with="Creating…">Create Tabula</button>
            </.form>
          </.modal>
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
              <div class="column-heading">
                <h3 id={"heading-#{column["key"]}"}>{column["name"]}</h3>
                <button
                  :if={column["key"] in ~w(specs todo)}
                  type="button"
                  class="button icon-button"
                  aria-label={"Add task to #{column["name"]}"}
                  phx-click={
                    JS.push("edit", value: %{id: "new", column: column["key"]})
                    |> JS.dispatch("cc:open", to: "#draft-editor")
                  }
                >
                  <span aria-hidden="true">+</span>
                </button>
              </div>
              <p class="fine-print">{role_name(@board_team, column["role"])}</p>
              <p
                :if={!Enum.any?(@tasks, &(task_column(&1, @battle_projection) == column["key"]))}
                class="fine-print"
              >
                No tasks yet
              </p>
              <article
                :for={
                  task <- Enum.filter(@tasks, &(task_column(&1, @battle_projection) == column["key"]))
                }
                id={"task-#{task.id}"}
                class="task-card"
              >
                <h4>{task.title}</h4>
                <p class="fine-print">{task_status(task, @battle_projection)}</p>
                <p :if={task.depends_on != []} class="fine-print">
                  Prerequisites: {Enum.map_join(task.depends_on, "; ", &dependency_label(@tasks, &1))}
                </p>
                <button
                  type="button"
                  class="button"
                  phx-click={
                    JS.dispatch("cc:open", to: "#draft-editor")
                    |> Phoenix.LiveView.JS.push("edit", value: %{id: task.id})
                  }
                  aria-label={"#{if Map.has_key?(@battle_projection, task.id), do: "Inspect", else: "Edit"} #{task.title}"}
                >{if Map.has_key?(@battle_projection, task.id), do: "Inspect task", else: "Edit task"}</button>
              </article>
            </section>
          </div>
        </div>
        <p :if={@board} class="fine-print">
          New tasks added during a battle wait for the next Start.
        </p>
        <.live_component
          module={CuckodingWeb.ActivityComponent}
          id="arena-activity"
          arena_id={@arena.id}
          session_id={@session_id}
          now={@now}
        />
      </section>
      <.modal
        :if={@board}
        id="draft-editor"
        title={if @revision == 0, do: "Add task", else: "Task details"}
      >
        <div :if={@pending_edit} role="alert" class="notice">
          <p>Discard your unsaved edits and open the selected draft?</p>
          <button type="button" class="button" phx-click="keep">Keep editing</button>
          <button type="button" class="button" phx-click="discard">Discard unsaved edits</button>
        </div>
        <.live_component
          :if={@revision > 0}
          module={CuckodingWeb.TaskEvidenceComponent}
          id="task-evidence"
          session_id={@session_id}
          board={@board}
          task_id={@task_id}
          draft_revision={@revision}
          dirty={@dirty}
        />
        <.form
          for={%{}}
          id="draft-form"
          phx-change="change"
          phx-submit="save"
          aria-describedby={if @error, do: "draft-error"}
        >
          <p :if={@editing_locked} id="draft-locked" role="status" class="notice">
            This task is frozen in the active battle. Your unsaved text is kept; new drafts can still be added for a later battle.
          </p>
          <fieldset
            class="role-fields"
            disabled={@editing_locked}
            aria-labelledby="draft-editor-title"
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
            <label for="draft-criteria">Acceptance criteria and checks</label>
            <textarea id="draft-criteria" name="criteria" rows="4" maxlength="4000">{@content["criteria"]}</textarea>
            <label for="draft-column">Column</label>
            <select id="draft-column" name="column">
              <option value="specs" selected={@content["column"] == "specs"}>
                Specs · refine the task
              </option>
              <option value="todo" selected={@content["column"] == "todo"}>
                ToDo · planned work
              </option>
            </select>
            <fieldset id="draft-prerequisites" aria-describedby="prerequisites-help">
              <legend>Prerequisites</legend>
              <p id="prerequisites-help" class="fine-print">
                Choose up to 16 tasks that must come first. This records a plan; it does not start work.
              </p>
              <input type="hidden" name="depends_on[]" value="" />
              <label
                :for={task <- Enum.reject(@tasks, &(&1.id == @task_id))}
                class="confirm-executable"
              >
                <input
                  id={"depends-on-#{task.id}"}
                  type="checkbox"
                  name="depends_on[]"
                  value={task.id}
                  checked={task.id in @content["depends_on"]}
                />
                {dependency_label(@tasks, task.id)}
              </label>
              <p :if={!Enum.any?(@tasks, &(&1.id != @task_id))} class="fine-print">
                Save another task to add a prerequisite.
              </p>
            </fieldset>
            <p class="fine-print">
              ToDo needs a description and criteria. These are database drafts; project files stay untouched.
            </p>
            <p :if={@error} id="draft-error" role="alert" class="notice">{@error}</p>
            <button
              id="draft-save"
              type="submit"
              class="button primary"
              phx-disable-with="Saving…"
            >Save task</button>
          </fieldset>
        </.form>
        <.live_component
          :if={@revision > 0 && !@editing_locked}
          module={CuckodingWeb.SpecificationComponent}
          id="task-specifications"
          session_id={@session_id}
          board={@board}
          task_id={@task_id}
          revision={@revision}
          dirty={@dirty || !@form_matches}
          now={@now}
        />
        <details
          :if={@source}
          id="draft-source"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Original proposal sources</summary>
          <p class="fine-print">
            Proposal {@source.plan_id} · suggestion {@source.index + 1}.
            These snapshots describe the original import, not later draft edits or live files.
          </p>
          <p :if={@source.documents == []} class="fine-print">
            No task-specific document citations.
          </p>
          <CuckodingWeb.PlanningComponent.documents
            id="draft-source-document"
            files={@source.documents}
          />
        </details>
        <details
          :if={@history != []}
          id="draft-history"
          phx-mounted={Phoenix.LiveView.JS.ignore_attributes("open")}
        >
          <summary>Saved history · latest five revisions</summary>
          <article :for={revision <- @history} class="team-role">
            <h3>Revision {revision.revision} · {revision.content["column"]}</h3>
            <p class="fine-print">
              {Calendar.strftime(revision.inserted_at, "%Y-%m-%d %H:%M UTC")}
            </p>
            <h4>{revision.content["title"]}</h4>
            <p class="draft-copy">{revision.content["description"]}</p>
            <p class="draft-copy">{revision.content["criteria"]}</p>
            <p class="fine-print">
              Prerequisites (current task names): {case Map.get(revision.content, "depends_on", []) do
                [] -> "None"
                ids -> Enum.map_join(ids, "; ", &dependency_label(@tasks, &1))
              end}
            </p>
          </article>
        </details>
      </.modal>
    </Layouts.workspace>
    """
  end
end
