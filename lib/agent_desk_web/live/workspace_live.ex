defmodule AgentDeskWeb.WorkspaceLive do
  @moduledoc """
  Desktop application shell: project sidebar, agent tabs, activity, and approvals.
  """

  use AgentDeskWeb, :live_view

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Graph
  alias AgentDesk.A2A.Workflows
  alias AgentDesk.Agents
  alias AgentDesk.Git
  alias AgentDesk.Ids
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Project
  alias AgentDesk.Projects.Runtime
  alias AgentDesk.Projects.Supervisor, as: ProjectSupervisor
  alias AgentDesk.Providers
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Resources.Overlap
  alias AgentDesk.Reviews
  alias AgentDesk.Scope
  alias AgentDesk.Worktrees
  alias AgentDesk.Worktrees.Handoffs

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgentDesk.PubSub, "projects")
      send(self(), :restore_last_project)
    end

    {:ok,
     socket
     |> assign(:page_title, "AgentDesk")
     |> assign(:path, "")
     |> assign(:current_project, nil)
     |> assign(:recent_projects, [])
     |> assign(:live_project_ids, [])
     |> assign(:confirm_close_project_id, nil)
     |> assign(:sessions, [])
     |> assign(:active_session_id, nil)
     |> assign(:active_status, "idle")
     |> assign(:pending_approval, nil)
     |> assign(:prompt, "")
     |> assign(:display_name, "")
     |> assign(:sdk_executable, "")
     |> assign(:sdk_args, "")
     |> assign(:connect_path, nil)
     |> assign(:usage, %{
       "input_tokens" => 0,
       "output_tokens" => 0,
       "total_tokens" => 0,
       "cost_cents" => 0
     })
     |> assign(:roles, [])
     |> assign(:provider, "fake")
     |> assign(:confirm_terminate, false)
     |> assign(:agents, [])
     |> assign(:leases, [])
     |> assign(:lease_previews, [])
     |> assign(:delegations, [])
     |> assign(:tasks, [])
     |> assign(:task_deps, %{})
     |> assign(:workflows, [])
     |> assign(:messages, [])
     |> assign(:artifacts, [])
     |> assign(:merge_queue, [])
     |> assign(:confirm_merge_id, nil)
     |> assign(:worktrees, [])
     |> assign(:active_worktree, nil)
     |> assign(:worktree_diff, "")
     |> assign(:unexpected_edits, [])
     |> assign(:confirm_cleanup, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:sync_path, nil)
     |> assign(:search_status, %{
       adapter: "Disabled",
       health: {:error, :unavailable},
       status: "unavailable",
       last_indexed_at: nil,
       error: nil
     })
     |> assign(:form, to_form(%{"path" => ""}))
     |> stream(:activity, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if connected?(socket) do
        socket
        |> assign(:recent_projects, Projects.list_recent())
        |> assign(:live_project_ids, live_project_ids())
        |> assign_current_project(params)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("validate", %{"path" => path}, socket) do
    {:noreply, assign(socket, path: path, form: to_form(%{"path" => path}))}
  end

  def handle_event("open_project", %{"path" => path}, socket) do
    case Projects.open_project(path) do
      {:ok, project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Opened #{project.name}")
         |> push_patch(to: ~p"/projects/#{project.id}")}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "That path does not exist.")}

      {:error, :not_a_directory} ->
        {:noreply, put_flash(socket, :error, "That path is not a directory.")}

      {:error, :not_a_git_repository} ->
        {:noreply,
         put_flash(socket, :error, "Open a Git repository. AgentDesk does not initialize repos.")}

      {:error, :symlink_loop} ->
        {:noreply, put_flash(socket, :error, "Could not resolve that path.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not open that project.")}
    end
  end

  def handle_event("confirm_close_project", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_close_project_id, id)}
  end

  def handle_event("cancel_close_project", _params, socket) do
    {:noreply, assign(socket, :confirm_close_project_id, nil)}
  end

  def handle_event("close_project", %{"id" => id}, socket) do
    case Projects.close_project(id) do
      :ok ->
        {:noreply, after_project_closed(socket, id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not close that project.")}
    end
  end

  def handle_event(_event, _params, %{assigns: %{current_project: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Open a project first.")}
  end

  def handle_event("session_form", params, socket) do
    {:noreply,
     socket
     |> assign(:provider, params["provider"] || socket.assigns.provider)
     |> assign(:display_name, params["display_name"] || "")
     |> assign(:sdk_executable, params["sdk_executable"] || "")
     |> assign(:sdk_args, params["sdk_args"] || "")}
  end

  def handle_event("start_session", params, socket) do
    project = socket.assigns.current_project
    provider = params["provider"]
    name = params["display_name"]
    name = if is_binary(name) and String.trim(name) != "", do: name, else: provider

    attrs = %{
      provider: provider,
      display_name: name,
      role_id: params["role_id"],
      settings: session_settings(params)
    }

    case Providers.start_session(Scope.for_project(project), attrs) do
      {:ok, session} ->
        {:noreply,
         socket
         |> assign(:display_name, "")
         |> assign(:sessions, Agents.visible_sessions(Scope.for_project(project)))
         |> select_session(session)
         |> load_coordination(project)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not start that provider session.")}
    end
  end

  def handle_event("save_role", params, socket) do
    project = socket.assigns.current_project

    attrs = %{
      name: params["name"],
      description: params["description"] || "",
      prompt: params["prompt"] || "",
      permission_profile: params["permission_profile"] || "default"
    }

    socket =
      case AgentDesk.Roles.save(project, attrs) do
        {:ok, _role} -> put_flash(socket, :info, "Saved role.")
        {:error, _reason} -> put_flash(socket, :error, "Could not save that role.")
      end

    {:noreply, load_coordination(socket, project)}
  end

  def handle_event("select_tab", %{"id" => id}, socket) do
    {:noreply, select_session_id(socket, id)}
  end

  def handle_event("close_tab", %{"id" => id}, socket) do
    project = socket.assigns.current_project

    case Agents.get_session(Scope.for_project(project), id) do
      {:ok, session} ->
        {:ok, _} = Agents.hide_tab(session)
        sessions = Agents.visible_sessions(Scope.for_project(project))
        socket = assign(socket, :sessions, sessions)

        socket =
          if socket.assigns.active_session_id == id do
            select_session(socket, List.first(sessions))
          else
            socket
          end

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_event("send_prompt", %{"prompt" => prompt}, socket) do
    with session_id when is_binary(session_id) <- socket.assigns.active_session_id,
         :ok <- SessionWorker.prompt(session_id, prompt) do
      {:noreply, assign(socket, :prompt, "")}
    else
      _ -> {:noreply, put_flash(socket, :error, "No active session to prompt.")}
    end
  end

  def handle_event("interrupt", _params, socket) do
    _ =
      socket.assigns.active_session_id &&
        SessionWorker.interrupt(socket.assigns.active_session_id)

    {:noreply, socket}
  end

  def handle_event("confirm_terminate", _params, socket) do
    {:noreply, assign(socket, :confirm_terminate, true)}
  end

  def handle_event("cancel_terminate", _params, socket) do
    {:noreply, assign(socket, :confirm_terminate, false)}
  end

  def handle_event("terminate", _params, socket) do
    _ =
      socket.assigns.active_session_id &&
        SessionWorker.terminate_session(socket.assigns.active_session_id)

    {:noreply, assign(socket, :confirm_terminate, false)}
  end

  def handle_event("resume_session", %{"id" => id}, socket) do
    project = socket.assigns.current_project

    case Agents.get_session(Scope.for_project(project), id) do
      {:ok, session} ->
        _ = Providers.resume_session(session)
        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, socket}
    end
  end

  def handle_event("approve", %{"id" => request_id}, socket) do
    _ = SessionWorker.approve(socket.assigns.active_session_id, request_id, "allow")
    {:noreply, assign(socket, :pending_approval, nil)}
  end

  def handle_event("deny", %{"id" => request_id}, socket) do
    _ = SessionWorker.approve(socket.assigns.active_session_id, request_id, "deny")
    {:noreply, assign(socket, :pending_approval, nil)}
  end

  def handle_event("accept_delegation", %{"id" => id}, socket) do
    {:noreply, decide_delegation(socket, id, :accept)}
  end

  def handle_event("reject_delegation", %{"id" => id}, socket) do
    {:noreply, decide_delegation(socket, id, :reject)}
  end

  def handle_event("commit_worktree", %{"message" => message}, socket) do
    _ =
      socket.assigns.active_worktree &&
        Worktrees.commit(socket.assigns.active_worktree, message)

    {:noreply, load_coordination(socket, socket.assigns.current_project)}
  end

  def handle_event("publish_handoff", %{"summary" => summary}, socket) do
    publish_active_handoff(socket, summary)
  end

  def handle_event("accept_queue_item", %{"artifact_id" => artifact_id}, socket) do
    _ = Handoffs.accept(reviewer_scope(socket), artifact_id)
    {:noreply, load_coordination(socket, socket.assigns.current_project)}
  end

  def handle_event("reject_queue_item", %{"artifact_id" => artifact_id}, socket) do
    _ = Handoffs.reject(reviewer_scope(socket), artifact_id)
    {:noreply, load_coordination(socket, socket.assigns.current_project)}
  end

  def handle_event("confirm_merge", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_merge_id, id)}
  end

  def handle_event("cancel_merge", _params, socket) do
    {:noreply, assign(socket, :confirm_merge_id, nil)}
  end

  def handle_event("merge_queue_item", %{"id" => id}, socket) do
    project = socket.assigns.current_project

    socket =
      case Reviews.merge(project, id) do
        {:ok, _item} ->
          socket
          |> assign(:confirm_merge_id, nil)
          |> put_flash(:info, "Merged into #{project.default_branch || "HEAD"}.")

        {:error, :policy_failed} ->
          put_flash(socket, :error, "Required checks have not passed.")

        {:error, :conflict} ->
          put_flash(socket, :error, "Git reports unresolved conflicts.")

        {:error, :dirty_worktree} ->
          put_flash(socket, :error, "The primary worktree is dirty.")

        {:error, :not_accepted} ->
          put_flash(socket, :error, "Accept the handoff before merging.")

        {:error, _reason} ->
          put_flash(socket, :error, "Could not merge that handoff.")
      end

    {:noreply, load_coordination(socket, project)}
  end

  def handle_event("create_task", %{"title" => title}, socket) do
    project = socket.assigns.current_project
    scope = reviewer_scope(socket)

    socket =
      with {:ok, context} <- A2A.ensure_working_context(scope),
           {:ok, _task} <- A2A.create_task(scope, context, %{title: title}) do
        socket
      else
        {:error, _reason} -> put_flash(socket, :error, "Could not create that task.")
      end

    {:noreply, load_coordination(socket, project)}
  end

  def handle_event(
        "add_task_dependency",
        %{"task_id" => task_id, "depends_on_id" => prereq},
        socket
      ) do
    project = socket.assigns.current_project
    scope = reviewer_scope(socket)

    socket =
      case Graph.add_dependency(scope, task_id, prereq) do
        {:ok, _edge} -> socket
        {:error, :cycle} -> put_flash(socket, :error, "That dependency would create a cycle.")
        {:error, _reason} -> put_flash(socket, :error, "Could not add that dependency.")
      end

    {:noreply, load_coordination(socket, project)}
  end

  def handle_event("complete_task", %{"id" => id}, socket) do
    project = socket.assigns.current_project
    scope = reviewer_scope(socket)

    socket =
      case Enum.find(socket.assigns.tasks, &(&1.id == id)) do
        nil ->
          put_flash(socket, :error, "Task not found.")

        task ->
          case A2A.update_task(scope, task, %{status: "completed"}) do
            {:ok, _} -> socket
            {:error, _} -> put_flash(socket, :error, "Could not complete that task.")
          end
      end

    {:noreply, load_coordination(socket, project)}
  end

  def handle_event("run_workflow", %{"name" => name, "steps" => steps}, socket) do
    project = socket.assigns.current_project
    scope = reviewer_scope(socket)
    titles = String.split(steps || "", "\n", trim: true)

    socket =
      with {:ok, context} <- A2A.ensure_working_context(scope),
           {:ok, _tasks} <- Workflows.instantiate_linear(scope, context, name, titles) do
        put_flash(socket, :info, "Started workflow #{name}.")
      else
        {:error, _reason} -> put_flash(socket, :error, "Could not start that workflow.")
      end

    {:noreply, load_coordination(socket, project)}
  end

  def handle_event("instantiate_workflow", %{"id" => id}, socket) do
    project = socket.assigns.current_project
    scope = reviewer_scope(socket)

    socket =
      with {:ok, context} <- A2A.ensure_working_context(scope),
           {:ok, _tasks} <- Workflows.instantiate(scope, id, context) do
        socket
      else
        {:error, _reason} -> put_flash(socket, :error, "Could not run that workflow.")
      end

    {:noreply, load_coordination(socket, project)}
  end

  def handle_event("cleanup_worktree", _params, socket) do
    {:noreply, assign(socket, :confirm_cleanup, true)}
  end

  def handle_event("cancel_cleanup", _params, socket) do
    {:noreply, assign(socket, :confirm_cleanup, false)}
  end

  def handle_event("search_project", %{"q" => q}, socket) do
    project = socket.assigns.current_project
    results = search_results(project, q)

    {:noreply,
     socket
     |> assign(:search_query, q)
     |> assign(:search_results, results)
     |> assign(:search_status, AgentDesk.Search.status(project))}
  end

  def handle_event("rebuild_search", _params, socket) do
    project = socket.assigns.current_project
    _ = AgentDesk.Search.rebuild(project)

    {:noreply,
     socket
     |> assign(:search_status, AgentDesk.Search.status(project))
     |> put_flash(:info, "Search rebuild requested.")}
  end

  def handle_event("export_sync", _params, socket) do
    case AgentDesk.Sync.export(socket.assigns.current_project) do
      {:ok, path} ->
        {:noreply,
         socket
         |> assign(:sync_path, path)
         |> put_flash(:info, "Sync bundle exported.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not export a sync bundle.")}
    end
  end

  def handle_event("import_sync", %{"path" => path}, socket) do
    case AgentDesk.Sync.import_bundle(socket.assigns.current_project, path) do
      {:ok, _counts} ->
        project = socket.assigns.current_project

        {:noreply,
         socket
         |> load_coordination(project)
         |> put_flash(:info, "Sync bundle imported.")}

      {:error, :sync_mismatch} ->
        {:noreply, put_flash(socket, :error, "Bundle does not match this Git repository.")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not import that sync bundle.")}
    end
  end

  def handle_event("confirm_cleanup", _params, socket) do
    project = socket.assigns.current_project
    worktree = socket.assigns.active_worktree
    _ = worktree && Worktrees.cleanup(project, worktree)

    {:noreply,
     socket
     |> assign(:confirm_cleanup, false)
     |> load_coordination(project)}
  end

  @impl true
  def handle_info(:restore_last_project, socket) do
    {:noreply, maybe_restore_last_project(socket)}
  end

  def handle_info({:project_opened, project}, socket) do
    {:noreply,
     socket
     |> assign(:recent_projects, Projects.list_recent())
     |> assign(:live_project_ids, live_project_ids())
     |> maybe_replace_current(project)}
  end

  def handle_info({:project_closed, project_id}, socket) do
    {:noreply, after_project_closed(socket, project_id)}
  end

  def handle_info({:session_updated, session}, socket) do
    if socket.assigns.current_project && session.project_id == socket.assigns.current_project.id do
      sessions = Agents.visible_sessions(Scope.for_project(socket.assigns.current_project))

      {:noreply,
       socket
       |> assign(:sessions, sessions)
       |> maybe_status(session)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:session_activity, session_id, events, status, approval}, socket) do
    if socket.assigns.active_session_id == session_id do
      socket =
        Enum.reduce(events, socket, fn event, acc ->
          item = %{
            id: Ids.generate(),
            type: Atom.to_string(event.type),
            text:
              event.payload["text"] || event.payload["summary"] || event.type |> Atom.to_string(),
            payload: event.payload
          }

          stream_insert(acc, :activity, item, at: -1, limit: -200)
        end)

      {:noreply, socket |> assign(:active_status, status) |> assign(:pending_approval, approval)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:merge_queue_changed, _project_id}, socket) do
    case socket.assigns.current_project do
      %Project{} = project ->
        {:noreply, load_coordination(socket, project)}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:worktrees_scanned, warnings}, socket) do
    case socket.assigns.current_project do
      %Project{} = project ->
        {:noreply,
         socket
         |> assign(:unexpected_edits, warnings)
         |> load_coordination(project)}

      _ ->
        {:noreply, socket}
    end
  end

  defp assign_current_project(socket, %{"id" => id}) do
    case Projects.get_project(id) do
      {:ok, project} ->
        {:ok, _pid} = ProjectSupervisor.start_runtime(project)

        if socket.assigns[:subscribed_project_id] != project.id do
          Phoenix.PubSub.subscribe(AgentDesk.PubSub, "project:" <> project.id <> ":sessions")
          Phoenix.PubSub.subscribe(AgentDesk.PubSub, "project:" <> project.id <> ":worktrees")
          Phoenix.PubSub.subscribe(AgentDesk.PubSub, "project:" <> project.id <> ":reviews")
        end

        scope = Scope.for_project(project)
        sessions = Agents.visible_sessions(scope)

        socket
        |> assign(:current_project, project)
        |> assign(:subscribed_project_id, project.id)
        |> assign(:page_title, project.name)
        |> assign(:sessions, sessions)
        |> assign(:live_project_ids, live_project_ids())
        |> load_coordination(project)
        |> select_session(List.first(sessions))

      {:error, :not_found} ->
        socket
        |> put_flash(:error, "Project not found.")
        |> push_patch(to: ~p"/")
    end
  end

  defp assign_current_project(socket, _params) do
    assign(socket, :current_project, nil)
  end

  defp after_project_closed(socket, project_id) do
    socket =
      socket
      |> assign(:confirm_close_project_id, nil)
      |> assign(:recent_projects, Projects.list_recent())
      |> assign(:live_project_ids, live_project_ids())

    case socket.assigns.current_project do
      %Project{id: ^project_id} ->
        socket
        |> assign(:current_project, nil)
        |> push_patch(to: ~p"/")

      _ ->
        socket
    end
  end

  defp live_project_ids do
    Enum.flat_map(Projects.list_recent(), fn project ->
      case Runtime.fetch(project.id) do
        {:ok, _pid} -> [project.id]
        _ -> []
      end
    end)
  end

  defp maybe_restore_last_project(socket) do
    cond do
      socket.assigns.live_action != :index ->
        socket

      socket.assigns.current_project ->
        socket

      true ->
        case Projects.list_open() do
          [%Project{} = project | _] ->
            push_patch(socket, to: ~p"/projects/#{project.id}")

          [] ->
            socket
        end
    end
  end

  defp maybe_replace_current(socket, project) do
    case socket.assigns.current_project do
      %{id: id} when id == project.id -> assign(socket, :current_project, project)
      _ -> socket
    end
  end

  defp load_coordination(socket, project) do
    scope = Scope.for_project(project)
    leases = Manager.list_project(project.id)

    tasks = A2A.list_tasks(scope)

    socket
    |> assign(:agents, A2A.list_agents(scope))
    |> assign(:leases, leases)
    |> assign(:lease_previews, Overlap.previews(leases))
    |> assign(:delegations, A2A.list_delegations(scope))
    |> assign(:tasks, tasks)
    |> assign(:task_deps, dependency_titles(project.id, tasks))
    |> assign(:workflows, Workflows.list(scope))
    |> assign(:messages, A2A.list_messages(scope))
    |> assign(:artifacts, A2A.list_artifacts(scope))
    |> assign(:merge_queue, Reviews.list_open(project))
    |> assign(:roles, AgentDesk.Roles.list(project))
    |> assign(:search_status, AgentDesk.Search.status(project))
    |> assign(:usage, AgentDesk.Usage.summary(project))
    |> load_worktrees(project)
  end

  defp search_results(project, q) do
    case AgentDesk.Search.search(Scope.for_project(project), %{"q" => q}) do
      {:ok, results} -> results
      {:error, _} -> []
    end
  end

  defp load_worktrees(socket, project) do
    trees = Worktrees.list_project(project.id)
    active_id = socket.assigns.active_session_id
    current = Enum.find(trees, &(&1.agent_session_id == active_id))
    diff = bounded_diff(current)

    socket
    |> assign(:worktrees, trees)
    |> assign(:active_worktree, current)
    |> assign(:worktree_diff, diff)
    |> assign(:unexpected_edits, Worktrees.unexpected_main_edits(project))
  end

  defp bounded_diff(nil), do: ""

  defp bounded_diff(worktree) do
    case Git.diff(worktree.path, worktree.base_commit) do
      {:ok, text} -> String.slice(text, 0, 20_000)
      {:error, _} -> ""
    end
  end

  defp publish_active_handoff(socket, summary) do
    project = socket.assigns.current_project
    session_id = socket.assigns.active_session_id

    with true <- is_binary(session_id),
         {:ok, session} <- Agents.get_session(Scope.for_project(project), session_id) do
      _ = Handoffs.publish(Scope.for_agent(project, session), %{summary: summary})
    end

    {:noreply, load_coordination(socket, project)}
  end

  defp decide_delegation(socket, id, action) do
    project = socket.assigns.current_project
    session_id = socket.assigns.active_session_id

    with true <- is_binary(session_id),
         {:ok, session} <- Agents.get_session(Scope.for_project(project), session_id) do
      scope = Scope.for_agent(project, session)
      attrs = %{idempotency_key: Ids.generate(), expected_version: 1, response_reason: "ui"}

      _ =
        case action do
          :accept -> A2A.accept_delegation(scope, id, attrs)
          :reject -> A2A.reject_delegation(scope, id, attrs)
        end
    end

    load_coordination(socket, project)
  end

  defp dependency_titles(project_id, tasks) do
    titles = Map.new(tasks, &{&1.id, &1.title})
    grouped = Enum.group_by(Graph.list_edges(project_id), & &1.task_id)

    Map.new(tasks, fn task ->
      names =
        grouped
        |> Map.get(task.id, [])
        |> Enum.map(&titles[&1.depends_on_id])
        |> Enum.reject(&is_nil/1)

      {task.id, names}
    end)
  end

  defp reviewer_scope(socket) do
    project = socket.assigns.current_project
    session_id = socket.assigns.active_session_id

    with true <- is_binary(session_id),
         {:ok, session} <- Agents.get_session(Scope.for_project(project), session_id) do
      Scope.for_agent(project, session)
    else
      _ -> Scope.for_project(project)
    end
  end

  defp session_settings(params) do
    settings = %{"tab_open" => true, "container" => params["container"] == "true"}

    if params["provider"] == "sdk" do
      Map.merge(settings, %{
        "sdk_executable" => params["sdk_executable"] || "",
        "sdk_args" => params["sdk_args"] || ""
      })
    else
      settings
    end
  end

  defp connect_env_path(%{provider: "remote"} = session) do
    AgentDesk.Providers.MCPInjection.connect_env_path(session)
  end

  defp connect_env_path(_session), do: nil

  defp select_session(socket, nil) do
    socket
    |> assign(:active_session_id, nil)
    |> assign(:active_status, "idle")
    |> assign(:pending_approval, nil)
    |> assign(:connect_path, nil)
    |> stream(:activity, [], reset: true)
  end

  defp select_session(socket, session) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgentDesk.PubSub, "session:" <> session.id)
    end

    socket
    |> assign(:active_session_id, session.id)
    |> assign(:active_status, session.status)
    |> assign(:pending_approval, nil)
    |> assign(:connect_path, connect_env_path(session))
    |> stream(:activity, [], reset: true)
  end

  defp select_session_id(socket, id) do
    case Enum.find(socket.assigns.sessions, &(&1.id == id)) do
      nil -> socket
      session -> select_session(socket, session)
    end
  end

  defp maybe_status(socket, session) do
    if socket.assigns.active_session_id == session.id do
      assign(socket, :active_status, session.status)
    else
      socket
    end
  end

  defp active_session(assigns) do
    Enum.find(assigns.sessions, &(&1.id == assigns.active_session_id))
  end

  defp capabilities(nil), do: nil

  defp capabilities(session) do
    case Providers.adapter(session.provider) do
      {:ok, adapter} -> adapter.capabilities()
      {:error, _} -> nil
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :active, active_session(assigns))
    assigns = assign(assigns, :caps, capabilities(assigns.active))

    ~H"""
    <div class="flex h-screen min-h-0 bg-base-200 text-base-content">
      <aside class="flex w-72 shrink-0 flex-col border-r border-base-300 bg-base-100">
        <div class="flex items-center justify-between gap-2 border-b border-base-300 px-4 py-3">
          <div>
            <p class="text-sm font-semibold tracking-wide">AgentDesk</p>
            <p class="text-xs text-base-content/60">Local multi-agent workspace</p>
          </div>
          <.theme_toggle />
        </div>

        <section class="border-b border-base-300 p-4">
          <.form
            for={@form}
            id="open-project-form"
            phx-change="validate"
            phx-submit="open_project"
            class="space-y-2"
          >
            <label class="text-xs font-medium text-base-content/70" for="project-path">
              Open Git repository
            </label>
            <input
              id="project-path"
              type="text"
              name="path"
              value={@path}
              placeholder="/path/to/repo"
              class="input input-sm input-bordered w-full"
              autocomplete="off"
            />
            <.button type="submit" class="btn btn-primary btn-sm w-full">Open project</.button>
          </.form>
        </section>

        <section class="min-h-0 flex-1 overflow-y-auto p-4">
          <h2 class="mb-2 text-xs font-semibold uppercase tracking-wide text-base-content/60">
            Recent projects
          </h2>
          <ul id="recent-projects" class="space-y-1">
            <li :if={@recent_projects == []} class="text-sm text-base-content/50">
              No projects opened yet.
            </li>
            <li :for={project <- @recent_projects} class="flex items-start gap-1">
              <.link
                patch={~p"/projects/#{project.id}"}
                class={[
                  "min-w-0 flex-1 rounded-lg px-3 py-2 text-sm hover:bg-base-200",
                  @current_project && @current_project.id == project.id && "bg-base-200 font-medium"
                ]}
              >
                <span class="flex items-center gap-2">
                  <span class="block truncate">{project.name}</span>
                  <span
                    :if={project.id in @live_project_ids}
                    class="badge badge-xs badge-success"
                  >
                    live
                  </span>
                </span>
                <span class="block truncate text-xs text-base-content/50">
                  {project.canonical_path}
                </span>
              </.link>
              <div class="flex shrink-0 flex-col gap-1 pt-1">
                <button
                  :if={@confirm_close_project_id == project.id}
                  type="button"
                  id={"confirm-close-#{project.id}"}
                  phx-click="close_project"
                  phx-value-id={project.id}
                  class="btn btn-xs btn-error"
                >
                  Confirm close
                </button>
                <button
                  :if={@confirm_close_project_id == project.id}
                  type="button"
                  phx-click="cancel_close_project"
                  class="btn btn-xs"
                >
                  Cancel
                </button>
                <button
                  :if={@confirm_close_project_id != project.id}
                  type="button"
                  id={"close-project-#{project.id}"}
                  phx-click="confirm_close_project"
                  phx-value-id={project.id}
                  class="btn btn-ghost btn-xs"
                  aria-label={"Close #{project.name}"}
                >
                  Close
                </button>
              </div>
            </li>
          </ul>
        </section>
      </aside>

      <main class="flex min-w-0 flex-1 flex-col">
        <header class="flex items-center justify-between border-b border-base-300 bg-base-100 px-6 py-3">
          <div>
            <h1 class="text-base font-semibold">
              {if @current_project, do: @current_project.name, else: "No project open"}
            </h1>
            <p class="text-xs text-base-content/60">
              {if @current_project,
                do: @current_project.canonical_path,
                else: "Open a Git repository to start concurrent agent sessions."}
            </p>
          </div>
          <div class="flex gap-2 text-xs">
            <span class="badge badge-ghost">Codex</span>
            <span class="badge badge-ghost">Claude</span>
            <span class="badge badge-ghost">Cursor</span>
            <span class="badge badge-ghost">OpenCode</span>
            <span class="badge badge-ghost">SDK</span>
            <span class="badge badge-ghost">Remote</span>
          </div>
        </header>

        <div class="grid min-h-0 flex-1 grid-cols-[1fr_20rem]">
          <section class="flex min-h-0 flex-col">
            <div :if={@current_project} class="border-b border-base-300 bg-base-100 px-4 py-2">
              <form
                id="start-session-form"
                phx-change="session_form"
                phx-submit="start_session"
                class="flex flex-wrap items-end gap-2"
              >
                <label class="text-xs">
                  Provider
                  <select name="provider" class="select select-bordered select-xs ml-1">
                    <option :for={key <- Providers.ui_keys()} value={key} selected={key == @provider}>
                      {key}
                    </option>
                  </select>
                </label>
                <input
                  type="text"
                  name="display_name"
                  value={@display_name}
                  placeholder="Session name"
                  class="input input-bordered input-xs"
                />
                <label class="text-xs">
                  Role
                  <select
                    name="role_id"
                    id="session-role"
                    class="select select-bordered select-xs ml-1"
                  >
                    <option value="">none</option>
                    <option :for={role <- @roles} value={role.id}>{role.name}</option>
                  </select>
                </label>
                <input
                  :if={@provider == "sdk"}
                  type="text"
                  name="sdk_executable"
                  id="sdk-executable"
                  value={@sdk_executable}
                  placeholder="SDK executable"
                  class="input input-bordered input-xs"
                />
                <input
                  :if={@provider == "sdk"}
                  type="text"
                  name="sdk_args"
                  id="sdk-args"
                  value={@sdk_args}
                  placeholder="one arg per line"
                  class="input input-bordered input-xs"
                />
                <.button class="btn btn-primary btn-xs">New session</.button>
                <label class="flex items-center gap-1 text-xs">
                  <input type="checkbox" name="container" value="true" id="container-opt-in" />
                  Containers
                </label>
              </form>
              <form
                id="save-role-form"
                phx-submit="save_role"
                class="mt-2 flex flex-wrap items-end gap-2"
              >
                <input
                  type="text"
                  name="name"
                  placeholder="role name"
                  class="input input-bordered input-xs"
                />
                <input
                  type="text"
                  name="description"
                  placeholder="safe card description"
                  class="input input-bordered input-xs"
                />
                <select name="permission_profile" class="select select-bordered select-xs">
                  <option value="default">default</option>
                  <option value="observer">observer</option>
                  <option value="restricted">restricted</option>
                </select>
                <input
                  type="text"
                  name="prompt"
                  placeholder="session prompt (not published)"
                  class="input input-bordered input-xs w-64"
                />
                <.button class="btn btn-ghost btn-xs">Save role</.button>
              </form>
            </div>

            <div
              id="session-tabs"
              class="flex gap-1 overflow-x-auto border-b border-base-300 px-2 py-1"
            >
              <p :if={@sessions == []} class="px-2 py-1 text-xs text-base-content/50">
                No agent tabs. Starting a session does not close another.
              </p>
              <div :for={session <- @sessions} class="join">
                <button
                  type="button"
                  id={"tab-#{session.id}"}
                  phx-click="select_tab"
                  phx-value-id={session.id}
                  class={[
                    "btn btn-xs join-item",
                    @active_session_id == session.id && "btn-active"
                  ]}
                >
                  {session.display_name}
                  <span :if={session.role} class="ml-1 opacity-70">{session.role}</span>
                  <span class="ml-1 opacity-70">{session.status}</span>
                </button>
                <button
                  type="button"
                  id={"close-tab-#{session.id}"}
                  phx-click="close_tab"
                  phx-value-id={session.id}
                  class="btn btn-xs join-item"
                  title="Close tab without terminating"
                >
                  ×
                </button>
              </div>
            </div>

            <p :if={@active_session_id == nil} class="p-4 text-sm text-base-content/60">
              Open a Git repository, then start Codex, Claude, Cursor, or OpenCode sessions in tabs.
            </p>
            <div
              id="activity-stream"
              phx-update="stream"
              class="min-h-0 flex-1 overflow-y-auto p-4 text-sm"
            >
              <article :for={{dom_id, item} <- @streams.activity} id={dom_id} class="mb-2">
                <p class="text-xs uppercase text-base-content/50">{item.type}</p>
                <p class="whitespace-pre-wrap">{item.text}</p>
              </article>
            </div>

            <div :if={@active} class="border-t border-base-300 bg-base-100 p-3">
              <p :if={@connect_path} id="remote-connect" class="mb-2 break-all text-xs">
                Connect file: {@connect_path}
              </p>
              <div class="mb-2 flex flex-wrap gap-2">
                <button
                  :if={@caps && (@caps.steer_active_turn or @active_status == "working")}
                  type="button"
                  id="interrupt-session"
                  phx-click="interrupt"
                  class="btn btn-warning btn-xs"
                >
                  Interrupt
                </button>
                <button
                  :if={@active_status in ["interrupted", "failed"] && @caps && @caps.resume}
                  type="button"
                  id="resume-session"
                  phx-click="resume_session"
                  phx-value-id={@active.id}
                  class="btn btn-xs"
                >
                  Resume
                </button>
                <button
                  :if={!@confirm_terminate}
                  type="button"
                  id="confirm-terminate"
                  phx-click="confirm_terminate"
                  class="btn btn-error btn-xs"
                >
                  Terminate
                </button>
                <button
                  :if={@confirm_terminate}
                  type="button"
                  id="terminate-session"
                  phx-click="terminate"
                  class="btn btn-error btn-xs"
                >
                  Confirm terminate
                </button>
                <button
                  :if={@confirm_terminate}
                  type="button"
                  phx-click="cancel_terminate"
                  class="btn btn-ghost btn-xs"
                >
                  Cancel
                </button>
              </div>
              <form id="prompt-composer" phx-submit="send_prompt" class="flex gap-2">
                <textarea
                  name="prompt"
                  class="textarea textarea-bordered textarea-sm min-h-16 flex-1"
                  placeholder="Send a prompt"
                >{@prompt}</textarea>
                <.button class="btn btn-primary btn-sm">Send</.button>
              </form>
            </div>
          </section>

          <aside class="border-l border-base-300 bg-base-100 p-4">
            <h2 class="mb-3 text-xs font-semibold uppercase tracking-wide text-base-content/60">
              Context
            </h2>
            <dl class="space-y-3 text-sm">
              <div>
                <dt class="text-xs text-base-content/50">Runtime</dt>
                <dd>{if @current_project, do: "Project runtime started", else: "Idle"}</dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Session</dt>
                <dd id="session-status">
                  {if @active, do: "#{@active.display_name} · #{@active_status}", else: "None"}
                </dd>
              </div>
              <div :if={@pending_approval}>
                <dt class="text-xs text-base-content/50">Approval</dt>
                <dd id="approval-card" class="space-y-2 rounded-lg bg-warning/10 p-2">
                  <p>
                    {@pending_approval.payload["action"]} — {@pending_approval.payload["summary"]}
                  </p>
                  <button
                    type="button"
                    id="approve-request"
                    phx-click="approve"
                    phx-value-id={@pending_approval.payload["request_id"]}
                    class="btn btn-success btn-xs"
                  >
                    Allow
                  </button>
                  <button
                    type="button"
                    id="deny-request"
                    phx-click="deny"
                    phx-value-id={@pending_approval.payload["request_id"]}
                    class="btn btn-error btn-xs"
                  >
                    Deny
                  </button>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Agents</dt>
                <dd id="agents-directory">
                  <p :if={@agents == []} class="text-base-content/50">No Agent Cards yet.</p>
                  <p :for={card <- @agents}>{card.name} · {card.availability}</p>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Delegations</dt>
                <dd id="delegation-inbox">
                  <p :if={@delegations == []} class="text-base-content/50">None</p>
                  <div :for={delegation <- @delegations} class="mb-1">
                    <span>{delegation.status}</span>
                    <button
                      :if={delegation.status == "proposed"}
                      type="button"
                      phx-click="accept_delegation"
                      phx-value-id={delegation.id}
                      class="btn btn-xs"
                    >
                      Accept
                    </button>
                    <button
                      :if={delegation.status == "proposed"}
                      type="button"
                      phx-click="reject_delegation"
                      phx-value-id={delegation.id}
                      class="btn btn-xs"
                    >
                      Reject
                    </button>
                  </div>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Leases</dt>
                <dd id="resource-leases">
                  <p :if={@lease_previews == []} class="text-base-content/50">No active leases.</p>
                  <p :for={{lease, overlaps} <- @lease_previews} id={"lease-#{lease.id}"}>
                    {lease.mode} {lease.resource_type}:{lease.resource_key}
                    <span :if={match?([_ | _], overlaps)} class="text-warning">
                      overlaps {Enum.join(overlaps, ", ")}
                    </span>
                  </p>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Tasks</dt>
                <dd id="task-conversation">
                  <p :if={@tasks == []} class="text-base-content/50">None</p>
                  <div :for={task <- @tasks} id={"task-#{task.id}"} class="mb-2">
                    <p>
                      {task.title} · {task.status}
                      <span :if={match?([_ | _], Map.get(@task_deps, task.id, []))} class="text-xs">
                        waits on {Enum.join(Map.get(@task_deps, task.id, []), ", ")}
                      </span>
                    </p>
                    <button
                      :if={task.status not in ["completed", "failed", "cancelled", "rejected"]}
                      type="button"
                      phx-click="complete_task"
                      phx-value-id={task.id}
                      class="btn btn-xs"
                    >
                      Complete
                    </button>
                  </div>
                  <form id="create-task" phx-submit="create_task" class="mt-2 space-y-1">
                    <input
                      name="title"
                      class="input input-bordered input-xs w-full"
                      placeholder="New task"
                    />
                    <.button class="btn btn-xs">Add task</.button>
                  </form>
                  <form
                    :if={match?([_, _ | _], @tasks)}
                    id="add-task-dependency"
                    phx-submit="add_task_dependency"
                    class="mt-2 space-y-1"
                  >
                    <select name="task_id" class="select select-bordered select-xs w-full">
                      <option :for={task <- @tasks} value={task.id}>{task.title}</option>
                    </select>
                    <select name="depends_on_id" class="select select-bordered select-xs w-full">
                      <option :for={task <- @tasks} value={task.id}>{task.title}</option>
                    </select>
                    <.button class="btn btn-xs">Wait on</.button>
                  </form>
                  <form id="run-workflow" phx-submit="run_workflow" class="mt-2 space-y-1">
                    <input
                      name="name"
                      class="input input-bordered input-xs w-full"
                      placeholder="Workflow name"
                    />
                    <textarea
                      name="steps"
                      class="textarea textarea-bordered textarea-xs w-full"
                      placeholder="Design\nImplement\nReview"
                    />
                    <.button class="btn btn-xs">Save and run workflow</.button>
                  </form>
                  <div :if={@workflows != []} id="workflow-list" class="mt-2 space-y-1">
                    <button
                      :for={workflow <- @workflows}
                      type="button"
                      phx-click="instantiate_workflow"
                      phx-value-id={workflow.id}
                      class="btn btn-xs btn-ghost"
                    >
                      Run {workflow.name}
                    </button>
                  </div>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Messages</dt>
                <dd id="message-panel">
                  <p :if={@messages == []} class="text-base-content/50">None</p>
                  <p :for={message <- @messages}>{message.scope} · {message.body}</p>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Artifacts</dt>
                <dd id="artifact-panel">
                  <p :if={@artifacts == []} class="text-base-content/50">None</p>
                  <p :for={artifact <- @artifacts}>{artifact.name} · {artifact.state}</p>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Merge queue</dt>
                <dd id="merge-queue">
                  <p :if={@merge_queue == []} class="text-base-content/50">None</p>
                  <div :for={item <- @merge_queue} id={"merge-item-#{item.id}"} class="mb-2">
                    <p>
                      {item.status} · {item.summary}
                    </p>
                    <p class="text-xs">
                      {item.branch_name} → {item.target_ref} · policy {item.policy_status}
                    </p>
                    <p
                      :if={item.policy_status == "failed"}
                      class="text-warning text-xs"
                    >
                      Checks blocked merge
                    </p>
                    <button
                      :if={item.status == "queued"}
                      type="button"
                      phx-click="accept_queue_item"
                      phx-value-artifact_id={item.artifact_id}
                      class="btn btn-xs"
                    >
                      Accept
                    </button>
                    <button
                      :if={item.status in ["queued", "accepted"]}
                      type="button"
                      phx-click="reject_queue_item"
                      phx-value-artifact_id={item.artifact_id}
                      class="btn btn-xs"
                    >
                      Reject
                    </button>
                    <button
                      :if={
                        item.status == "accepted" and item.policy_status == "passed" and
                          @confirm_merge_id != item.id
                      }
                      type="button"
                      id={"confirm-merge-#{item.id}"}
                      phx-click="confirm_merge"
                      phx-value-id={item.id}
                      class="btn btn-xs"
                    >
                      Merge
                    </button>
                    <button
                      :if={@confirm_merge_id == item.id}
                      type="button"
                      id={"merge-#{item.id}"}
                      phx-click="merge_queue_item"
                      phx-value-id={item.id}
                      class="btn btn-xs btn-error"
                    >
                      Confirm merge
                    </button>
                    <button
                      :if={@confirm_merge_id == item.id}
                      type="button"
                      phx-click="cancel_merge"
                      class="btn btn-xs"
                    >
                      Cancel
                    </button>
                  </div>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Worktree</dt>
                <dd id="worktree-panel">
                  <p :if={@unexpected_edits != []} id="unexpected-edits" class="text-warning">
                    Unexpected main-tree edits: {length(@unexpected_edits)}
                  </p>
                  <p :if={!@active_worktree} class="text-base-content/50">No isolated worktree.</p>
                  <div :if={@active_worktree}>
                    <p>{@active_worktree.branch_name} · {@active_worktree.status}</p>
                    <pre id="worktree-diff" class="max-h-32 overflow-auto text-xs">{@worktree_diff}</pre>
                    <form id="commit-worktree" phx-submit="commit_worktree" class="mt-2 space-y-1">
                      <input
                        name="message"
                        class="input input-bordered input-xs w-full"
                        placeholder="Commit message"
                      />
                      <.button class="btn btn-xs">Commit</.button>
                    </form>
                    <form id="publish-handoff" phx-submit="publish_handoff" class="mt-1 space-y-1">
                      <input
                        name="summary"
                        class="input input-bordered input-xs w-full"
                        placeholder="Handoff summary"
                      />
                      <.button class="btn btn-xs">Handoff</.button>
                    </form>
                    <button
                      :if={!@confirm_cleanup}
                      type="button"
                      id="cleanup-worktree"
                      phx-click="cleanup_worktree"
                      class="btn btn-ghost btn-xs mt-1"
                    >
                      Cleanup worktree
                    </button>
                    <button
                      :if={@confirm_cleanup}
                      type="button"
                      id="confirm-cleanup-worktree"
                      phx-click="confirm_cleanup"
                      class="btn btn-error btn-xs mt-1"
                    >
                      Confirm cleanup
                    </button>
                  </div>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Usage</dt>
                <dd id="usage-panel">
                  <p>
                    {@usage["input_tokens"]} in / {@usage["output_tokens"]} out / {@usage[
                      "total_tokens"
                    ]} total
                  </p>
                  <p class="text-xs">{@usage["cost_cents"]} cents</p>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Search</dt>
                <dd id="search-panel">
                  <p id="search-status">
                    {@search_status.status} · {@search_status.adapter}
                  </p>
                  <form id="project-search" phx-submit="search_project" class="mt-1 space-y-1">
                    <input
                      name="q"
                      value={@search_query}
                      class="input input-bordered input-xs w-full"
                      placeholder="Search project"
                      aria-label="Search project"
                    />
                    <.button class="btn btn-xs">Search</.button>
                  </form>
                  <button
                    type="button"
                    id="rebuild-search"
                    phx-click="rebuild_search"
                    class="btn btn-ghost btn-xs mt-1"
                    aria-label="Rebuild search index"
                  >
                    Rebuild index
                  </button>
                  <p :if={@search_results == []} class="text-base-content/50">No search results.</p>
                  <p :for={hit <- @search_results} class="text-xs">
                    {hit.title} · {hit.source}
                  </p>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">Team sync</dt>
                <dd id="sync-panel">
                  <button
                    type="button"
                    id="export-sync"
                    phx-click="export_sync"
                    class="btn btn-ghost btn-xs"
                    aria-label="Export sync bundle"
                  >
                    Export bundle
                  </button>
                  <p :if={@sync_path} id="sync-path" class="break-all text-xs">{@sync_path}</p>
                  <form id="import-sync" phx-submit="import_sync" class="mt-1 space-y-1">
                    <input
                      name="path"
                      class="input input-bordered input-xs w-full"
                      placeholder="Path to bundle.json"
                      aria-label="Sync bundle path"
                    />
                    <.button class="btn btn-xs">Import bundle</.button>
                  </form>
                </dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">A2A</dt>
                <dd>
                  Agent Cards, delegations, durable messages, leases, and artifacts persist in SQLite.
                </dd>
              </div>
            </dl>
          </aside>
        </div>
      </main>
    </div>

    <Layouts.flash_group flash={@flash} />
    """
  end

  defp theme_toggle(assigns) do
    ~H"""
    <div class="flex items-center justify-between gap-1">
      <button
        type="button"
        class="btn btn-ghost btn-xs"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        aria-label="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>
      <button
        type="button"
        class="btn btn-ghost btn-xs"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        aria-label="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
