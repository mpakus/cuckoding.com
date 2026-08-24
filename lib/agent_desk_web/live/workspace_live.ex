defmodule AgentDeskWeb.WorkspaceLive do
  @moduledoc """
  Desktop application shell: project sidebar, agent tabs, activity, and approvals.
  """

  use AgentDeskWeb, :live_view
  use ExTauri.LiveView

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Graph
  alias AgentDesk.A2A.Orchestration
  alias AgentDesk.A2A.Workflows
  alias AgentDesk.Agents
  alias AgentDesk.Analytics
  alias AgentDesk.Branding
  alias AgentDesk.Git
  alias AgentDesk.Ids
  alias AgentDesk.Isolation
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Project
  alias AgentDesk.Projects.Runtime
  alias AgentDesk.Projects.Supervisor, as: ProjectSupervisor
  alias AgentDesk.Providers
  alias AgentDesk.Providers.AcpRegistry
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Providers.Transcript
  alias AgentDesk.Repo
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Resources.Overlap
  alias AgentDesk.Reviews
  alias AgentDesk.Scope
  alias AgentDesk.Worktrees
  alias AgentDesk.Worktrees.Handoffs

  import AgentDeskWeb.WorkspaceView

  @default_shortcuts %{
    "send" => "Meta+Enter",
    "interrupt" => "Meta+.",
    "new_session" => "Meta+Shift+Enter",
    "next_tab" => "Meta+Shift+]",
    "prev_tab" => "Meta+Shift+[",
    "focus_composer" => "Meta+L",
    "search" => "Meta+K",
    "load_older" => "Meta+["
  }

  @recent_limit 12

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgentDesk.PubSub, "projects")
      send(self(), :restore_last_project)
      send(self(), :probe_providers)
    end

    {:ok,
     socket
     |> assign(:page_title, Branding.product_name())
     |> assign(:current_project, nil)
     |> assign(:recent_projects, [])
     |> assign(:live_project_ids, [])
     |> assign(:confirm_close_project_id, nil)
     |> assign(:failed_recent_id, nil)
     |> assign(:confirm_forget_project_id, nil)
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
     |> assign(:provider, "codex")
     |> assign(:provider_status, %{})
     |> assign(:confirm_terminate, false)
     |> assign(:allow_force_terminate, false)
     |> assign(:agents, [])
     |> assign(:agent_filter, "all")
     |> assign(:leases, [])
     |> assign(:lease_previews, [])
     |> assign(:inbox, [])
     |> assign(:deliveries, [])
     |> assign(:unread, %{})
     |> assign(:announce, "")
     |> assign(:activity_mode, "cards")
     |> assign(:activity_limit, 200)
     |> assign(:activity_older?, false)
     |> assign(:activity_tail, nil)
     |> assign(:type_scale, "md")
     |> assign(:shortcuts, @default_shortcuts)
     |> assign(:onboard_step, 1)
     |> assign(:onboard_complete, false)
     |> assign(:delegation_depth, 3)
     |> assign(:xerj_enabled, false)
     |> assign(:memories, [])
     |> assign(:confirm_revoke_lease_id, nil)
     |> assign(:delegations, [])
     |> assign(:tasks, [])
     |> assign(:task_deps, %{})
     |> assign(:workflows, [])
     |> assign(:messages, [])
     |> assign(:artifacts, [])
     |> assign(:merge_queue, [])
     |> assign(:confirm_merge_id, nil)
     |> assign(:selected_handoff_id, nil)
     |> assign(:worktrees, [])
     |> assign(:active_worktree, nil)
     |> assign(:worktree_diff, "")
     |> assign(:unexpected_edits, [])
     |> assign(:confirm_cleanup, false)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:sync_path, nil)
     |> assign(:workspace_view, "workspace")
     |> assign(:registry_query, "")
     |> assign(:registry_filter, "all")
     |> assign(:registry_agents, [])
     |> assign(:analytics, empty_analytics())
     |> allow_upload(:attachments,
       accept: :any,
       max_entries: 8,
       max_file_size: 20_000_000,
       auto_upload: true
     )
     |> assign(:search_status, %{
       adapter: "Disabled",
       health: {:error, :unavailable},
       status: "unavailable",
       last_indexed_at: nil,
       error: nil
     })
     |> assign_registry()
     |> stream(:activity, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if connected?(socket) do
        socket
        |> assign_recents()
        |> assign_current_project(params)
      else
        assign_project_preview(socket, params)
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("pick_project_folder", _params, socket) do
    {:noreply,
     ExTauri.Dialog.open(
       socket,
       [
         title: "Choose a Git repository",
         directory: true,
         default_path: picker_start_path(socket)
       ],
       &handle_picked_repo/2
     )}
  end

  def handle_event("open_project", %{"path" => path}, socket) when is_binary(path) do
    {:noreply, open_selected_project(socket, path, :picker)}
  end

  def handle_event("open_recent", %{"id" => id}, socket) when is_binary(id) do
    {:noreply, reopen_recent_project(socket, id, :open)}
  end

  def handle_event("check_recent", %{"id" => id}, socket) when is_binary(id) do
    {:noreply, reopen_recent_project(socket, id, :check)}
  end

  def handle_event("confirm_forget_recent", %{"id" => id}, socket) when is_binary(id) do
    {:noreply, assign(socket, :confirm_forget_project_id, id)}
  end

  def handle_event("cancel_forget_recent", _params, socket) do
    {:noreply, assign(socket, :confirm_forget_project_id, nil)}
  end

  def handle_event("forget_recent", %{"id" => id}, socket) when is_binary(id) do
    case Projects.forget_recent(id) do
      :ok ->
        {:noreply, after_recent_forgotten(socket, id)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not remove that project from recents.")}
    end
  end

  def handle_event("picker_failed", _params, socket) do
    {:noreply, put_flash(socket, :error, "Could not open the macOS folder picker.")}
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

  def handle_event("set_view", %{"view" => "analytics"}, socket) do
    handle_event("set_view", %{"view" => "dashboard"}, socket)
  end

  def handle_event("set_view", %{"view" => view}, socket)
      when view in ~w(workspace registry dashboard new handoff) do
    socket = assign(socket, :workspace_view, view)

    socket =
      case view do
        "registry" -> assign_registry(socket)
        "dashboard" -> assign_analytics(socket)
        _ -> socket
      end

    {:noreply, socket}
  end

  def handle_event("review_handoff", params, socket) do
    id = blank_to_nil(params["id"]) || default_handoff_id(socket.assigns.merge_queue)

    {:noreply, assign(socket, workspace_view: "handoff", selected_handoff_id: id)}
  end

  def handle_event("filter_agents", %{"filter" => filter}, socket) when is_binary(filter) do
    allowed = ["all" | agent_filter_keys(socket.assigns.agents)]
    {:noreply, assign(socket, :agent_filter, if(filter in allowed, do: filter, else: "all"))}
  end

  def handle_event("registry_search", params, socket) do
    query = params["q"] || params["query"] || ""

    {:noreply,
     socket
     |> assign(:registry_query, query)
     |> assign_registry()}
  end

  def handle_event("registry_filter", %{"filter" => filter}, socket) do
    selected = if filter in ~w(all installed not_installed), do: filter, else: "all"

    {:noreply,
     socket
     |> assign(:registry_filter, selected)
     |> assign_registry()}
  end

  def handle_event("registry_refresh", _params, socket) do
    _ = AcpRegistry.refresh()
    {:noreply, assign_registry(socket)}
  end

  def handle_event("registry_install", %{"id" => id}, socket) do
    case AcpRegistry.install(id) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Installed. Start a thread with Use.")
         |> assign_registry()}

      {:error, :unsupported_distribution} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This agent needs a CLI on PATH. Install the vendor CLI, then try again."
         )}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Could not install that agent.")}
    end
  end

  def handle_event("registry_remove", %{"id" => id}, socket) do
    case AcpRegistry.remove(id) do
      {:ok, _} -> {:noreply, assign_registry(socket)}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Could not remove that agent.")}
    end
  end

  def handle_event("shortcut", %{"action" => action}, socket) do
    {:noreply, apply_shortcut(socket, action)}
  end

  def handle_event("save_shortcuts", params, socket) do
    shortcuts =
      @default_shortcuts
      |> Map.keys()
      |> Map.new(fn key -> {key, params[key] || @default_shortcuts[key]} end)

    socket = assign(socket, :shortcuts, shortcuts)

    socket =
      case socket.assigns.current_project do
        %Project{} = project ->
          case Projects.put_settings(project, %{"shortcuts" => shortcuts}) do
            {:ok, updated} -> assign(socket, :current_project, updated)
            _ -> socket
          end

        _ ->
          socket
      end

    {:noreply, socket}
  end

  def handle_event("onboard_next", _params, socket) do
    {:noreply, persist_onboard(socket, min(10, socket.assigns.onboard_step + 1))}
  end

  def handle_event("onboard_complete", _params, socket) do
    {:noreply,
     socket
     |> assign(:workspace_view, "new")
     |> persist_onboard(10, complete: true)}
  end

  def handle_event("enable_xerj", _params, socket) do
    AgentDesk.Search.put_xerj(true)

    socket =
      socket
      |> assign(:xerj_enabled, true)
      |> persist_project_setting("xerj", true)
      |> then(fn sock ->
        case sock.assigns.current_project do
          %Project{} = project ->
            _ = AgentDesk.Search.rebuild(project)
            assign(sock, :search_status, AgentDesk.Search.status(project))

          _ ->
            sock
        end
      end)

    {:noreply, socket}
  end

  def handle_event("set_delegation_policy", %{"depth" => depth}, socket) do
    int =
      case Integer.parse(to_string(depth)) do
        {value, _} when value in 1..8 -> value
        _ -> 3
      end

    a2a = %{"max_delegation_depth" => int, "max_delegation_fan_out" => 4}

    {:noreply,
     socket
     |> assign(:delegation_depth, int)
     |> persist_project_setting("a2a", a2a)
     |> put_flash(:info, "Delegation depth set to #{int}.")}
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

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Providers.start_error_message(reason))}
    end
  end

  def handle_event("registry_use", %{"id" => id}, socket) do
    project = socket.assigns.current_project

    with {:ok, attrs} <- AcpRegistry.session_attrs(id),
         {:ok, session} <- Providers.start_session(Scope.for_project(project), attrs) do
      {:noreply,
       socket
       |> assign(:workspace_view, "workspace")
       |> assign(:sessions, Agents.visible_sessions(Scope.for_project(project)))
       |> select_session(session)
       |> load_coordination(project)
       |> put_flash(:info, "Started #{session.display_name}")}
    else
      {:error, :not_installed} ->
        {:noreply, put_flash(socket, :error, "Install that agent first.")}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, Providers.start_error_message(reason))}
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
    socket = select_session_id(socket, id)

    socket =
      case socket.assigns.current_project do
        %Project{} = project -> load_coordination(socket, project)
        _ -> socket
      end

    {:noreply, socket}
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

  def handle_event("validate_prompt", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_attachment", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :attachments, ref)}
  end

  def handle_event("send_prompt", params, socket) do
    prompt = params["prompt"] || ""
    {_done, in_progress} = uploaded_entries(socket, :attachments)

    cond do
      in_progress != [] ->
        {:noreply, put_flash(socket, :error, "Wait for attachments to finish uploading.")}

      true ->
        dispatch_prompt(socket, prompt)
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

    {:noreply, assign(socket, confirm_terminate: false, allow_force_terminate: false)}
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

  def handle_event("retry_session", _params, socket) do
    session = socket.assigns.active

    cond do
      is_nil(session) ->
        {:noreply, socket}

      socket.assigns.caps && socket.assigns.caps.resume ->
        handle_event("resume_session", %{"id" => session.id}, socket)

      true ->
        {:noreply,
         socket
         |> put_flash(:info, "Start a new session from the toolbar to retry.")
         |> announce("Retry from a new session")}
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

  def handle_event("set_activity_mode", %{"mode" => mode}, socket)
      when mode in ~w(cards raw) do
    {:noreply, assign(socket, :activity_mode, mode)}
  end

  def handle_event("set_type_scale", %{"scale" => scale}, socket)
      when scale in ~w(sm md lg) do
    {:noreply, assign(socket, :type_scale, scale)}
  end

  def handle_event("load_older_activity", _params, socket) do
    {:noreply, load_more_activity(socket)}
  end

  def handle_event("announce_handoff", _params, socket) do
    {:noreply,
     socket
     |> assign(:workspace_view, "handoff")
     |> assign(:selected_handoff_id, default_handoff_id(socket.assigns.merge_queue))
     |> announce("Review the handoff")}
  end

  def handle_event("message_agent", %{"id" => agent_id}, socket) do
    {:noreply, peer_action(socket, agent_id, :message)}
  end

  def handle_event("delegate_agent", %{"id" => agent_id}, socket) do
    {:noreply, peer_action(socket, agent_id, :delegate)}
  end

  def handle_event("request_review", %{"id" => agent_id}, socket) do
    {:noreply, peer_action(socket, agent_id, :review)}
  end

  def handle_event("lease_message", %{"id" => id}, socket) do
    {:noreply, lease_owner_message(socket, id, "Can we coordinate on this resource?")}
  end

  def handle_event("lease_wait", _params, socket) do
    {:noreply,
     socket
     |> put_flash(
       :info,
       "Wait until the lease expires, then retry. Cuckoding never takes a lease silently."
     )
     |> announce("Wait for the lease to expire")}
  end

  def handle_event("lease_other_task", _params, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Pick another task in the Tasks list while this lease is held.")
     |> announce("Choose another task")}
  end

  def handle_event("request_lease_release", %{"id" => id}, socket) do
    {:noreply, lease_owner_message(socket, id, "Please release this resource when you can.")}
  end

  def handle_event("confirm_revoke_lease", %{"id" => id}, socket) do
    {:noreply, assign(socket, :confirm_revoke_lease_id, id)}
  end

  def handle_event("cancel_revoke_lease", _params, socket) do
    {:noreply, assign(socket, :confirm_revoke_lease_id, nil)}
  end

  def handle_event("revoke_lease", %{"id" => id}, socket) do
    project = socket.assigns.current_project

    socket =
      case Manager.revoke(Scope.for_project(project), id) do
        {:ok, _} ->
          socket
          |> assign(:confirm_revoke_lease_id, nil)
          |> put_flash(:info, "Lease revoked.")
          |> announce("Lease revoked")

        {:error, _} ->
          put_flash(socket, :error, "Could not revoke that lease.")
      end

    {:noreply, load_coordination(socket, project)}
  end

  def handle_event("revoke_delegation", %{"id" => id}, socket) do
    {:noreply, mutate_delegation(socket, id, :revoke)}
  end

  def handle_event(
        "redirect_delegation",
        %{"delegation_id" => id, "to_agent_id" => to_id},
        socket
      ) do
    {:noreply, mutate_delegation(socket, id, :redirect, to_id)}
  end

  def handle_event("forget_memory", %{"namespace" => namespace, "id" => id}, socket) do
    project = socket.assigns.current_project
    _ = AgentDesk.Search.forget(Scope.for_project(project), namespace, id)
    _ = forget_sql_memory(project.id, id)

    {:noreply,
     socket
     |> assign(:search_results, search_results(project, socket.assigns.search_query))
     |> assign(:memories, list_memories(project))
     |> put_flash(:info, "Forgot that memory.")}
  end

  def handle_event("accept_delegation", %{"id" => id}, socket) do
    {:noreply, decide_delegation(socket, id, :accept)}
  end

  def handle_event("reject_delegation", params, socket) do
    id = params["delegation_id"] || params["id"]
    reason = params["reason"] || "ui"
    {:noreply, decide_delegation(socket, id, :reject, reason)}
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

  def handle_event("split_work", params, socket) do
    project = socket.assigns.current_project
    scope = reviewer_scope(socket)
    lanes = params |> Map.get("lanes", []) |> List.wrap()

    socket =
      case Orchestration.start_crew(scope, %{
             goal: params["goal"],
             lead_session_id: blank_to_nil(params["lead_session_id"]),
             provider: blank_to_nil(params["provider"]),
             lanes: lanes,
             spawn: true
           }) do
        {:ok, result} ->
          put_flash(socket, :info, "Split work into #{length(result["lanes"])} specialist tasks.")

        {:error, :invalid_goal} ->
          put_flash(socket, :error, "Describe the work to split.")

        {:error, {:missing_agent, role}} ->
          put_flash(socket, :error, "No #{role} agent. Pick a provider to start one.")

        {:error, reason} ->
          put_flash(socket, :error, Providers.start_error_message(reason))
      end

    {:noreply, load_coordination(socket, project)}
  end

  def handle_event("create_task", params, socket) do
    project = socket.assigns.current_project
    scope = reviewer_scope(socket)
    title = params["title"]
    skills = csv_list(params["skills"])
    files = csv_list(params["files"])

    recipient_id =
      blank_to_nil(params["recipient_id"]) || auto_recipient_id(socket, params)

    reviewer_id = blank_to_nil(params["reviewer_id"])
    checks = csv_list(params["checks"])
    isolated? = params["isolated"] != "false"
    permission = params["permission_profile"] || "default"
    role_id = blank_to_nil(params["role_id"])
    depth = blank_to_nil(params["delegation_depth"])

    socket =
      with {:ok, context} <- A2A.ensure_working_context(scope),
           {:ok, task} <-
             A2A.create_task(scope, context, %{
               title: title,
               metadata: %{
                 "skills" => skills,
                 "required_checks" => checks,
                 "reviewer_id" => reviewer_id,
                 "provider" => params["provider"],
                 "role_id" => role_id,
                 "permission_profile" => permission,
                 "isolated" => isolated?,
                 "delegation_depth" => depth
               }
             }) do
        _ = maybe_claim_task_files(scope, files, title)
        _ = maybe_propose_task(scope, task, recipient_id, "delegate")
        _ = maybe_propose_task(scope, task, reviewer_id, "review")
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
            {:ok, _} ->
              socket

            {:error, :blocked_by_dependencies} ->
              put_flash(socket, :error, "That task is still waiting on dependencies.")

            {:error, _} ->
              put_flash(socket, :error, "Could not complete that task.")
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

  def handle_info(:probe_providers, socket) do
    {:noreply, assign(socket, :provider_status, probe_providers())}
  end

  def handle_info({:project_opened, project}, socket) do
    {:noreply,
     socket
     |> assign_recents()
     |> maybe_replace_current(project)}
  end

  def handle_info({:project_closed, project_id}, socket) do
    {:noreply, after_project_closed(socket, project_id)}
  end

  def handle_info({:project_forgotten, project_id}, socket) do
    {:noreply, refresh_after_forgotten(socket, project_id)}
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
        events
        |> Enum.reduce(socket, &append_activity/2)
        |> maybe_schedule_force(status)
        |> assign(:active_status, status)
        |> assign(:pending_approval, approval)
        |> announce_activity(status, approval)

      {:noreply, socket}
    else
      unread = Map.update(socket.assigns.unread, session_id, 1, &(&1 + 1))

      {:noreply,
       socket
       |> assign(:unread, unread)
       |> announce_background(events, approval)}
    end
  end

  def handle_info(:allow_force_terminate, socket) do
    if socket.assigns.active_status == "terminating" do
      {:noreply, assign(socket, :allow_force_terminate, true)}
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
        |> assign_recents()
        |> apply_project_prefs(project)
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

  defp assign_project_preview(socket, %{"id" => id}) do
    case Projects.get_project(id) do
      {:ok, project} -> assign(socket, :current_project, project)
      {:error, :not_found} -> assign(socket, :current_project, nil)
    end
  end

  defp assign_project_preview(socket, _params) do
    case Projects.list_open() do
      [%Project{} = project | _] -> assign(socket, :current_project, project)
      _ -> assign(socket, :current_project, nil)
    end
  end

  defp after_project_closed(socket, project_id) do
    socket =
      socket
      |> assign(:confirm_close_project_id, nil)
      |> assign_recents()

    case socket.assigns.current_project do
      %Project{id: ^project_id} ->
        socket
        |> assign(:current_project, nil)
        |> push_patch(to: ~p"/")

      _ ->
        socket
    end
  end

  defp after_recent_forgotten(socket, project_id) do
    name =
      Enum.find_value(socket.assigns.recent_projects, fn project ->
        if project.id == project_id, do: project.name
      end)

    socket
    |> refresh_after_forgotten(project_id)
    |> put_flash(:info, forget_flash(name))
  end

  defp refresh_after_forgotten(socket, project_id) do
    socket =
      socket
      |> assign(:confirm_forget_project_id, nil)
      |> assign(:failed_recent_id, nil)
      |> assign_recents()

    case socket.assigns.current_project do
      %Project{id: ^project_id} ->
        socket
        |> assign(:current_project, nil)
        |> push_patch(to: ~p"/")

      _ ->
        socket
    end
  end

  defp forget_flash(name) when is_binary(name), do: "Removed #{name} from recents."
  defp forget_flash(_name), do: "Removed that project from recents."

  defp assign_recents(socket) do
    recents = Projects.list_recent(@recent_limit)

    live_ids =
      Enum.flat_map(recents, fn project ->
        case Runtime.fetch(project.id) do
          {:ok, _pid} -> [project.id]
          _ -> []
        end
      end)

    socket
    |> assign(:recent_projects, recents)
    |> assign(:live_project_ids, live_ids)
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
    |> assign(
      :delegations,
      scope |> A2A.list_delegations() |> Repo.preload([:task, :from_agent, :to_agent])
    )
    |> assign(:tasks, tasks)
    |> assign(:task_deps, dependency_titles(project.id, tasks))
    |> assign(:workflows, Workflows.list(scope))
    |> assign(:messages, A2A.list_messages(scope))
    |> assign(:inbox, session_inbox(scope, socket.assigns.active_session_id))
    |> assign(:deliveries, A2A.list_deliveries(scope))
    |> assign(:artifacts, A2A.list_artifacts(scope))
    |> assign(:merge_queue, Reviews.list_open(project))
    |> assign(:roles, AgentDesk.Roles.list(project))
    |> assign(:search_status, AgentDesk.Search.status(project))
    |> assign(:usage, AgentDesk.Usage.summary(project))
    |> assign(:memories, list_memories(project))
    |> assign_analytics()
    |> assign_registry()
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

  defp assign_registry(socket) do
    query = socket.assigns[:registry_query] || ""
    filter = socket.assigns[:registry_filter] || "all"
    assign(socket, :registry_agents, AcpRegistry.list(query, filter))
  end

  defp assign_analytics(socket) do
    case socket.assigns.current_project do
      %Project{} = project -> assign(socket, :analytics, Analytics.report(project))
      _ -> assign(socket, :analytics, empty_analytics())
    end
  end

  defp empty_analytics do
    %{
      sqlite: %{path: nil, bytes: 0, tables: []},
      memory: %{namespaces: [], total: 0, bytes: 0},
      runtime: %{
        total: 0,
        processes: 0,
        ets: 0,
        atom: 0,
        binary: 0,
        process_count: 0
      },
      xerj: %{
        adapter: "Disabled",
        health: "unavailable",
        status: "unavailable",
        last_indexed_at: nil,
        error: nil,
        data_dir: nil,
        data_present: false
      },
      exchange: %{
        messages: [],
        scopes: [],
        artifacts: [],
        events: [],
        usage: %{"total_tokens" => 0, "cost_cents" => 0},
        sessions: 0,
        pending_deliveries: 0
      }
    }
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

  defp decide_delegation(socket, id, action, reason \\ "ui") do
    project = socket.assigns.current_project
    session_id = socket.assigns.active_session_id

    with true <- is_binary(session_id),
         {:ok, session} <- Agents.get_session(Scope.for_project(project), session_id) do
      scope = Scope.for_agent(project, session)

      attrs = %{
        idempotency_key: Ids.generate(),
        expected_version: 1,
        response_reason: reason
      }

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
    settings = %{
      "tab_open" => true,
      "container" => params["container"] == "true",
      "shared" => params["shared"] == "true"
    }

    if params["provider"] == "sdk" do
      Map.merge(settings, %{
        "sdk_executable" => params["sdk_executable"] || "",
        "sdk_args" => params["sdk_args"] || ""
      })
    else
      settings
    end
  end

  defp picker_start_path(socket) do
    cond do
      match?(%Project{}, socket.assigns.current_project) ->
        socket.assigns.current_project.canonical_path

      match?([%Project{} | _], socket.assigns.recent_projects) ->
        hd(socket.assigns.recent_projects).canonical_path

      true ->
        System.user_home()
    end
  end

  defp handle_picked_repo({:ok, %{"path" => path}}, socket)
       when is_binary(path) and path != "" do
    open_selected_project(socket, path, :picker)
  end

  defp handle_picked_repo({:ok, %{"path" => [path | _]}}, socket)
       when is_binary(path) and path != "" do
    handle_picked_repo({:ok, %{"path" => path}}, socket)
  end

  defp handle_picked_repo({:ok, _payload}, socket), do: socket

  defp handle_picked_repo({:error, _reason}, socket) do
    put_flash(
      socket,
      :error,
      "Folder picker needs the Cuckoding app. Use Choose folder… there, or open a recent project."
    )
  end

  defp reopen_recent_project(socket, id, context) do
    case Projects.reopen_project(id) do
      {:ok, project} ->
        finish_opened_project(socket, project, context)

      {:error, reason} ->
        fail_recent_project(socket, id, reason, context)
    end
  end

  defp open_selected_project(socket, path, context) do
    case Projects.open_project(path) do
      {:ok, project} ->
        finish_opened_project(socket, project, context)

      {:error, reason} ->
        fail_open_project(socket, reason, context)
    end
  end

  defp finish_opened_project(socket, project, :check) do
    socket
    |> assign(:failed_recent_id, nil)
    |> assign(:confirm_forget_project_id, nil)
    |> assign_recents()
    |> put_flash(:info, "Checked #{project.name}. Repository is still valid.")
    |> push_patch(to: ~p"/projects/#{project.id}")
  end

  defp finish_opened_project(socket, project, _context) do
    socket
    |> assign(:failed_recent_id, nil)
    |> assign(:confirm_forget_project_id, nil)
    |> assign_recents()
    |> put_flash(:info, "Opened #{project.name}")
    |> push_patch(to: ~p"/projects/#{project.id}")
  end

  defp fail_recent_project(socket, id, :not_found, _context) do
    socket
    |> assign(:failed_recent_id, id)
    |> put_flash(
      :error,
      "That folder is gone. It may have been moved or deleted."
    )
  end

  defp fail_recent_project(socket, id, :not_a_directory, _context) do
    socket
    |> assign(:failed_recent_id, id)
    |> put_flash(:error, "That path is not a directory.")
  end

  defp fail_recent_project(socket, id, :not_a_git_repository, _context) do
    socket
    |> assign(:failed_recent_id, id)
    |> put_flash(
      :error,
      "Open a Git repository. #{Branding.product_name()} does not initialize repos."
    )
  end

  defp fail_recent_project(socket, id, :symlink_loop, _context) do
    socket
    |> assign(:failed_recent_id, id)
    |> put_flash(:error, "Could not resolve that path.")
  end

  defp fail_recent_project(socket, _id, reason, context) do
    fail_open_project(socket, reason, context)
  end

  defp fail_open_project(socket, :not_found, :picker) do
    put_flash(socket, :error, "That path does not exist.")
  end

  defp fail_open_project(socket, :not_found, _context) do
    put_flash(socket, :error, "That folder is gone. It may have been moved or deleted.")
  end

  defp fail_open_project(socket, :not_a_directory, _context) do
    put_flash(socket, :error, "That path is not a directory.")
  end

  defp fail_open_project(socket, :not_a_git_repository, _context) do
    put_flash(
      socket,
      :error,
      "Open a Git repository. #{Branding.product_name()} does not initialize repos."
    )
  end

  defp fail_open_project(socket, :symlink_loop, _context) do
    put_flash(socket, :error, "Could not resolve that path.")
  end

  defp fail_open_project(socket, _reason, _context) do
    put_flash(socket, :error, "Could not open that project.")
  end

  defp connect_env_path(%{provider: "remote"} = session) do
    AgentDesk.Providers.MCPInjection.connect_env_path(session)
  end

  defp connect_env_path(_session), do: nil

  defp select_session(socket, nil) do
    socket
    |> assign(:workspace_view, "dashboard")
    |> assign_analytics()
    |> assign(:active_session_id, nil)
    |> assign(:active_status, "idle")
    |> assign(:pending_approval, nil)
    |> assign(:connect_path, nil)
    |> assign(:inbox, [])
    |> assign(:deliveries, [])
    |> assign(:activity_tail, nil)
    |> stream(:activity, [], reset: true)
  end

  defp select_session(socket, session) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(AgentDesk.PubSub, "session:" <> session.id)
    end

    socket
    |> assign(:workspace_view, "workspace")
    |> assign(:active_session_id, session.id)
    |> assign(:active_status, session.status)
    |> assign(:pending_approval, nil)
    |> assign(:connect_path, connect_env_path(session))
    |> assign(:unread, Map.delete(socket.assigns.unread || %{}, session.id))
    |> assign(:activity_limit, 200)
    |> assign(:activity_tail, nil)
    |> then(&stream_transcript(&1, session, 200))
  end

  defp select_session_id(socket, id) do
    case Enum.find(socket.assigns.sessions, &(&1.id == id)) do
      nil -> socket
      session -> select_session(socket, session)
    end
  end

  defp dispatch_prompt(socket, prompt) do
    session = active_session(socket.assigns)
    project = socket.assigns.current_project
    {_, in_progress} = uploaded_entries(socket, :attachments)
    pending? = socket.assigns.uploads.attachments.entries != []

    cond do
      is_nil(session) or is_nil(project) ->
        {:noreply, put_flash(socket, :error, "No active session to prompt.")}

      in_progress != [] ->
        {:noreply, put_flash(socket, :error, "Wait for attachments to finish uploading.")}

      String.trim(prompt) == "" and not pending? ->
        {:noreply, socket}

      true ->
        attachments =
          consume_uploaded_entries(socket, :attachments, fn %{path: path}, entry ->
            {:ok,
             AgentDesk.Attachments.store!(
               project,
               session,
               path,
               entry.client_name,
               entry.client_type
             )}
          end)

        case SessionWorker.prompt(session.id, prompt, attachments) do
          :ok -> {:noreply, assign(socket, :prompt, "")}
          _ -> {:noreply, put_flash(socket, :error, "No active session to prompt.")}
        end
    end
  end

  defp maybe_status(socket, session) do
    if socket.assigns.active_session_id == session.id do
      socket
      |> assign(:active_status, session.status)
      |> announce_activity(session.status, socket.assigns.pending_approval)
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

  defp probe_providers do
    Map.new(~w(codex claude cursor opencode), fn key ->
      case AgentDesk.Providers.Discovery.probe(key) do
        {:ok, result} -> {key, Map.put(result, :available, true)}
        {:error, _} -> {key, %{available: false}}
      end
    end)
  end

  defp append_activity(event, socket) do
    if activity_visible?(event) do
      item = live_activity_item(event)
      tail = socket.assigns.activity_tail

      if AgentDesk.Activity.mergeable?(tail, item) do
        merged = AgentDesk.Activity.merge(tail, item)

        socket
        |> assign(:activity_tail, merged)
        |> stream_insert(:activity, merged, at: -1, limit: -200)
      else
        socket
        |> assign(:activity_tail, item)
        |> stream_insert(:activity, item, at: -1, limit: -200)
      end
    else
      socket
    end
  end

  defp live_activity_item(event) do
    %{
      id: Ids.generate(),
      type: Atom.to_string(event.type),
      text: activity_text(event),
      payload: event.payload
    }
  end

  defp activity_from_transcript(session, limit) do
    window = Transcript.window(session.project_id, session.id, limit: limit)

    items =
      window.rows
      |> Enum.filter(&transcript_visible?/1)
      |> Enum.map(&transcript_item/1)
      |> AgentDesk.Activity.coalesce()

    {items, window.older?}
  end

  defp stream_transcript(socket, session, limit) do
    {items, older?} = activity_from_transcript(session, limit)

    socket
    |> assign(:activity_older?, older?)
    |> assign(:activity_limit, limit)
    |> assign(:activity_tail, open_activity_tail(List.last(items)))
    |> stream(:activity, items, reset: true)
  end

  defp open_activity_tail(item) do
    if AgentDesk.Activity.open_stream?(item), do: item, else: nil
  end

  defp transcript_visible?(%{"type" => "initialize_result"}), do: false

  defp transcript_visible?(%{"type" => "message_delta", "payload" => payload}) do
    text = payload["text"]
    is_binary(text) and String.trim(text) != ""
  end

  defp transcript_visible?(%{"type" => type}) when is_binary(type), do: true
  defp transcript_visible?(_), do: false

  defp transcript_item(row) do
    type = row["type"]
    payload = row["payload"] || %{}

    %{
      id: Ids.generate(),
      type: type,
      text:
        payload["text"] || payload["summary"] || payload["message"] || payload["reason"] ||
          String.replace(to_string(type), "_", " "),
      payload: payload
    }
  end

  defp activity_visible?(%{type: type}) when type in [:initialize_result], do: false

  defp activity_visible?(%{type: :message_delta, payload: payload}) do
    text = payload["text"] || payload["delta"]
    is_binary(text) and String.trim(text) != ""
  end

  defp activity_visible?(_event), do: true

  defp activity_text(%{payload: payload, type: type}) when is_map(payload) do
    payload["text"] || payload["delta"] || payload["summary"] || payload["message"] ||
      payload["reason"] || activity_label(Atom.to_string(type))
  end

  defp activity_label("message_delta"), do: "Agent"
  defp activity_label("message_completed"), do: "Agent"
  defp activity_label("turn_started"), do: "Turn"
  defp activity_label("turn_completed"), do: "Turn complete"
  defp activity_label("session_ready"), do: "Ready"
  defp activity_label("file_change"), do: "File change"
  defp activity_label("provider_error"), do: "Error"
  defp activity_label("approval_requested"), do: "Approval"
  defp activity_label("command_started"), do: "Command"
  defp activity_label("command_completed"), do: "Command"
  defp activity_label("tool_started"), do: "Tool"
  defp activity_label("tool_completed"), do: "Tool"
  defp activity_label("session_exited"), do: "Exited"
  defp activity_label(type) when is_binary(type), do: String.replace(type, "_", " ")

  defp announce(socket, text), do: assign(socket, :announce, text)

  defp announce_activity(socket, status, approval) do
    cond do
      match?(%{payload: _}, approval) -> announce(socket, "Approval requested")
      status in ~w(completed failed blocked) -> announce(socket, "Session #{status}")
      true -> socket
    end
  end

  defp maybe_schedule_force(socket, "terminating") do
    if socket.assigns.active_status != "terminating" do
      Process.send_after(self(), :allow_force_terminate, 8_000)
    end

    socket
  end

  defp maybe_schedule_force(socket, _status),
    do: assign(socket, :allow_force_terminate, false)

  defp announce_background(socket, events, approval) do
    cond do
      match?(%{payload: _}, approval) ->
        announce(socket, "Approval requested on another tab")

      Enum.any?(events, &(&1.type in [:provider_error, :lease_conflict])) ->
        announce(socket, "A background session needs attention")

      true ->
        socket
    end
  end

  defp session_inbox(scope, session_id) when is_binary(session_id) do
    case Agents.get_session(scope, session_id) do
      {:ok, session} -> A2A.inbox(Scope.for_agent(scope.project, session))
      _ -> []
    end
  end

  defp session_inbox(_scope, _session_id), do: []

  defp peer_action(socket, agent_id, kind) do
    project = socket.assigns.current_project
    scope = reviewer_scope(socket)

    socket =
      cond do
        is_nil(scope.agent_session) ->
          put_flash(socket, :error, "Select a session tab first.")

        scope.agent_session.id == agent_id ->
          put_flash(socket, :error, "Pick another agent for that action.")

        true ->
          case perform_peer_action(scope, agent_id, kind) do
            :ok ->
              socket
              |> put_flash(:info, peer_flash(kind))
              |> announce(peer_flash(kind))

            {:error, _} ->
              put_flash(socket, :error, "Could not complete that agent action.")
          end
      end

    load_coordination(socket, project)
  end

  defp perform_peer_action(scope, agent_id, :message) do
    sender = scope.agent_session.display_name

    with {:ok, context} <- A2A.ensure_working_context(scope),
         {:ok, _} <-
           A2A.send_direct_message(scope, %{
             context_id: context.id,
             recipient_agent_id: agent_id,
             body: "Hello from #{sender}",
             idempotency_key: Ids.generate()
           }) do
      :ok
    end
  end

  defp perform_peer_action(scope, agent_id, kind) when kind in [:delegate, :review] do
    title = if kind == :review, do: "Review requested", else: "Delegated work"
    reason = if kind == :review, do: "review", else: "delegate"

    with {:ok, context} <- A2A.ensure_working_context(scope),
         {:ok, task} <- A2A.create_task(scope, context, %{title: title}),
         {:ok, _} <-
           A2A.propose_delegation(scope, %{
             task_id: task.id,
             to_agent_id: agent_id,
             reason: reason,
             idempotency_key: Ids.generate()
           }) do
      :ok
    end
  end

  defp peer_flash(:message), do: "Message queued."
  defp peer_flash(:delegate), do: "Delegation proposed."
  defp peer_flash(:review), do: "Review requested."

  defp lease_owner_message(socket, lease_id, body) do
    project = socket.assigns.current_project
    lease = Enum.find(socket.assigns.leases, &(&1.id == lease_id))
    scope = reviewer_scope(socket)

    socket =
      cond do
        is_nil(lease) ->
          put_flash(socket, :error, "That lease is no longer active.")

        is_nil(scope.agent_session) ->
          put_flash(socket, :error, "Select a session tab first.")

        scope.agent_session.id == lease.agent_session_id ->
          put_flash(socket, :info, "You already hold that lease.")

        true ->
          with {:ok, context} <- A2A.ensure_working_context(scope),
               {:ok, _} <-
                 A2A.send_direct_message(scope, %{
                   context_id: context.id,
                   recipient_agent_id: lease.agent_session_id,
                   body: "#{body} (#{lease.resource_type}:#{lease.resource_key})",
                   idempotency_key: Ids.generate()
                 }) do
            socket
            |> put_flash(:info, "Message sent to the lease owner.")
            |> announce("Message sent to the lease owner")
          else
            {:error, _} -> put_flash(socket, :error, "Could not message the lease owner.")
          end
      end

    load_coordination(socket, project)
  end

  defp mutate_delegation(socket, id, action, to_id \\ nil) do
    project = socket.assigns.current_project
    session_id = socket.assigns.active_session_id

    socket =
      with true <- is_binary(session_id),
           {:ok, session} <- Agents.get_session(Scope.for_project(project), session_id) do
        scope = Scope.for_agent(project, session)
        attrs = %{idempotency_key: Ids.generate()}

        result =
          case action do
            :revoke -> A2A.revoke_delegation(scope, id, attrs)
            :redirect -> A2A.redirect_delegation(scope, id, Map.put(attrs, :to_agent_id, to_id))
          end

        case result do
          {:ok, _} -> put_flash(socket, :info, "Delegation updated.")
          {:error, _} -> put_flash(socket, :error, "Could not update that delegation.")
        end
      else
        _ -> put_flash(socket, :error, "Select a session tab first.")
      end

    load_coordination(socket, project)
  end

  defp csv_list(value) when is_binary(value) do
    value
    |> String.split([",", "\n"], trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp csv_list(_), do: []

  defp blank_to_nil(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(_), do: nil

  defp auto_recipient_id(socket, %{"auto_recipient" => "true"}) do
    case socket.assigns.sessions do
      [%{id: id} | _] -> id
      _ -> nil
    end
  end

  defp auto_recipient_id(_socket, _params), do: nil
  defp maybe_claim_task_files(%{agent_session: nil}, _files, _title), do: :ok
  defp maybe_claim_task_files(_scope, [], _title), do: :ok

  defp maybe_claim_task_files(scope, files, title) do
    resources = Enum.map(files, &%{"type" => "file", "key" => &1, "mode" => "exclusive"})
    Manager.claim(scope, resources, reason: title || "task")
  end

  defp maybe_propose_task(%{agent_session: nil}, _task, _to_id, _reason), do: :ok
  defp maybe_propose_task(_scope, _task, nil, _reason), do: :ok

  defp maybe_propose_task(scope, task, to_id, reason) do
    if scope.agent_session.id == to_id do
      :ok
    else
      A2A.propose_delegation(scope, %{
        task_id: task.id,
        to_agent_id: to_id,
        reason: reason,
        idempotency_key: Ids.generate()
      })
    end
  end

  defp apply_project_prefs(socket, %Project{} = project) do
    settings = project.settings || %{}
    xerj = settings["xerj"] == true
    AgentDesk.Search.put_xerj(xerj)
    a2a = settings["a2a"] || %{}
    depth = a2a["max_delegation_depth"] || 3
    shortcuts = Map.merge(@default_shortcuts, settings["shortcuts"] || %{})

    socket
    |> assign(:xerj_enabled, xerj)
    |> assign(:delegation_depth, depth)
    |> assign(:shortcuts, shortcuts)
    |> assign(:onboard_step, settings["onboard_step"] || 1)
    |> assign(:onboard_complete, settings["onboard_complete"] == true)
  end

  defp persist_onboard(socket, step, opts \\ []) do
    complete? = Keyword.get(opts, :complete, false)

    socket
    |> assign(:onboard_step, step)
    |> assign(:onboard_complete, complete? or socket.assigns.onboard_complete)
    |> persist_project_setting("onboard_step", step)
    |> persist_project_setting("onboard_complete", complete? or socket.assigns.onboard_complete)
  end

  defp persist_project_setting(socket, key, value) do
    case socket.assigns.current_project do
      %Project{} = project ->
        case Projects.put_settings(project, %{key => value}) do
          {:ok, updated} -> assign(socket, :current_project, updated)
          _ -> socket
        end

      _ ->
        socket
    end
  end

  defp load_more_activity(socket) do
    session = active_session(socket.assigns)

    if session do
      stream_transcript(socket, session, socket.assigns.activity_limit + 200)
    else
      socket
    end
  end

  defp apply_shortcut(socket, "interrupt"), do: elem(handle_event("interrupt", %{}, socket), 1)
  defp apply_shortcut(socket, "load_older"), do: load_more_activity(socket)

  defp apply_shortcut(socket, "next_tab") do
    rotate_tab(socket, 1)
  end

  defp apply_shortcut(socket, "prev_tab") do
    rotate_tab(socket, -1)
  end

  defp apply_shortcut(socket, "new_session") do
    if socket.assigns.current_project do
      elem(
        handle_event(
          "start_session",
          %{
            "provider" => socket.assigns.provider,
            "display_name" => socket.assigns.display_name
          },
          socket
        ),
        1
      )
    else
      socket
    end
  end

  defp apply_shortcut(socket, _action), do: socket

  defp rotate_tab(socket, delta) do
    session_ids = Enum.map(socket.assigns.sessions, & &1.id)
    keys = ["dashboard" | session_ids]

    current =
      case socket.assigns.workspace_view do
        "dashboard" -> "dashboard"
        "new" -> "new"
        _ -> socket.assigns.active_session_id || "dashboard"
      end

    keys = if current == "new", do: keys ++ ["new"], else: keys
    index = Enum.find_index(keys, &(&1 == current)) || 0
    next = Enum.at(keys, rem(index + delta + length(keys), length(keys)))

    case next do
      "dashboard" -> elem(handle_event("set_view", %{"view" => "dashboard"}, socket), 1)
      "new" -> elem(handle_event("set_view", %{"view" => "new"}, socket), 1)
      id -> elem(handle_event("select_tab", %{"id" => id}, socket), 1)
    end
  end

  defp list_memories(%Project{} = project) do
    import Ecto.Query, only: [from: 2]

    from(m in AgentDesk.Search.Memory,
      where: m.project_id == ^project.id,
      order_by: [desc: m.inserted_at],
      limit: 20
    )
    |> Repo.all()
  end

  defp forget_sql_memory(project_id, id) do
    case Repo.get_by(AgentDesk.Search.Memory, id: id, project_id: project_id) do
      nil -> :ok
      row -> Repo.delete(row)
    end
  end

  defp isolation_profile(nil), do: nil
  defp isolation_profile(session), do: Isolation.profile(session)

  defp show_onboarding?(assigns) do
    is_nil(assigns.current_project) or
      (assigns.sessions == [] and not assigns.onboard_complete)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :active, active_session(assigns))
    assigns = assign(assigns, :caps, capabilities(assigns.active))
    assigns = assign(assigns, :show_onboarding, show_onboarding?(assigns))
    assigns = assign(assigns, :isolation, isolation_profile(assigns.active))

    assigns =
      assign(
        assigns,
        :review_item,
        selected_queue_item(assigns.merge_queue, assigns[:selected_handoff_id])
      )

    AgentDeskWeb.WorkspaceHTML.render(assigns)
  end
end
