defmodule BossWeb.AutopilotPanel do
  use BossWeb, :html

  def panel(assigns) do
    assigns =
      assigns
      |> assign_new(:intake_attempts, fn -> [] end)
      |> assign_new(:reviewers, fn ->
        [%{id: "codex", name: "Codex"}, %{id: "claude", name: "Claude Code"}]
      end)

    ~H"""
    <section
      id={@id}
      aria-labelledby="autopilot-heading"
      class="min-w-0"
    >
      <div class="flex flex-wrap items-center gap-3">
        <h2 id="autopilot-heading" class="app-panel-heading mr-auto">Autopilot</h2>
        <button
          id="open-autopilot"
          type="button"
          phx-target={@myself}
          phx-click="toggle"
          aria-expanded={to_string(@open)}
          aria-controls="autopilot-content"
          class="app-button-secondary px-3 py-2 text-sm"
        >{if @open, do: "Hide controls", else: "Show controls"}</button>
        <span :if={@batch} id="autopilot-status" role="status" class="app-badge">
          {label(@batch.status)}
        </span>
      </div>
      <p class="mt-3 max-w-3xl text-sm leading-6 text-muted">
        <%= if @documentation do %>
          Autopilot plans tasks from committed documentation and code, then implements them in dependency order.
        <% else %>
          A new Start runs eligible unfinished tasks one at a time through implementation, checks, fixes, review and integration.
        <% end %>
      </p>
      <div
        id="autopilot-content"
        hidden={!@open}
        class="mt-5 min-w-0 space-y-4 border-t border-line pt-5"
      >
        <p :if={!@supported} role="status" class="text-sm text-warning">
          Agent execution currently requires macOS.
        </p>
        <p :if={!@loaded && !@error} role="status" class="text-sm text-muted">
          Loading Autopilot…
        </p>
        <div
          :if={!@documentation}
          id="documentation-conversion"
          class="space-y-2 border-b border-line pb-4"
        >
          <p id="documentation-conversion-help" class="max-w-3xl text-sm text-body">
            Imported instructions instead of implementation tasks? Use these documents as planning context.
            Existing tasks and attempts remain in reference history. Then Start Autopilot to generate a new plan.
          </p>
          <button
            id="plan-from-documentation"
            type="button"
            phx-target={@myself}
            phx-click="plan_from_documentation"
            phx-value-command-id={@command}
            disabled={!@conversion_ready}
            aria-describedby="documentation-conversion-help"
            class="app-button-secondary px-3 py-2 text-sm disabled:opacity-50"
          >Plan from documentation</button>
        </div>
        <div :if={@intake && @intake.status != "finished"} id="autopilot-intake" class="space-y-2">
          <p id="autopilot-intake-status" role="status" class="text-sm text-body">
            {if @intake.status == "planning",
              do: "Planning tasks from documentation…",
              else: label(@intake.status)}
          </p>
          <p
            :if={@intake.reason}
            id="autopilot-intake-reason"
            role="status"
            class="break-words text-sm text-warning"
          >
            {@intake.reason}
          </p>
          <button
            :if={@intake.status == "planning"}
            id="stop-autopilot-intake"
            type="button"
            phx-target={@myself}
            phx-click="stop_intake"
            disabled={@pending != nil}
            class="app-button-danger px-3 py-2 text-sm disabled:opacity-50"
          >Stop planning</button>
        </div>
        <div :if={@intake_attempts != []} id="intake-attempt-history" class="space-y-2">
          <h3 class="text-sm font-medium text-body">Planning attempts</h3>
          <ol class="space-y-2 text-sm">
            <li
              :for={attempt <- @intake_attempts}
              id={"intake-attempt-#{attempt.number}"}
              class="space-y-1"
            >
              <p class="break-words text-body">
                Attempt {attempt.number} · {attempt.model_profile["model"]} · {label(attempt.status)}
              </p>
              <p class="text-muted">{attempt_reason(attempt)}</p>
            </li>
          </ol>
        </div>
        <p
          :if={match?(%{status: "finished", batch_id: nil}, @intake)}
          id="autopilot-intake-empty"
          role="status"
          class="text-sm text-body"
        >
          Planning found no outstanding tasks.
        </p>
        <div :if={@batch} id="autopilot-batch" class="min-w-0 space-y-3">
          <p class="text-sm text-body">
            Saved reviewer: {agent_name(@batch.reviewer)}
          </p>
          <code class="block break-all text-xs text-muted">{JSON.encode!(@batch.check_config["argv"])}</code>
          <p
            :if={@batch.reason}
            id="autopilot-reason"
            role="status"
            class="break-words text-sm text-warning"
          >
            {@batch.reason}
          </p>
          <ol id="autopilot-items" class="max-h-64 space-y-2 overflow-y-auto text-sm">
            <li
              :for={item <- @batch.items}
              id={"autopilot-item-#{item.task_id}"}
              class="flex flex-wrap items-baseline gap-x-3 gap-y-1"
            >
              <.link
                patch={~p"/projects/#{@project.id}/tasks/#{item.task_id}"}
                class="min-w-0 break-words text-forest underline underline-offset-4"
              >
                {item.position + 1}. {item.title}
              </.link>
              <span class="text-muted">{label(item.delivery_status || item.request_status)}</span>
            </li>
          </ol>
          <div :if={@batch.status in ["running", "paused"]} class="flex flex-wrap gap-2">
            <button
              :if={@batch.status == "running"}
              id="pause-autopilot"
              type="button"
              phx-target={@myself}
              phx-click="pause"
              disabled={@pending != nil}
              class="app-button-secondary px-3 py-2 text-sm disabled:opacity-50"
            >Pause Autopilot</button>
            <button
              :if={@batch.status == "paused"}
              id="resume-autopilot"
              type="button"
              phx-target={@myself}
              phx-click="resume"
              disabled={@pending != nil}
              class="app-button-secondary px-3 py-2 text-sm disabled:opacity-50"
            >Resume Autopilot</button>
            <button
              id="stop-autopilot"
              type="button"
              phx-target={@myself}
              phx-click="cancel"
              disabled={@pending != nil}
              class="app-button-danger px-3 py-2 text-sm disabled:opacity-50"
            >Stop Autopilot</button>
          </div>
          <p :if={@batch.status in ["running", "paused"]} class="text-xs text-muted">
            Pause lets the current workflow reach review approval, then prevents integration and the next task. Stop cancels active work and the remaining saved selection.
            Restart pauses automatic work until you resume it.
          </p>
        </div>
        <form
          :if={
            @loaded && !match?(%{status: "planning"}, @intake) &&
              (is_nil(@batch) || @batch.status in ["blocked", "completed", "cancelled"])
          }
          id="autopilot-form"
          phx-target={@myself}
          phx-change="edit"
          phx-submit="start"
          class="min-w-0 space-y-4"
        >
          <fieldset disabled={@pending != nil || !@supported} class="min-w-0">
            <legend class="text-sm font-medium">
              {if @plans_from_docs, do: "Project documentation", else: "Eligible unfinished tasks"}
            </legend>
            <p id="autopilot-selection-help" class="mt-1 text-xs text-muted">
              <%= if @plans_from_docs do %>
                Codex will inspect the committed documentation and code. Autopilot saves the resulting tasks with their dependencies and begins the first ready task.
              <% else %>
                A new Start saves all eligible New, Failed, Blocked and Needs input tasks (up to 256).
                Each receives a fresh workflow request; earlier batches and evidence stay unchanged.
                Active work, unconfirmed cleanup and unresolved integration are excluded.
                Dependencies must reach Done before their dependent task starts. Later imports stay outside this run.
              <% end %>
            </p>
            <p
              :if={!@plans_from_docs}
              id="autopilot-selection-count"
              class="mt-2 text-sm text-body"
            >
              {length(@choices)} eligible unfinished tasks
            </p>
            <p
              :if={!@plans_from_docs && @choices == [] && !@documentation}
              class="mt-2 text-sm text-muted"
            >
              No eligible unfinished tasks. Import a spec or inspect tasks with unresolved work.
            </p>
            <ul
              :if={!@plans_from_docs && @choices != []}
              class="mt-2 max-h-64 space-y-2 overflow-y-auto rounded border border-line p-3"
            >
              <li
                :for={entry <- @choices}
                id={"autopilot-task-#{entry.task_id}"}
                class="min-w-0 break-words text-sm"
              >
                {entry.title}
                <span class="ml-2 text-xs text-muted">{if entry.state == "new",
                  do: "New",
                  else: "Retry · " <> label(entry.state)}</span>
                <span class="block break-all text-xs text-muted">{entry.relative_path} · revision {entry.task_revision}</span>
              </li>
            </ul>
            <label for="autopilot-command" class="mt-4 block text-sm font-medium">Check command for every task</label>
            <input
              id="autopilot-command"
              name="command"
              type="text"
              value={@text}
              placeholder="mix test"
              maxlength="4096"
              required
              autocomplete="off"
              aria-describedby="autopilot-command-help"
              class="app-field mt-1 w-full min-w-0 px-3 py-2 text-sm"
            />
            <p id="autopilot-command-help" class="mt-1 text-xs text-muted">
              Verify the command before starting. It runs without a shell before review and after integration.
            </p>
            <label for="autopilot-reviewer" class="mt-4 block text-sm font-medium">Independent reviewer</label>
            <select
              id="autopilot-reviewer"
              name="reviewer"
              class="app-field mt-1 max-w-full px-3 py-2 text-sm"
            >
              <option
                :for={agent <- @reviewers}
                value={agent.id}
                selected={@reviewer == agent.id}
              >
                {agent.name}
              </option>
            </select>
            <p id="autopilot-reviewer-help" class="mt-1 text-xs text-muted">
              <%= if Enum.any?(@reviewers, &(&1.id not in ~w(codex claude))) do %>
                The list is the agents assigned to Reviewer. Codex and Claude can run the review.
              <% else %>
                Assign agents to Reviewer on the Agents page to choose from that roster. Codex and Claude can run the review.
              <% end %>
            </p>
          </fieldset>
          <p
            id="autopilot-authorization"
            class="rounded-sm border border-line bg-sage/50 p-4 text-sm leading-6 text-body"
          >
            <%= if @plans_from_docs do %>
              Start authorizes project planning and execution of the generated tasks.
              Invalid plans can pass to another model for up to three planning attempts.
            <% else %>
              Start authorizes a new execution of the entire eligible unfinished selection, including retries of failed tasks.
              It does not resume an earlier batch.
            <% end %>
            Start also authorizes automatic integration into <strong class="break-all">{@project.base_branch}</strong>.
            New workflows resolve questions with another model and can use up to five implementation cycles.
            A task reaches Done only after verified review, publication and postchecks.
            Independent tasks can continue after a task-specific failure with confirmed cleanup.
            Shared model, catalog or provider failures stop the batch before another task starts.
            Stop, unknown cleanup and integration failures halt the batch.
          </p>
          <p id="autopilot-provider-help" class="text-xs text-muted">
            Codex plans and implements; the selected reviewer checks the result. Runs use your configured CLI accounts and may incur charges.
          </p>
          <p class="text-xs text-muted">
            The target branch must not be checked out in your workspace. BOSS retains your checkout and failed work for inspection.
          </p>
          <button
            id="start-autopilot"
            type="submit"
            disabled={!@ready || (!@plans_from_docs && length(@choices) not in 1..256)}
            aria-describedby="autopilot-authorization"
            class="app-button-primary px-4 py-2 text-sm font-semibold disabled:opacity-50"
          >Start Autopilot</button>
        </form>
        <p :if={@acting} role="status" class="text-sm text-muted">Saving Autopilot request…</p>
        <p :if={@error} id="autopilot-error" role="alert" class="break-words text-sm text-warning">
          {@error}
        </p>
        <button
          :if={@pending && !@acting}
          id="retry-autopilot"
          type="button"
          phx-target={@myself}
          phx-click="retry"
          class="app-button-secondary px-3 py-2 text-sm"
        >Retry saved request</button>
        <button
          :if={@error && !@pending}
          type="button"
          phx-target={@myself}
          phx-click="reload"
          class="app-button-secondary px-3 py-2 text-sm"
        >Reload Autopilot</button>
      </div>
    </section>
    """
  end

  defp attempt_reason(%{status: "running"}), do: "Planning from the saved documentation."
  defp attempt_reason(%{receipt: %{"validation_code" => "valid"}}), do: "Plan validated."

  defp attempt_reason(%{receipt: %{"validation_code" => "report_too_large"}}),
    do: "Plan exceeded the 32 KiB response limit."

  defp attempt_reason(%{receipt: %{"validation_code" => "task_limit"}}),
    do: "Plan exceeded the 32-task limit."

  defp attempt_reason(%{receipt: %{"validation_code" => "dependency_cycle"}}),
    do: "The planned tasks contained a dependency cycle."

  defp attempt_reason(%{receipt: %{"validation_code" => code}}) when is_binary(code),
    do: "Plan did not meet the required output contract."

  defp attempt_reason(%{status: "cancelled"}), do: "Planning stopped."
  defp attempt_reason(%{status: "interrupted"}), do: "Process cleanup needs verification."
  defp attempt_reason(_), do: "The model attempt could not complete."

  defp agent_name(id) do
    Enum.find_value(Boss.Agents.Metadata.catalog(), id, fn agent ->
      Atom.to_string(agent.id) == id && agent.name
    end)
  end

  defp label("ready_to_merge"), do: "Awaiting integration"
  defp label("needs_input"), do: "Needs input"
  defp label("done"), do: "Done"
  defp label("blocked"), do: "Needs attention"
  defp label(value) when is_binary(value), do: String.capitalize(String.replace(value, "_", " "))
end
