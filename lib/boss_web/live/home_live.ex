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
       message: nil,
       duplicate?: false
     )}
  end

  @impl true
  def handle_event("validate", %{"project" => attrs}, socket) do
    changeset = %{Projects.change_project(attrs) | action: :validate}
    {:noreply, assign(socket, form: to_form(changeset), message: nil, duplicate?: false)}
  end

  def handle_event("create", %{"project" => attrs}, socket) do
    case Projects.create_project(attrs) do
      {:ok, _project} ->
        {:noreply,
         assign(socket,
           projects: Projects.list_projects(),
           form: to_form(Projects.change_project()),
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
  def render(assigns) do
    ~H"""
    <p class="text-sm font-semibold tracking-widest text-emerald-400">BOSS · LOCAL</p>
    <h1 class="mt-4 text-3xl font-semibold">Projects</h1>
    <p class="mt-3 text-zinc-300">
      Connect a local repository to your workspace. Spec import and agent runs are coming next.
    </p>
    <p :if={@message} role="status" class="mt-6 text-sm text-emerald-300">{@message}</p>
    <section aria-label="Registered projects" class="mt-8">
      <p
        :if={@projects == []}
        class="rounded-md border border-dashed border-zinc-700 px-5 py-6 text-zinc-400"
      >
        No projects yet. Add your first repository below.
      </p>
      <ul id="projects" class="divide-y divide-zinc-800">
        <li :for={project <- @projects} id={"project-#{project.id}"} class="py-5 first:pt-0">
          <h2 class="font-semibold">{project.name}</h2>
          <p class="mt-2 break-all font-mono text-sm text-zinc-300">{project.root_path}</p>
          <dl class="mt-3 space-y-1 text-sm text-zinc-400">
            <div class="flex gap-2">
              <dt>Base branch</dt><dd class="break-all text-zinc-200">{project.base_branch}</dd>
            </div>
            <div>
              <dt>Specs directory</dt><dd class="mt-1 break-all font-mono">{project.specs_path}</dd>
            </div>
          </dl>
        </li>
      </ul>
    </section>
    <section aria-labelledby="add-project-title" class="mt-8 border-t border-zinc-800 pt-8">
      <h2 id="add-project-title" class="text-xl font-semibold">Add a local project</h2>
      <p id="project-help" class="mt-2 text-sm text-zinc-400">
        Choose an existing Git repository with at least one commit and a specs directory inside it.
      </p>
      <.form
        for={@form}
        id="project-form"
        phx-change="validate"
        phx-submit="create"
        aria-describedby="project-help"
        class="mt-6 space-y-5"
      >
        <p :if={@duplicate?} role="alert" class="text-sm text-red-300">
          This repository is already registered, including its linked worktrees.
        </p>
        <.field
          field={@form[:root_path]}
          label="Repository path"
          placeholder="/Users/you/projects/my-app"
          required
        />
        <.field field={@form[:specs_path]} label="Specs directory" placeholder="specs" required />
        <.field
          field={@form[:base_branch]}
          label="Base branch (optional)"
          placeholder="Current branch"
        />
        <.field
          field={@form[:name]}
          label="Project name (optional)"
          placeholder="Repository folder name"
        />
        <button
          type="submit"
          phx-disable-with="Adding…"
          class="rounded-md bg-emerald-400 px-5 py-3 font-semibold text-zinc-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 phx-submit-loading:opacity-60"
        >
          Add project
        </button>
      </.form>
    </section>
    <p class="mt-8 border-t border-zinc-800 pt-6 text-sm text-zinc-400">
      Closing this tab keeps BOSS running. Stop the server in your terminal when finished.
    </p>
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
        class="mt-2 w-full rounded-md border border-zinc-600 bg-zinc-900 px-3 py-3 text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
      />
      <div
        :if={@errors != []}
        id={@field.id <> "-error"}
        role="alert"
        class="mt-2 text-sm text-red-300"
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
