defmodule BossWeb.HomeLive do
  use BossWeb, :live_view
  alias Boss.Projects

  @impl true
  def mount(_params, _session, socket) do
    projects = Projects.list_projects()

    {:ok,
     assign(socket,
       page_title: "Projects · BOSS",
       projects: projects,
       stats: project_stats(projects),
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
        projects = Projects.list_projects()

        {:noreply,
         assign(socket,
           projects: projects,
           stats: project_stats(projects),
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

  defp project_stats(projects) do
    Map.new(projects, fn project ->
      entries =
        project.id
        |> Projects.list_spec_entries()
        |> Enum.reject(&Map.get(&1, :reference_only, false))

      total = length(entries)
      done = Enum.count(entries, &(&1.state == "done"))

      active =
        Enum.count(
          entries,
          &(&1.state in ~w(planning implementing testing reviewing integrating))
        )

      {project.id, %{total: total, done: done, active: active}}
    end)
  rescue
    _ -> %{}
  end

  defp mode_chip(project) do
    mode = if project.intake_mode == "documentation", do: "docs", else: "specs"
    base = Path.basename(project.specs_path)
    if base == mode, do: "#{mode}/", else: "#{mode} · #{base}"
  end

  @impl true
  def render(assigns) do
    submitted? = assigns.form.source.action != nil

    advanced_open =
      assigns.folders["specs_path"] != nil or
        (submitted? and
           (assigns.form[:specs_path].errors != [] or
              assigns.form[:base_branch].errors != [] or
              assigns.form[:name].errors != []))

    assigns = assign(assigns, :advanced_open, advanced_open)

    ~H"""
    <header class="mb-5 flex flex-wrap items-center justify-between gap-3">
      <div class="flex items-center gap-3">
        <h1 class="app-page-title">Projects</h1>
        <span class="app-badge tabular-nums">{length(@projects)}</span>
      </div>
      <span class="text-xs text-muted">
        Closing this tab keeps BOSS running in your terminal.
      </span>
    </header>

    <p
      :if={@message}
      role="status"
      class="mb-4 rounded-lg border border-forest/30 bg-sage px-3.5 py-2 text-xs font-medium text-forest"
    >
      {@message}
    </p>

    <div class="grid min-w-0 items-start gap-6 lg:grid-cols-[minmax(0,1fr)_23rem]">
      <section aria-label="Registered projects" class="min-w-0">
        <p :if={@projects == []} class="app-empty-state">
          No projects yet. Connect a local repository to begin.
        </p>

        <ul
          :if={@projects != []}
          id="projects"
          class="grid gap-3 sm:grid-cols-2"
        >
          <li
            :for={project <- @projects}
            id={"project-#{project.id}"}
            class="min-w-0"
          >
            <% stat = Map.get(@stats, project.id, %{total: 0, done: 0, active: 0}) %>
            <% pct = if stat.total > 0, do: round(stat.done * 100 / stat.total), else: 0 %>
            <.link
              navigate={~p"/projects/#{project.id}"}
              class="board-card group flex h-full flex-col justify-between gap-3.5 border border-line p-4 no-underline"
            >
              <div class="min-w-0">
                <div class="flex items-start justify-between gap-3">
                  <h2 class="min-w-0 truncate text-base font-semibold text-ink group-hover:text-forest">
                    {project.name}
                  </h2>
                  <span class="flex shrink-0 items-center gap-1.5">
                    <span :if={stat.active > 0} class="board-live-dot" aria-hidden="true"></span>
                    <span
                      class="font-mono text-xs text-muted group-hover:text-forest"
                      aria-hidden="true"
                    >
                      ↗
                    </span>
                  </span>
                </div>
                <p
                  class="mt-1 truncate font-mono text-xs text-muted"
                  title={project.root_path}
                >
                  {project.root_path}
                </p>
              </div>

              <div class="space-y-2.5">
                <div :if={stat.total > 0} class="space-y-1">
                  <div class="flex items-center justify-between font-mono text-[11px] text-muted">
                    <span>{stat.done}/{stat.total} done</span>
                    <span>{pct}%</span>
                  </div>
                  <div class="board-stage-track">
                    <div class="board-stage-fill" style={"width: #{pct}%"}></div>
                  </div>
                </div>

                <div class="flex flex-wrap items-center gap-1.5 font-mono text-[11px]">
                  <span class="app-pill">
                    <span class="text-forest">⎇</span>
                    <span class="max-w-36 truncate">{project.base_branch}</span>
                  </span>
                  <span class="app-pill text-muted">
                    {mode_chip(project)}
                  </span>
                </div>
              </div>
            </.link>
          </li>
        </ul>
      </section>

      <section
        aria-labelledby="add-project-title"
        class="app-panel min-w-0 lg:sticky lg:top-16"
      >
        <div class="flex items-center justify-between gap-2">
          <h2 id="add-project-title" class="app-panel-heading">Connect repository</h2>
          <span class="app-eyebrow">Git</span>
        </div>
        <p id="project-help" class="sr-only">
          Choose a Git repository with at least one commit and a documentation or specs folder.
        </p>

        <.form
          for={@form}
          id="project-form"
          phx-change="validate"
          phx-submit="create"
          aria-describedby="project-help"
          class="mt-4 space-y-3.5"
        >
          <p
            :if={@duplicate?}
            role="alert"
            class="rounded-md border border-danger-line bg-danger-soft px-3 py-2 text-xs text-danger"
          >
            This repository is already registered, including its linked worktrees.
          </p>

          <.folder
            field={@form[:root_path]}
            label="Repository"
            kind="repository"
            disabled={@picking != nil}
          />

          <div class="rounded-lg border border-line bg-paper/60 px-3 py-2">
            <input type="hidden" name={@form[:intake_mode].name} value="specs" />
            <label
              for={@form[:intake_mode].id}
              class="flex cursor-pointer items-center gap-2.5 text-xs font-medium text-body"
            >
              <input
                id={@form[:intake_mode].id}
                name={@form[:intake_mode].name}
                type="checkbox"
                value="documentation"
                checked={@form[:intake_mode].value == "documentation"}
                aria-describedby="intake-mode-help"
                class="h-4 w-4 rounded accent-forest"
              />
              <span>Plan tasks from documentation</span>
            </label>
            <p id="intake-mode-help" class="sr-only">
              Start Autopilot will compare the committed documentation with the code and create a task plan.
            </p>
          </div>

          <p :if={@picking} role="status" class="text-xs text-forest">
            Choose a folder in the system dialog on this computer…
          </p>

          <details open={@advanced_open} class="rounded-lg border border-line bg-paper/40 px-3 py-2">
            <summary class="flex cursor-pointer items-center justify-between text-xs font-medium text-muted hover:text-ink">
              <span>Custom folder, branch &amp; name</span>
              <span class="font-mono text-[10px]">optional</span>
            </summary>
            <div class="mt-3 space-y-3 border-t border-line pt-3">
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
              <.field
                field={@form[:base_branch]}
                label={
                  if @form[:intake_mode].value == "documentation",
                    do: "Target branch",
                    else: "Base branch"
                }
                placeholder={
                  if @form[:intake_mode].value == "documentation",
                    do: "Dedicated branch (auto)",
                    else: "Current branch"
                }
              />
              <.field
                field={@form[:name]}
                label="Display name"
                placeholder="Folder name"
              />
            </div>
          </details>

          <button
            id="add-project"
            type="submit"
            disabled={@picking != nil or is_nil(@folders["root_path"])}
            phx-disable-with="Adding…"
            class="app-button-primary w-full py-2.5 font-semibold phx-submit-loading:opacity-60"
          >
            Add project
          </button>
        </.form>
      </section>
    </div>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :kind, :string, required: true
  attr :disabled, :boolean, required: true

  defp folder(assigns) do
    ~H"""
    <div>
      <label for={@field.id} class="block text-xs font-medium text-muted">{@label}</label>
      <div class="mt-1.5 flex gap-2">
        <input
          id={@field.id}
          value={@field.value}
          type="text"
          readonly
          placeholder="No folder selected"
          aria-invalid={@field.errors != []}
          aria-describedby={if @field.errors != [], do: @field.id <> "-error"}
          class="app-field min-w-0 flex-1 font-mono text-xs"
        />
        <button
          id={"choose-#{@kind}"}
          type="button"
          phx-click="choose_folder"
          phx-value-kind={@kind}
          disabled={@disabled}
          class="app-button-secondary shrink-0 px-3 text-xs"
        >
          {if @kind == "repository", do: "Browse…", else: "Change…"}
        </button>
      </div>
      <div
        :if={@field.errors != []}
        id={@field.id <> "-error"}
        role="alert"
        class="mt-1.5 text-xs text-danger"
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
      <label for={@field.id} class="block text-xs font-medium text-muted">{@label}</label>
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
        class="app-field mt-1.5 w-full text-xs"
      />
      <div
        :if={@errors != []}
        id={@field.id <> "-error"}
        role="alert"
        class="mt-1.5 text-xs text-danger"
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
