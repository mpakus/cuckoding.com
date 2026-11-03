defmodule BossWeb.HomeLive do
  use BossWeb, :live_view
  alias Boss.Projects

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Projects · BOSS",
       projects: Projects.list_projects(),
       form: to_form(Projects.change_project()),
       folders: %{"root_path" => nil, "specs_path" => nil},
       picking: nil,
       message: nil,
       duplicate?: false
     )}
  end

  @impl true
  def handle_event("validate", %{"project" => attrs}, socket) do
    changeset = %{Projects.change_project(project_attrs(socket, attrs)) | action: :validate}
    {:noreply, assign(socket, form: to_form(changeset), message: nil, duplicate?: false)}
  end

  def handle_event("choose_folder", %{"kind" => kind}, %{assigns: %{picking: nil}} = socket)
      when kind in ["repository", "specs"] do
    root = socket.assigns.folders["root_path"]

    if kind == "specs" and is_nil(root) do
      {:noreply, socket}
    else
      kind = if kind == "repository", do: :repository, else: :specs

      initial =
        if kind == :specs,
          do: Path.expand(project_attrs(socket, socket.assigns.form.params)["specs_path"], root),
          else: root

      initial = if is_binary(initial) and File.dir?(initial), do: initial, else: root
      picker = Application.get_env(:boss, :folder_picker_server, Boss.FolderPicker)

      {:noreply,
       socket
       |> assign(picking: kind, message: nil)
       |> start_async(:folder_picker, fn -> Boss.FolderPicker.choose(kind, initial, picker) end)}
    end
  end

  def handle_event("choose_folder", _, socket), do: {:noreply, socket}

  def handle_event("create", _, %{assigns: %{picking: picking}} = socket) when picking != nil,
    do: {:noreply, socket}

  def handle_event("create", %{"project" => attrs}, socket) do
    case Projects.create_project(project_attrs(socket, attrs)) do
      {:ok, %{intake_mode: "documentation"} = project} ->
        {:noreply, push_navigate(socket, to: ~p"/projects/#{project.id}")}

      {:ok, _project} ->
        {:noreply,
         assign(socket,
           projects: Projects.list_projects(),
           form: to_form(Projects.change_project()),
           folders: %{"root_path" => nil, "specs_path" => nil},
           message: "Project added.",
           duplicate?: false
         )}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           form: to_form(changeset),
           message: nil,
           duplicate?: Keyword.has_key?(changeset.errors, :git_common_dir)
         )}
    end
  end

  @impl true
  def handle_async(:folder_picker, {:ok, {:ok, path}}, socket) do
    folders =
      if socket.assigns.picking == :repository,
        do: %{"root_path" => path, "specs_path" => nil},
        else:
          Map.put(
            socket.assigns.folders,
            "specs_path",
            Path.relative_to(path, socket.assigns.folders["root_path"])
          )

    socket = assign(socket, folders: folders, picking: nil, duplicate?: false)
    form = to_form(Projects.change_project(project_attrs(socket, socket.assigns.form.params)))
    {:noreply, assign(socket, form: form)}
  end

  def handle_async(:folder_picker, {:ok, :cancelled}, socket),
    do: {:noreply, assign(socket, picking: nil)}

  def handle_async(:folder_picker, result, socket) do
    message =
      case result do
        {:ok, {:error, :unavailable}} ->
          "Folder selection is unavailable. Run BOSS in a desktop session on macOS or Linux with Zenity installed."

        {:ok, {:error, :busy}} ->
          "A folder dialog is already open. Finish that selection first."

        {:ok, {:error, :timeout}} ->
          "Folder selection timed out. Choose the folder again."

        _ ->
          "Could not open or read the folder dialog. Try again."
      end

    {:noreply, assign(socket, picking: nil, message: message)}
  end

  defp project_attrs(socket, attrs) do
    root = socket.assigns.folders["root_path"]
    docs? = is_binary(root) && File.dir?(Path.join(root, "docs"))

    mode =
      Map.get(attrs, "intake_mode", if(docs? or is_nil(root), do: "documentation", else: "specs"))

    default_path = if mode == "documentation" and docs?, do: "docs", else: "specs"

    attrs
    |> Map.take(["name", "base_branch"])
    |> Map.put("root_path", root)
    |> Map.put("specs_path", socket.assigns.folders["specs_path"] || default_path)
    |> Map.put("intake_mode", mode)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <header class="app-page-header">
      <p class="app-eyebrow">Your workspace</p>
      <h1 class="app-page-title">Projects</h1>
      <p class="app-page-description">
        Connect a local repository to plan tasks from documentation or import individual specs.
      </p>
    </header>
    <p :if={@message} role="status" class="mb-6 text-sm text-forest">{@message}</p>
    <div class="grid min-w-0 items-start gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(0,1fr)] lg:gap-10">
      <section aria-label="Registered projects" class="min-w-0 border-t border-line pt-5">
        <div class="mb-5 flex items-center justify-between gap-3">
          <h2 class="app-panel-heading">Repositories</h2>
          <span class="app-badge tabular-nums">{length(@projects)}</span>
        </div>
        <p
          :if={@projects == []}
          class="app-empty-state"
        >
          No projects yet. Add your first repository to get started.
        </p>
        <ul id="projects" class="divide-y divide-line">
          <li :for={project <- @projects} id={"project-#{project.id}"} class="py-6 first:pt-0">
            <h3 class="text-xl font-semibold">
              <.link
                navigate={~p"/projects/#{project.id}"}
                class="flex min-w-0 items-baseline justify-between gap-4 break-words text-ink hover:text-forest focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-forest"
              >
                <span class="min-w-0">{project.name}</span><span
                  aria-hidden="true"
                  class="shrink-0 text-forest"
                >↗</span>
              </.link>
            </h3>
            <p class="mt-2 break-all font-mono text-sm text-body">{project.root_path}</p>
            <dl class="mt-4 grid gap-3 text-xs text-muted">
              <div class="flex flex-wrap gap-x-3 gap-y-1">
                <dt>Base branch</dt><dd class="break-all font-mono text-ink">
                  {project.base_branch}
                </dd>
              </div>
              <div>
                <dt>Specs directory</dt><dd class="mt-1 break-all font-mono">{project.specs_path}</dd>
              </div>
            </dl>
          </li>
        </ul>
      </section>
      <section
        aria-labelledby="add-project-title"
        class="min-w-0 rounded-sm border border-line bg-peach/40 p-5 sm:p-6"
      >
        <p class="app-eyebrow mb-3">Start with the source</p>
        <h2 id="add-project-title" class="app-panel-heading">Add a local project</h2>
        <p id="project-help" class="mt-2 text-sm text-muted">
          Choose a Git repository with at least one commit and a documentation or specs folder.
        </p>
        <.form
          for={@form}
          id="project-form"
          phx-change="validate"
          phx-submit="create"
          aria-describedby="project-help"
          class="mt-6 space-y-5"
        >
          <p :if={@duplicate?} role="alert" class="text-sm text-danger">
            This repository is already registered, including its linked worktrees.
          </p>
          <.folder
            field={@form[:root_path]}
            label="Repository folder"
            kind="repository"
            disabled={@picking != nil}
          />
          <div>
            <input type="hidden" name={@form[:intake_mode].name} value="specs" />
            <label for={@form[:intake_mode].id} class="flex min-h-11 items-center gap-2 text-sm">
              <input
                id={@form[:intake_mode].id}
                name={@form[:intake_mode].name}
                type="checkbox"
                value="documentation"
                checked={@form[:intake_mode].value == "documentation"}
                aria-describedby="intake-mode-help"
              /> Plan tasks from documentation
            </label>
            <p id="intake-mode-help" class="mt-1 text-xs text-muted">
              Start Autopilot will compare the committed documentation with the code and create a task plan.
            </p>
          </div>
          <.folder
            field={@form[:specs_path]}
            label={
              if @form[:intake_mode].value == "documentation",
                do: "Documentation folder",
                else: "Specs directory"
            }
            kind="specs"
            disabled={@picking != nil or is_nil(@folders["root_path"])}
          />
          <p :if={@picking} role="status" class="text-sm text-body">
            Choose a folder in the system dialog on this computer.
          </p>
          <.field
            field={@form[:base_branch]}
            label={
              if @form[:intake_mode].value == "documentation",
                do: "Integration target branch (optional)",
                else: "Base branch (optional)"
            }
            placeholder={
              if @form[:intake_mode].value == "documentation",
                do: "Create a dedicated branch",
                else: "Current branch"
            }
          />
          <.field
            field={@form[:name]}
            label="Project name (optional)"
            placeholder="Repository folder name"
          />
          <button
            id="add-project"
            type="submit"
            disabled={@picking != nil or is_nil(@folders["root_path"])}
            phx-disable-with="Adding…"
            class="app-button-primary px-5 py-3 font-semibold disabled:opacity-40 phx-submit-loading:opacity-60"
          >
            Add project
          </button>
        </.form>
      </section>
    </div>
    <p class="mt-8 border-t border-line pt-6 text-sm text-muted">
      Closing this tab keeps BOSS running. Stop the server in your terminal when finished.
    </p>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :kind, :string, required: true
  attr :disabled, :boolean, required: true

  defp folder(assigns) do
    ~H"""
    <div>
      <label for={@field.id} class="block text-sm font-medium">{@label}</label>
      <div class="mt-2 flex flex-col gap-2 sm:flex-row lg:flex-col xl:flex-row">
        <input
          id={@field.id}
          value={@field.value}
          type="text"
          readonly
          placeholder="No folder selected"
          aria-invalid={@field.errors != []}
          aria-describedby={if @field.errors != [], do: @field.id <> "-error"}
          class="app-field min-w-0 flex-1 px-3 py-3 text-sm"
        />
        <button
          id={"choose-#{@kind}"}
          type="button"
          phx-click="choose_folder"
          phx-value-kind={@kind}
          disabled={@disabled}
          class="app-button-secondary shrink-0 px-4 py-3 text-sm font-medium disabled:opacity-40"
        >
          {if @kind == "repository", do: "Choose repository…", else: "Choose specs folder…"}
        </button>
      </div>
      <div
        :if={@field.errors != []}
        id={@field.id <> "-error"}
        role="alert"
        class="mt-2 text-sm text-danger"
      >
        <p :for={{message, _opts} <- @field.errors}>{message}</p>
      </div>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :placeholder, :string, required: true
  attr :required, :boolean, default: false

  defp field(assigns) do
    assigns =
      assign(assigns, :errors, if(used_input?(assigns.field), do: assigns.field.errors, else: []))

    ~H"""
    <div>
      <label for={@field.id} class="block text-sm font-medium">{@label}</label>
      <input
        id={@field.id}
        name={@field.name}
        value={@field.value}
        type="text"
        placeholder={@placeholder}
        required={@required}
        autocomplete="off"
        autocorrect="off"
        autocapitalize="off"
        spellcheck="false"
        aria-invalid={@errors != []}
        aria-describedby={if @errors != [], do: @field.id <> "-error"}
        class="app-field mt-2 w-full px-3 py-3 text-sm"
      />
      <div
        :if={@errors != []}
        id={@field.id <> "-error"}
        role="alert"
        class="mt-2 text-sm text-danger"
      >
        <p :for={{message, opts} <- @errors}>
          {Enum.reduce(opts, message, fn {key, value}, text ->
            String.replace(text, "%{#{key}}", to_string(value))
          end)}
        </p>
      </div>
    </div>
    """
  end
end
