defmodule CuckodingWeb.ProjectSetupLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.PolicyComponents

  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.ProjectOnboarding

  @steps ["Project", "Repository", "Agents and roles", "Review"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Add project",
       step: 1,
       steps: @steps,
       error: nil,
       roles: ProjectOnboarding.default_roles(),
       runtime_options: RuntimeConfiguration.options(),
       project: %{
         "name" => "",
         "description" => "",
         "repo_path" => "",
         "default_branch" => "main",
         "runtime" => "codex",
         "executable_path" => System.find_executable("codex") || "",
         "api_key_helper" => "",
         "confirmed" => "false"
       }
     )}
  end

  @impl true
  def handle_event("next", %{"project" => params}, socket) do
    project = Map.merge(socket.assigns.project, params)

    case validate_step(socket.assigns.step, project) do
      {:ok, normalized} ->
        {:noreply,
         assign(socket,
           project: Map.merge(project, normalized),
           step: socket.assigns.step + 1,
           error: nil
         )}

      {:error, reason} ->
        {:noreply, assign(socket, project: project, error: error_message(reason))}
    end
  end

  def handle_event("back", _params, socket) do
    {:noreply, assign(socket, step: max(socket.assigns.step - 1, 1), error: nil)}
  end

  def handle_event("create", %{"project" => params}, socket) do
    project = Map.merge(socket.assigns.project, params)

    if project["confirmed"] == "true" do
      case ProjectOnboarding.create(project) do
        {:ok, %{project: created}} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{created.name} was added. Create a board when you are ready.")
           |> push_navigate(to: ~p"/")}

        {:error, reason} ->
          {:noreply, assign(socket, project: project, error: error_message(reason))}
      end
    else
      {:noreply,
       assign(socket,
         project: project,
         error: "Confirm the repository and host-runner settings before adding the project."
       )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app>
      <section aria-labelledby="project-setup-heading" class="mx-auto max-w-4xl space-y-8">
        <header class="space-y-3">
          <p class="text-sm font-semibold uppercase tracking-wide text-slate-600">Project setup</p>
          <h1 id="project-setup-heading" class="text-3xl font-semibold tracking-tight text-slate-950">
            Add a project
          </h1>
          <p class="max-w-2xl text-base leading-7 text-slate-700">
            Register an existing repository, connect an agent runtime, and review the default roles.
            Setup does not create a board, task, branch, worktree, or running process.
          </p>
        </header>

        <nav aria-label="Project setup progress">
          <ol class="grid gap-2 sm:grid-cols-4">
            <li :for={{label, index} <- Enum.with_index(@steps, 1)}>
              <span
                aria-current={if index == @step, do: "step"}
                class={[
                  "flex min-h-11 items-center rounded-md border px-3 text-sm font-medium",
                  index == @step && "border-slate-950 bg-slate-950 text-white",
                  index < @step && "border-emerald-300 bg-emerald-50 text-emerald-950",
                  index > @step && "border-slate-200 bg-white text-slate-600"
                ]}
              >
                {index}. {label}
              </span>
            </li>
          </ol>
        </nav>

        <p
          :if={@error}
          id="project-setup-error"
          role="alert"
          class="rounded-md border border-red-300 bg-red-50 p-4 text-sm text-red-950"
        >
          {@error}
        </p>

        <form :if={@step == 1} id="project-step-1" phx-submit="next" class="space-y-6">
          <fieldset class="space-y-5 rounded-xl border border-slate-200 bg-white p-6">
            <legend class="px-2 text-lg font-semibold text-slate-950">Project identity</legend>
            <label class="grid gap-2 font-medium text-slate-800">
              Project name
              <input
                name="project[name]"
                value={@project["name"]}
                required
                autofocus
                class="min-h-11 rounded-md border border-slate-400 px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
              />
            </label>
            <label class="grid gap-2 font-medium text-slate-800">
              Description <span class="text-sm font-normal text-slate-600">Optional</span>
              <textarea
                name="project[description]"
                rows="4"
                class="rounded-md border border-slate-400 px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2"
              >{@project["description"]}</textarea>
            </label>
          </fieldset>
          <.wizard_actions step={@step} />
        </form>

        <form :if={@step == 2} id="project-step-2" phx-submit="next" class="space-y-6">
          <fieldset class="space-y-5 rounded-xl border border-slate-200 bg-white p-6">
            <legend class="px-2 text-lg font-semibold text-slate-950">Repository</legend>
            <p class="text-sm leading-6 text-slate-700">
              Choose the root folder of an existing local Git repository. Uncommitted work is allowed;
              Cuckoding only reads the selected branch revision during setup.
            </p>
            <label class="grid gap-2 font-medium text-slate-800">
              Repository folder
              <input
                name="project[repo_path]"
                value={@project["repo_path"]}
                type="text"
                required
                placeholder="/absolute/path/to/repository"
                autocapitalize="none"
                spellcheck="false"
                class="min-h-11 rounded-md border border-slate-400 px-3 font-mono text-sm focus-visible:outline-2 focus-visible:outline-offset-2"
              />
            </label>
            <label class="grid gap-2 font-medium text-slate-800">
              Git branch
              <input
                name="project[default_branch]"
                value={@project["default_branch"]}
                required
                autocapitalize="none"
                spellcheck="false"
                class="min-h-11 rounded-md border border-slate-400 px-3 font-mono text-sm focus-visible:outline-2 focus-visible:outline-offset-2"
              />
            </label>
          </fieldset>
          <.wizard_actions step={@step} />
        </form>

        <form :if={@step == 3} id="project-step-3" phx-submit="next" class="space-y-6">
          <fieldset class="space-y-5 rounded-xl border border-slate-200 bg-white p-6">
            <legend class="px-2 text-lg font-semibold text-slate-950">Agent connection</legend>
            <p class="text-sm leading-6 text-slate-700">
              Start with one local agent connection. The same connection is assigned to each default role;
              assignments can be changed before work starts.
            </p>
            <label class="grid gap-2 font-medium text-slate-800">
              Runtime
              <select
                name="project[runtime]"
                class="min-h-11 rounded-md border border-slate-400 bg-white px-3 focus-visible:outline-2 focus-visible:outline-offset-2"
              >
                <option
                  :for={{label, value} <- @runtime_options}
                  value={value}
                  selected={@project["runtime"] == value}
                >
                  {label}
                </option>
              </select>
            </label>
            <label class="grid gap-2 font-medium text-slate-800">
              Runtime executable
              <input
                name="project[executable_path]"
                value={@project["executable_path"]}
                required
                placeholder="/absolute/path/to/codex"
                autocapitalize="none"
                spellcheck="false"
                class="min-h-11 rounded-md border border-slate-400 px-3 font-mono text-sm focus-visible:outline-2 focus-visible:outline-offset-2"
              />
            </label>
            <label class="grid gap-2 font-medium text-slate-800">
              Claude API-key helper
              <span class="text-sm font-normal text-slate-600">Required only for Claude Code</span>
              <input
                name="project[api_key_helper]"
                value={@project["api_key_helper"]}
                placeholder="/absolute/path/to/helper"
                autocapitalize="none"
                spellcheck="false"
                class="min-h-11 rounded-md border border-slate-400 px-3 font-mono text-sm focus-visible:outline-2 focus-visible:outline-offset-2"
              />
            </label>
          </fieldset>

          <section aria-labelledby="roles-heading" class="space-y-3">
            <div>
              <h2 id="roles-heading" class="text-lg font-semibold text-slate-950">Default roles</h2>
              <p class="text-sm text-slate-700">The board workflow will use these role snapshots.</p>
            </div>
            <ul class="grid gap-3 md:grid-cols-3">
              <li :for={role <- @roles} class="rounded-lg border border-slate-200 bg-white p-4">
                <h3 class="font-semibold text-slate-950">{role["name"]}</h3>
                <p class="mt-2 text-sm leading-6 text-slate-700">{role["instructions"]}</p>
              </li>
            </ul>
          </section>
          <.wizard_actions step={@step} />
        </form>

        <form :if={@step == 4} id="project-step-4" phx-submit="create" class="space-y-6">
          <section
            aria-labelledby="review-heading"
            class="space-y-5 rounded-xl border border-slate-200 bg-white p-6"
          >
            <h2 id="review-heading" class="text-lg font-semibold text-slate-950">Review project</h2>
            <dl class="grid gap-4 sm:grid-cols-2">
              <div>
                <dt class="text-sm text-slate-600">Name</dt><dd class="font-medium text-slate-950">
                  {@project["name"]}
                </dd>
              </div>
              <div>
                <dt class="text-sm text-slate-600">Branch</dt><dd class="font-mono text-sm text-slate-950">
                  {@project["default_branch"]}
                </dd>
              </div>
              <div class="sm:col-span-2">
                <dt class="text-sm text-slate-600">Repository</dt><dd class="break-all font-mono text-sm text-slate-950">
                  {@project["repo_path"]}
                </dd>
              </div>
              <div>
                <dt class="text-sm text-slate-600">Agent runtime</dt><dd class="font-medium text-slate-950">
                  {runtime_label(@runtime_options, @project["runtime"])}
                </dd>
              </div>
              <div>
                <dt class="text-sm text-slate-600">Roles</dt><dd class="font-medium text-slate-950">
                  Specifications, Coding, Review
                </dd>
              </div>
            </dl>
          </section>

          <.host_runner_notice />

          <label class="flex min-h-11 items-start gap-3 rounded-md border border-slate-200 bg-white p-4 font-medium text-slate-900">
            <input
              type="checkbox"
              name="project[confirmed]"
              value="true"
              checked={@project["confirmed"] == "true"}
              required
              class="mt-1"
            />
            I reviewed this repository and local runtime configuration. Add the project without starting agents or changing the repository.
          </label>

          <div class="flex flex-wrap items-center justify-between gap-3">
            <button
              type="button"
              phx-click="back"
              class="min-h-11 rounded-md border border-slate-400 bg-white px-5 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
            >
              Back
            </button>
            <button class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2">
              Add project
            </button>
          </div>
        </form>
      </section>
    </Layouts.app>
    """
  end

  attr :step, :integer, required: true

  defp wizard_actions(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-3">
      <button
        :if={@step > 1}
        type="button"
        phx-click="back"
        class="min-h-11 rounded-md border border-slate-400 bg-white px-5 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
      >
        Back
      </button>
      <span :if={@step == 1}></span>
      <button class="min-h-11 rounded-md bg-slate-950 px-5 font-medium text-white focus-visible:outline-2 focus-visible:outline-offset-2">
        Continue
      </button>
    </div>
    """
  end

  defp validate_step(1, project) do
    if String.trim(project["name"] || "") == "",
      do: {:error, :project_name_required},
      else: {:ok, %{"name" => String.trim(project["name"])}}
  end

  defp validate_step(2, project) do
    case ProjectOnboarding.validate_repository(project) do
      {:ok, {repo_path, _sha}} -> {:ok, %{"repo_path" => repo_path}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_step(3, project) do
    case RuntimeConfiguration.validate(project) do
      {:ok, _runtime} -> {:ok, %{}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp error_message(:project_name_required), do: "Enter a project name."
  defp error_message(:missing_directory), do: "That repository folder does not exist."
  defp error_message(:not_a_directory), do: "The repository path must point to a folder."
  defp error_message(:not_a_git_repository), do: "Choose the root folder of a Git repository."
  defp error_message(:invalid_repository_path), do: "Enter an absolute repository folder path."

  defp error_message(:repository_root_mismatch),
    do: "Choose the repository root, not a subfolder."

  defp error_message(:invalid_branch), do: "Enter a valid local Git branch name."

  defp error_message(:invalid_runtime_executable),
    do: "Choose an absolute path to an executable runtime."

  defp error_message(:unsupported_runtime), do: "Choose a supported agent runtime."

  defp error_message(%Ecto.Changeset{} = changeset) do
    "Project could not be added: #{inspect(changeset.errors)}"
  end

  defp error_message(reason), do: "Project could not be added: #{inspect(reason)}"

  defp runtime_label(options, value) do
    options
    |> Enum.find_value(value, fn {label, option} -> if option == value, do: label end)
  end
end
