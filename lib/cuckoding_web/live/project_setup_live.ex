defmodule CuckodingWeb.ProjectSetupLive do
  use CuckodingWeb, :live_view

  import CuckodingWeb.PolicyComponents

  alias Cuckoding.FolderPicker
  alias Cuckoding.ProjectOnboarding

  @steps ["Project", "Repository", "Review"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Add project",
       step: 1,
       steps: @steps,
       error: nil,
       project: %{
         "name" => "",
         "description" => "",
         "repo_path" => "",
         "default_branch" => "main",
         "repository_action" => nil,
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

  def handle_event("choose_folder", _params, socket) do
    case choose_folder() do
      {:ok, path} ->
        branch =
          ProjectOnboarding.suggested_branch(path, socket.assigns.project["default_branch"])

        {:noreply,
         assign(socket,
           project:
             Map.merge(socket.assigns.project, %{
               "repo_path" => path,
               "default_branch" => branch,
               "repository_action" => nil
             }),
           error: nil
         )}

      :cancelled ->
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, assign(socket, error: error_message(reason))}
    end
  end

  def handle_event("create", %{"project" => params}, socket) do
    project = Map.merge(socket.assigns.project, params)

    if project["confirmed"] == "true" do
      case ProjectOnboarding.create(project) do
        {:ok, %{project: created}} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "#{created.name} was added. Connect agents and assign their roles."
           )
           |> push_navigate(to: ~p"/projects/#{created.id}/edit")}

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
            Choose a project folder and review the registration.
            Setup does not create a board, task, branch, worktree, or running process.
          </p>
        </header>

        <nav aria-label="Project setup progress">
          <ol class="grid gap-2 sm:grid-cols-3">
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
              Choose an empty folder, an initialized Git folder, or an existing project. Cuckoding
              will prepare a local Git repository only after you confirm the review step.
            </p>
            <div class="grid gap-2 font-medium text-slate-800">
              <label for="project-repo-path">Repository folder</label>
              <div class="flex flex-col gap-3 sm:flex-row">
                <input
                  id="project-repo-path"
                  name="project[repo_path]"
                  value={@project["repo_path"]}
                  type="text"
                  required
                  readonly
                  placeholder="Choose a folder"
                  class="min-h-11 min-w-0 flex-1 rounded-md border border-slate-400 bg-slate-50 px-3 font-mono text-sm focus-visible:outline-2 focus-visible:outline-offset-2"
                />
                <button
                  id="choose-project-folder"
                  type="button"
                  phx-click="choose_folder"
                  class="min-h-11 rounded-md border border-slate-400 bg-white px-5 font-medium text-slate-950 focus-visible:outline-2 focus-visible:outline-offset-2"
                >
                  Choose folder…
                </button>
              </div>
            </div>
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

        <form :if={@step == 3} id="project-step-3" phx-submit="create" class="space-y-6">
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
              <div class="sm:col-span-2">
                <dt class="text-sm text-slate-600">Git setup</dt><dd class="font-medium text-slate-950">
                  {repository_action_label(@project["repository_action"])}
                </dd>
                <p
                  :if={@project["repository_action"] in ["initialize", "initial_commit"]}
                  class="mt-2 text-sm leading-6 text-amber-900"
                >
                  The initial commit includes every non-ignored file. Go back and review
                  <span class="font-mono">.gitignore</span>
                  before confirming.
                </p>
              </div>
              <div class="sm:col-span-2">
                <dt class="text-sm text-slate-600">Agents and roles</dt><dd class="font-medium text-slate-950">
                  Configure after registration on the project settings page
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
            /> I reviewed this folder. If needed, initialize Git and
            create an initial local commit from the folder contents. Do not start agents or create a run.
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
      {:ok, {repo_path, registration}} ->
        {:ok,
         %{
           "repo_path" => repo_path,
           "repository_action" => Atom.to_string(registration.action)
         }}

      {:error, reason} ->
        {:error, reason}
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
  defp error_message(:branch_not_found), do: "That local Git branch does not exist."
  defp error_message(:folder_picker_failed), do: "The system folder chooser could not be opened."

  defp error_message({:git_failed, _status, _output}),
    do:
      "Git could not prepare this folder. Review its files and Git configuration, then try again."

  defp error_message(%Ecto.Changeset{} = changeset) do
    "Project could not be added: #{inspect(changeset.errors)}"
  end

  defp error_message(reason), do: "Project could not be added: #{inspect(reason)}"

  defp repository_action_label("initialize"),
    do: "Initialize Git and create an initial local commit"

  defp repository_action_label("initial_commit"),
    do: "Create the first local commit in this Git repository"

  defp repository_action_label(_action), do: "Use the existing repository without changing it"

  defp choose_folder do
    case Application.get_env(:cuckoding, :folder_picker, FolderPicker) do
      picker when is_function(picker, 0) -> picker.()
      picker -> picker.choose()
    end
  end
end
