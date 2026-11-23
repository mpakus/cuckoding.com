defmodule BossWeb.TaskPrompt do
  use BossWeb, :live_component

  alias Boss.Agents.{Metadata, Roles}
  alias Boss.Projects.RoleBindings
  alias Boss.Projects.TaskPrompt, as: Engine
  alias Boss.Repo
  alias Phoenix.LiveView.JS

  @impl true
  def mount(socket) do
    agents = Roles.prompt_agent_choices()
    default_agent = Roles.default_prompt_agent(agents)
    models = Roles.models_for_agent(default_agent)

    {:ok,
     assign(socket,
       project: nil,
       supported: false,
       open: false,
       prompt: "",
       prompt_role: "analytic",
       agent: default_agent,
       agent_edited: false,
       agents: agents,
       model_id: default_model_for(default_agent, models, nil),
       model_edited: false,
       models: models,
       reviewer: resolve_reviewer(nil),
       reviewer_tag: nil,
       running: false,
       stopping: false,
       request_id: nil,
       error: nil,
       receipt: nil
     )}
  end

  @impl true
  def update(%{open: open}, socket) when is_boolean(open) do
    {:ok, assign(socket, open: open)}
  end

  def update(%{refresh_roles: true}, socket) do
    project_id = socket.assigns.project && socket.assigns.project.id
    {:ok, sync_agent_and_models(socket, project_id)}
  end

  def update(assigns, socket) do
    project = Map.get(assigns, :project, socket.assigns.project)
    project_id = project && project.id

    socket =
      socket
      |> assign(Map.take(assigns, [:id, :project, :supported]))
      |> sync_agent_and_models(project_id)

    {:ok, socket}
  end

  defp sync_agent_and_models(socket, project_id) do
    agents = Roles.prompt_agent_choices()

    agent =
      if !socket.assigns.agent_edited or socket.assigns.agent not in Enum.map(agents, & &1.id),
        do: Roles.default_prompt_agent(agents, project_id),
        else: socket.assigns.agent

    models = Roles.models_for_agent(agent)
    model_ids = Enum.map(models, & &1.id)

    model_id =
      cond do
        socket.assigns.model_edited and
            (socket.assigns.model_id == "__default__" or socket.assigns.model_id in model_ids) ->
          socket.assigns.model_id

        true ->
          default_model_for(agent, models, project_id)
      end

    reviewer = resolve_reviewer(project_id)

    reviewer_tag =
      if is_integer(project_id) and project_id > 0 do
        get_in(RoleBindings.for_project(project_id), ["reviewer", :active, :tag])
      end

    assign(socket,
      agents: agents,
      agent: agent,
      models: models,
      model_id: model_id,
      reviewer: reviewer,
      reviewer_tag: reviewer_tag
    )
  end

  @impl true
  def handle_event("open", _, socket) do
    {:noreply, assign(socket, open: true)}
  end

  def handle_event("close", _, socket) do
    {:noreply, assign(socket, open: false)}
  end

  def handle_event("toggle", _, socket) do
    {:noreply, assign(socket, open: !socket.assigns.open)}
  end

  def handle_event("edit", params, %{assigns: %{running: false}} = socket) do
    prompt = string_param(params, "prompt", socket.assigns.prompt)
    next_agent = string_param(params, "agent", socket.assigns.agent)
    agent_changed? = next_agent != socket.assigns.agent
    models = Roles.models_for_agent(next_agent)
    project_id = socket.assigns.project && socket.assigns.project.id

    next_model =
      if agent_changed? or params["_target"] == ["agent"] do
        default_model_for(next_agent, models, project_id)
      else
        string_param(params, "model_id", socket.assigns.model_id)
      end

    {:noreply,
     assign(socket,
       prompt: prompt,
       agent: next_agent,
       agent_edited: socket.assigns.agent_edited or Map.has_key?(params, "agent"),
       models: models,
       model_id: next_model,
       model_edited:
         (socket.assigns.model_edited and not agent_changed?) or Map.has_key?(params, "model_id"),
       reviewer: resolve_reviewer(project_id),
       error: nil
     )}
  end

  def handle_event("edit", _, socket), do: {:noreply, socket}

  def handle_event("clear_receipt", _, socket) do
    {:noreply, assign(socket, receipt: nil, error: nil)}
  end

  def handle_event("preset", %{"kind" => kind}, %{assigns: %{running: false}} = socket) do
    project_id = socket.assigns.project && socket.assigns.project.id
    roles_map = if project_id, do: RoleBindings.for_project(project_id), else: %{}

    {role_kind, text} =
      case kind do
        "reviewer_refine_docs" ->
          {"reviewer",
           "Audit the project's docs/ directory against current unfinished tasks: refine any ambiguous or blocked specifications with concrete acceptance criteria and return reworked tasks cleanly to Backlog so Autopilot can execute them."}

        _ ->
          {"analytic",
           "Analyze the project's docs/ directory and task checklist: decompose any missing milestones into ordered Backlog tasks with clean depends_on edges and measurable acceptance criteria, or enrich existing unfinished task specs for parallel Implementer execution."}
      end

    role_active = get_in(roles_map, [role_kind, :active])
    offered_ids = Enum.map(socket.assigns.agents, & &1.id)

    chosen_agent =
      if role_active && role_active.agent_id in offered_ids,
        do: role_active.agent_id,
        else: socket.assigns.agent

    models = Roles.models_for_agent(chosen_agent)
    model_ids = Enum.map(models, & &1.id)

    chosen_model =
      cond do
        role_active && is_binary(role_active.model_id) && role_active.model_id in model_ids ->
          role_active.model_id

        true ->
          default_model_for(chosen_agent, models, project_id)
      end

    {:noreply,
     assign(socket,
       open: true,
       prompt: text,
       prompt_role: role_kind,
       agent: chosen_agent,
       agent_edited: true,
       models: models,
       model_id: chosen_model,
       model_edited: true,
       error: nil
     )}
  end

  def handle_event("preset", _, socket), do: {:noreply, socket}

  def handle_event("submit", params, %{assigns: %{running: false}} = socket) do
    prompt = string_param(params, "prompt", socket.assigns.prompt)
    agent = string_param(params, "agent", socket.assigns.agent)
    models = Roles.models_for_agent(agent)
    model_id = string_param(params, "model_id", socket.assigns.model_id)
    project_id = socket.assigns.project && socket.assigns.project.id
    reviewer = string_param(params, "reviewer", resolve_reviewer(project_id))
    offered_agents = Enum.map(socket.assigns.agents, & &1.id)

    socket =
      assign(socket,
        prompt: prompt,
        agent: agent,
        agent_edited: true,
        models: models,
        model_id: model_id,
        model_edited: true,
        reviewer: reviewer
      )

    cond do
      is_nil(socket.assigns.project) ->
        {:noreply, assign(socket, error: Engine.message(:project_not_found))}

      not socket.assigns.supported ->
        {:noreply, assign(socket, error: "Agent execution currently requires macOS.")}

      String.trim(prompt) == "" or byte_size(prompt) > 8_000 ->
        {:noreply, assign(socket, error: Engine.message(:invalid_prompt))}

      agent not in offered_agents or not Metadata.execution_runner?(agent) ->
        {:noreply, assign(socket, error: Engine.message(:invalid_agent))}

      not Metadata.review_runner?(reviewer) ->
        {:noreply, assign(socket, error: Engine.message(:invalid_reviewer))}

      true ->
        request_id = Ecto.UUID.generate()
        repo = current_repo_pid()
        opts = runner_opts()
        chosen_model = Enum.find(models, &(&1.id == model_id))

        run_params = %{
          prompt: prompt,
          prompt_role: socket.assigns.prompt_role || "analytic",
          agent: agent,
          model_id: if(model_id in ["", "__default__"], do: nil, else: model_id),
          reasoning_effort: chosen_model && chosen_model.default_effort,
          check_command: "",
          reviewer: reviewer
        }

        {:noreply,
         socket
         |> assign(
           running: true,
           stopping: false,
           request_id: request_id,
           error: nil
         )
         |> start_async({:prompt_run, request_id}, fn ->
           if is_pid(repo), do: Repo.put_dynamic_repo(repo)
           Engine.run(project_id, request_id, run_params, opts)
         end)}
    end
  end

  def handle_event("submit", _, socket), do: {:noreply, socket}

  def handle_event(
        "stop",
        _,
        %{assigns: %{running: true, request_id: request_id, project: %{id: project_id}}} = socket
      )
      when is_binary(request_id) do
    Engine.stop(project_id, request_id)
    {:noreply, assign(socket, stopping: true)}
  end

  def handle_event("stop", _, socket), do: {:noreply, socket}

  @impl true
  def handle_async(
        {:prompt_run, request_id},
        {:ok, result},
        %{assigns: %{request_id: request_id}} = socket
      ) do
    case result do
      {:ok, receipt} ->
        if socket.assigns.project do
          send(self(), {:prompt_tasks_updated, socket.assigns.project.id})
        end

        {:noreply,
         assign(socket,
           running: false,
           stopping: false,
           request_id: nil,
           prompt: "",
           error: nil,
           receipt: receipt
         )}

      {:error, reason} ->
        {:noreply,
         assign(socket,
           running: false,
           stopping: false,
           request_id: nil,
           error: Engine.message(reason)
         )}
    end
  end

  def handle_async(
        {:prompt_run, request_id},
        _exit,
        %{assigns: %{request_id: request_id}} = socket
      ) do
    {:noreply,
     assign(socket,
       running: false,
       stopping: false,
       request_id: nil,
       error: Engine.message(:invalid_report)
     )}
  end

  def handle_async(_, _, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    agent_name =
      Enum.find_value(assigns.agents, assigns.agent, fn a ->
        if a.id == assigns.agent, do: a.name
      end)

    model_label =
      case Enum.find(assigns.models, &(&1.id == assigns.model_id)) do
        %{name: name} -> " · #{name}"
        _ -> ""
      end

    reviewer_label = assigns.reviewer_tag || Roles.agent_label(assigns.reviewer)

    assigns =
      assigns
      |> assign(:agent_name, agent_name)
      |> assign(:model_label, model_label)
      |> assign(:reviewer_label, reviewer_label)

    ~H"""
    <div id={@id} class="flex flex-wrap items-center gap-2">
      <button
        id="open-task-prompt"
        type="button"
        phx-target={@myself}
        phx-click="open"
        aria-haspopup="dialog"
        aria-expanded={to_string(@open)}
        class="app-button-secondary shrink-0 px-4 py-3 font-semibold"
      >
        <span>Prompt task control</span>
        <span
          :if={!@running && @error}
          class="rounded bg-danger-soft px-1.5 py-0.5 text-[11px] font-semibold text-danger"
        >
          Error
        </span>
        <span
          :if={!@running && is_nil(@error) && @receipt}
          class="rounded bg-sage px-1.5 py-0.5 text-[11px] font-semibold text-forest"
        >
          Applied
        </span>
      </button>

      <span :if={@running && !@open} id="task-prompt-running" role="status" class="app-badge">
        {if @stopping, do: "Stopping…", else: "Running #{@agent_name}#{@model_label}…"}
      </span>
      <button
        :if={@running && !@open}
        id="task-prompt-toolbar-stop"
        type="button"
        phx-target={@myself}
        phx-click="stop"
        disabled={@stopping}
        class="app-button-danger shrink-0 px-3 py-2 text-xs font-semibold"
      >
        {if @stopping, do: "Stopping…", else: "Stop"}
      </button>

      <dialog
        :if={@open}
        id="task-prompt-dialog"
        phx-hook="DialogModal"
        phx-mounted={JS.ignore_attributes("open")}
        data-return-focus="open-task-prompt"
        aria-labelledby="task-prompt-heading"
        class="app-modal sm:max-w-2xl open:flex open:flex-col"
      >
        <div class="flex shrink-0 items-start justify-between gap-4 border-b border-line bg-surface px-5 py-4 sm:px-6">
          <div class="min-w-0">
            <div class="flex flex-wrap items-center gap-2">
              <p class="app-eyebrow">Natural-language workspace control</p>
              <span :if={@running} id="task-prompt-running" role="status" class="app-badge">
                {if @stopping, do: "Stopping…", else: "Running #{@agent_name}#{@model_label}…"}
              </span>
            </div>
            <h2 id="task-prompt-heading" class="mt-1 text-lg font-semibold text-ink">
              Prompt task control
            </h2>
            <p class="mt-1 text-xs text-muted">
              Create tasks, enrich specifications, leave task notes, or start and queue workflows with your selected Agent + Model.
            </p>
          </div>
          <button
            id="close-task-prompt"
            data-modal-close
            type="button"
            phx-target={@myself}
            phx-click="close"
            autofocus
            class="app-button-secondary shrink-0 px-3 py-2 text-xs"
          >
            Close
          </button>
        </div>

        <div
          id="task-prompt-content"
          class="min-h-0 flex-1 space-y-4 overflow-y-auto px-5 py-5 sm:px-6"
        >
          <p :if={!@supported} role="status" class="text-sm text-warning">
            Agent execution currently requires macOS.
          </p>

          <div class="flex flex-wrap items-center gap-2">
            <span class="text-[11px] font-semibold uppercase tracking-wider text-muted">
              Quick docs/ actions:
            </span>
            <button
              id="preset-analytic-parse-docs"
              type="button"
              phx-target={@myself}
              phx-click="preset"
              phx-value-kind="analytic_parse_docs"
              disabled={@running}
              class="app-button-secondary px-2.5 py-1 text-xs"
            >
              Parse docs/ into tasks (Analytic)
            </button>
            <button
              id="preset-reviewer-refine-docs"
              type="button"
              phx-target={@myself}
              phx-click="preset"
              phx-value-kind="reviewer_refine_docs"
              disabled={@running}
              class="app-button-secondary px-2.5 py-1 text-xs"
            >
              Audit docs/ &amp; refine specs (Reviewer)
            </button>
          </div>

          <form
            id="task-prompt-form"
            phx-target={@myself}
            phx-change="edit"
            phx-submit="submit"
            class="space-y-3"
          >
            <div>
              <label for="task-prompt-input" class="block text-xs font-medium text-ink">
                Instruction or new task prompt
              </label>
              <textarea
                id="task-prompt-input"
                name="prompt"
                rows="3"
                maxlength="8000"
                disabled={@running || !@supported}
                placeholder="e.g. Create a task to add webhook signature verification, add clarification notes to m3-seo, or queue m1-auth."
                class="app-field mt-1 w-full resize-y text-sm"
              >{@prompt}</textarea>
            </div>

            <div class="grid min-w-0 gap-3 sm:grid-cols-2">
              <div class="min-w-0">
                <label for="task-prompt-agent" class="block text-xs font-medium text-muted">
                  Prompt agent
                </label>
                <select
                  id="task-prompt-agent"
                  name="agent"
                  disabled={@running || !@supported}
                  class="app-field mt-1 w-full text-xs"
                >
                  <option
                    :for={choice <- @agents}
                    value={choice.id}
                    selected={choice.id == @agent}
                  >
                    {choice.name}
                  </option>
                </select>
              </div>

              <div class="min-w-0">
                <label for="task-prompt-model" class="block text-xs font-medium text-muted">
                  Agent model
                </label>
                <select
                  id="task-prompt-model"
                  name="model_id"
                  disabled={@running || !@supported}
                  class="app-field mt-1 w-full text-xs"
                >
                  <option value="__default__" selected={@model_id in [nil, "", "__default__"]}>
                    CLI default model
                  </option>
                  <option
                    :for={m <- @models}
                    value={m.id}
                    selected={m.id == @model_id}
                  >
                    {m.name} · {m.billing_label} ({m.price_label})
                  </option>
                </select>
              </div>
            </div>

            <div class="flex flex-wrap items-center gap-3">
              <button
                id="task-prompt-submit"
                type="submit"
                disabled={@running || !@supported || String.trim(@prompt) == ""}
                class="app-button-primary px-4 py-2 text-xs font-semibold"
              >
                {if @running, do: "Running prompt…", else: "Run prompt"}
              </button>
              <button
                :if={@running}
                id="task-prompt-stop"
                type="button"
                phx-target={@myself}
                phx-click="stop"
                disabled={@stopping}
                class="app-button-danger px-3.5 py-2 text-xs font-semibold"
              >
                {if @stopping, do: "Stopping…", else: "Stop"}
              </button>
              <span class="text-xs text-muted">
                Started workflows verify against specs via <strong class="font-mono text-forest">{@reviewer_label}</strong>.
              </span>
            </div>
          </form>

          <p
            :if={@error}
            id="task-prompt-error"
            role="alert"
            class="rounded-sm border border-danger-line bg-danger-soft px-3 py-2 text-xs text-danger"
          >
            {@error}
          </p>

          <div
            :if={@receipt}
            id="task-prompt-receipt"
            role="status"
            class="space-y-2.5 rounded-sm border border-line bg-surface p-3.5 text-sm"
          >
            <div class="flex flex-wrap items-start justify-between gap-3">
              <p id="task-prompt-summary" class="min-w-0 flex-1 whitespace-pre-line text-ink">
                {@receipt.summary}
              </p>
              <button
                id="task-prompt-dismiss"
                type="button"
                phx-target={@myself}
                phx-click="clear_receipt"
                class="text-xs text-muted underline underline-offset-4 hover:text-ink"
              >Dismiss</button>
            </div>

            <ul
              :if={@receipt.results != []}
              id="task-prompt-results"
              class="space-y-1.5 border-t border-line pt-2.5 text-xs"
            >
              <li
                :for={{item, idx} <- Enum.with_index(@receipt.results)}
                id={"task-prompt-result-#{idx}"}
                class="flex flex-wrap items-baseline gap-x-2 gap-y-1"
              >
                <span class={[
                  "rounded px-1.5 py-0.5 text-[11px] font-semibold",
                  if(item.status == :applied,
                    do: "bg-sage text-ink",
                    else: "bg-warning-soft text-warning"
                  )
                ]}>
                  {op_label(item.op)}
                </span>
                <%= if is_integer(item.task_id) and @project do %>
                  <.link
                    patch={~p"/projects/#{@project.id}/tasks/#{item.task_id}"}
                    class="font-medium text-forest underline underline-offset-4"
                  >{item.title}</.link>
                <% else %>
                  <span :if={item.title != ""} class="font-medium text-ink">{item.title}</span>
                <% end %>
                <span class="text-muted">— {item.detail}</span>
              </li>
            </ul>
          </div>
        </div>
      </dialog>
    </div>
    """
  end

  defp op_label("create_task"), do: "Created"
  defp op_label("update_task_spec"), do: "Updated spec"
  defp op_label("add_task_note"), do: "Note added"
  defp op_label("block_task"), do: "Blocked"
  defp op_label("needs_input_task"), do: "Needs input"
  defp op_label("cancel_task"), do: "Cancelled"
  defp op_label("resume_task"), do: "Resumed"
  defp op_label("retry_task"), do: "Reset"
  defp op_label("start_workflow"), do: "Started workflow"
  defp op_label("queue_workflow"), do: "Queued workflow"
  defp op_label("cancel_queued_workflow"), do: "Cancelled queue"
  defp op_label("stop_workflow"), do: "Stopped workflow"
  defp op_label(other), do: other

  defp default_model_for(agent, models, project_id) do
    sel = Roles.selection_for("analytic", agent, project_id)
    ids = Enum.map(models, & &1.id)

    cond do
      is_binary(sel.model_id) and sel.model_id in ids -> sel.model_id
      models != [] -> hd(models).id
      true -> "__default__"
    end
  end

  defp resolve_reviewer(project_id) when is_integer(project_id) and project_id > 0 do
    RoleBindings.reviewer_agent(project_id)
  end

  defp resolve_reviewer(_) do
    case Roles.reviewer_choices() do
      [%{id: id} | _] -> id
      _ -> "codex"
    end
  end

  defp string_param(params, key, default) do
    case Map.get(params, key) do
      value when is_binary(value) -> value
      _ -> default
    end
  end

  defp current_repo_pid do
    case Repo.get_dynamic_repo() do
      atom when is_atom(atom) -> Process.whereis(atom)
      pid when is_pid(pid) -> pid
      _ -> nil
    end
  end

  defp runner_opts do
    case Application.get_env(:boss, :task_prompt_runner) do
      fun when is_function(fun, 4) or is_function(fun, 5) -> [runner: fun]
      _ -> []
    end
  end
end
