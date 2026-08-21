defmodule AgentDeskWeb.WorkspaceLive do
  @moduledoc """
  Desktop application shell: project sidebar, agent workspace, and context panel.
  """

  use AgentDeskWeb, :live_view

  alias AgentDesk.Projects
  alias AgentDesk.Projects.Project
  alias AgentDesk.Projects.Supervisor, as: ProjectSupervisor

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
     |> assign(:form, to_form(%{"path" => ""}))}
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

  defp assign_current_project(socket, %{"id" => id}) do
    case Projects.get_project(id) do
      {:ok, project} ->
        {:ok, _pid} = ProjectSupervisor.start_runtime(project)

        socket
        |> assign(:current_project, project)
        |> assign(:page_title, project.name)

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

  @impl true
  def render(assigns) do
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
          <section class="flex items-center justify-center p-8">
            <div class="max-w-lg space-y-3 text-center">
              <h2 class="text-lg font-semibold">Agent workspace</h2>
              <p class="text-sm text-base-content/70">
                Tabs, streamed activity, approvals, and the prompt composer land here.
                Provider adapters and the internal A2A Hub are not wired yet.
              </p>
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
                <dt class="text-xs text-base-content/50">Leases</dt>
                <dd>Exact-file and named-resource leases come in Phase 3.</dd>
              </div>
              <div>
                <dt class="text-xs text-base-content/50">A2A</dt>
                <dd>Agent Cards, delegations, durable messages, and artifacts persist in SQLite.</dd>
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
    <div class="flex items-center gap-1">
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
