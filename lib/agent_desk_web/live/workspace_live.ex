defmodule AgentDeskWeb.WorkspaceLive do
  @moduledoc """
  Desktop application shell: project sidebar, agent tabs, activity, and approvals.
  """

  use AgentDeskWeb, :live_view

  alias AgentDesk.Agents
  alias AgentDesk.Ids
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Project
  alias AgentDesk.Projects.Supervisor, as: ProjectSupervisor
  alias AgentDesk.Providers
  alias AgentDesk.Providers.SessionWorker
  alias AgentDesk.Scope

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
     |> assign(:sessions, [])
     |> assign(:active_session_id, nil)
     |> assign(:active_status, "idle")
     |> assign(:pending_approval, nil)
     |> assign(:prompt, "")
     |> assign(:display_name, "")
     |> assign(:provider, "fake")
     |> assign(:confirm_terminate, false)
     |> assign(:form, to_form(%{"path" => ""}))
     |> stream(:activity, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    socket =
      if connected?(socket) do
        socket
        |> assign(:recent_projects, Projects.list_recent())
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

  def handle_event(_event, _params, %{assigns: %{current_project: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Open a project first.")}
  end

  def handle_event("start_session", %{"provider" => provider, "display_name" => name}, socket) do
    project = socket.assigns.current_project
    name = if String.trim(name) == "", do: provider, else: name

    case Providers.start_session(Scope.for_project(project), %{
           provider: provider,
           display_name: name
         }) do
      {:ok, session} ->
        {:noreply,
         socket
         |> assign(:display_name, "")
         |> assign(:sessions, Agents.visible_sessions(Scope.for_project(project)))
         |> select_session(session)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Could not start that provider session.")}
    end
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

  @impl true
  def handle_info(:restore_last_project, socket) do
    {:noreply, maybe_restore_last_project(socket)}
  end

  def handle_info({:project_opened, project}, socket) do
    {:noreply,
     socket
     |> assign(:recent_projects, Projects.list_recent())
     |> maybe_replace_current(project)}
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

  defp assign_current_project(socket, %{"id" => id}) do
    case Projects.get_project(id) do
      {:ok, project} ->
        {:ok, _pid} = ProjectSupervisor.start_runtime(project)

        if socket.assigns[:subscribed_project_id] != project.id do
          Phoenix.PubSub.subscribe(AgentDesk.PubSub, "project:" <> project.id <> ":sessions")
        end

        scope = Scope.for_project(project)
        sessions = Agents.visible_sessions(scope)

        socket
        |> assign(:current_project, project)
        |> assign(:subscribed_project_id, project.id)
        |> assign(:page_title, project.name)
        |> assign(:sessions, sessions)
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

  defp maybe_restore_last_project(socket) do
    cond do
      socket.assigns.live_action != :index ->
        socket

      socket.assigns.current_project ->
        socket

      true ->
        case Projects.last_opened() do
          %Project{} = project ->
            push_patch(socket, to: ~p"/projects/#{project.id}")

          nil ->
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

  defp select_session(socket, nil) do
    socket
    |> assign(:active_session_id, nil)
    |> assign(:active_status, "idle")
    |> assign(:pending_approval, nil)
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
            <li :for={project <- @recent_projects}>
              <.link
                patch={~p"/projects/#{project.id}"}
                class={[
                  "block rounded-lg px-3 py-2 text-sm hover:bg-base-200",
                  @current_project && @current_project.id == project.id && "bg-base-200 font-medium"
                ]}
              >
                <span class="block truncate">{project.name}</span>
                <span class="block truncate text-xs text-base-content/50">
                  {project.canonical_path}
                </span>
              </.link>
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
          </div>
        </header>

        <div class="grid min-h-0 flex-1 grid-cols-[1fr_20rem]">
          <section class="flex min-h-0 flex-col">
            <div :if={@current_project} class="border-b border-base-300 bg-base-100 px-4 py-2">
              <form
                id="start-session-form"
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
                <.button class="btn btn-primary btn-xs">New session</.button>
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
                <dt class="text-xs text-base-content/50">Leases</dt>
                <dd>Exact-file and named-resource leases come in Phase 3.</dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">A2A</dt>
                <dd>Each first-class session registers an Agent Card and receives inbox delivery.</dd>
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
