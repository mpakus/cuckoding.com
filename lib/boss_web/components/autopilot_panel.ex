defmodule BossWeb.AutopilotPanel do
  use BossWeb, :html

  def panel(assigns) do
    ~H"""
    <section
      id={@id}
      aria-labelledby="autopilot-heading"
      class="mt-5 min-w-0 border-t border-zinc-800 pt-4"
    >
      <div class="flex flex-wrap items-center gap-3">
        <h2 id="autopilot-heading" class="text-sm font-semibold">Autopilot</h2>
        <button
          id="open-autopilot"
          type="button"
          phx-target={@myself}
          phx-click="toggle"
          aria-expanded={to_string(@open)}
          aria-controls="autopilot-content"
          class="rounded border border-emerald-500 px-3 py-2 text-sm text-emerald-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
        >{if @open, do: "Hide controls", else: "Show controls"}</button>
        <span :if={@batch} id="autopilot-status" role="status" class="text-sm text-zinc-300">
          {label(@batch.status)}
        </span>
      </div>
      <p class="mt-2 text-xs text-zinc-400">
        <%= if @documentation do %>
          Autopilot plans tasks from committed documentation and code, then implements them in dependency order.
        <% else %>
          Current Backlog runs one task at a time through implementation, checks, fixes, review and integration.
        <% end %>
      </p>
      <div id="autopilot-content" hidden={!@open} class="mt-4 min-w-0 space-y-4">
        <p :if={!@supported} role="status" class="text-sm text-amber-300">
          Agent execution currently requires macOS.
        </p>
        <p :if={!@loaded && !@error} role="status" class="text-sm text-zinc-400">
          Loading Autopilot…
        </p>
        <div :if={@intake && @intake.status != "finished"} id="autopilot-intake" class="space-y-2">
          <p id="autopilot-intake-status" role="status" class="text-sm text-zinc-300">
            {if @intake.status == "planning",
              do: "Planning tasks from documentation…",
              else: label(@intake.status)}
          </p>
          <p
            :if={@intake.reason}
            id="autopilot-intake-reason"
            role="status"
            class="break-words text-sm text-amber-300"
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
            class="rounded border border-red-800 px-3 py-2 text-sm text-red-300 disabled:opacity-50"
          >Stop planning</button>
        </div>
        <p
          :if={match?(%{status: "finished", batch_id: nil}, @intake)}
          id="autopilot-intake-empty"
          role="status"
          class="text-sm text-zinc-300"
        >
          Planning found no outstanding tasks.
        </p>
        <div :if={@batch} id="autopilot-batch" class="min-w-0 space-y-3">
          <p class="text-sm text-zinc-300">
            Saved reviewer: {if @batch.reviewer == "claude", do: "Claude", else: "Codex"}
          </p>
          <code class="block break-all text-xs text-zinc-400">{JSON.encode!(
            @batch.check_config["argv"]
          )}</code>
          <p
            :if={@batch.reason}
            id="autopilot-reason"
            role="status"
            class="break-words text-sm text-amber-300"
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
                class="min-w-0 break-words text-emerald-300 underline underline-offset-4"
              >
                {item.position + 1}. {item.title}
              </.link>
              <span class="text-zinc-400">{label(item.delivery_status || item.request_status)}</span>
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
              class="rounded border border-zinc-600 px-3 py-2 text-sm disabled:opacity-50"
            >Pause Autopilot</button>
            <button
              :if={@batch.status == "paused"}
              id="resume-autopilot"
              type="button"
              phx-target={@myself}
              phx-click="resume"
              disabled={@pending != nil}
              class="rounded border border-zinc-600 px-3 py-2 text-sm disabled:opacity-50"
            >Resume Autopilot</button>
            <button
              id="stop-autopilot"
              type="button"
              phx-target={@myself}
              phx-click="cancel"
              disabled={@pending != nil}
              class="rounded border border-red-800 px-3 py-2 text-sm text-red-300 disabled:opacity-50"
            >Stop Autopilot</button>
          </div>
          <p :if={@batch.status in ["running", "paused"]} class="text-xs text-zinc-400">
            Pause lets the current workflow reach review approval, then prevents integration and the next task. Stop cancels active work and the remaining Backlog snapshot.
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
              {if @plans_from_docs, do: "Project documentation", else: "Current Backlog"}
            </legend>
            <p id="autopilot-selection-help" class="mt-1 text-xs text-zinc-400">
              <%= if @plans_from_docs do %>
                Codex will inspect the committed documentation and code. Autopilot saves the resulting tasks with their dependencies and begins the first ready task.
              <% else %>
                Start saves all current Backlog tasks (up to 256). Newly imported tasks stay outside this run.
                Dependencies must reach Done before their dependent task starts. Failed tasks need an explicit retry from their task details.
              <% end %>
            </p>
            <p
              :if={!@plans_from_docs}
              id="autopilot-selection-count"
              class="mt-2 text-sm text-zinc-300"
            >
              {length(@choices)} tasks in Backlog
            </p>
            <p
              :if={!@plans_from_docs && @choices == [] && !@documentation}
              class="mt-2 text-sm text-zinc-400"
            >
              No tasks in Backlog. Import a spec to start Autopilot.
            </p>
            <ul
              :if={!@plans_from_docs && @choices != []}
              class="mt-2 max-h-64 space-y-2 overflow-y-auto rounded border border-zinc-800 p-3"
            >
              <li
                :for={entry <- @choices}
                id={"autopilot-task-#{entry.task_id}"}
                class="min-w-0 break-words text-sm"
              >
                {entry.title}
                <span class="block break-all text-xs text-zinc-400">{entry.relative_path} · revision {entry.task_revision}</span>
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
              class="mt-1 w-full min-w-0 rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm"
            />
            <p id="autopilot-command-help" class="mt-1 text-xs text-zinc-400">
              Verify the command before starting. It runs without a shell before review and after integration.
            </p>
            <label for="autopilot-reviewer" class="mt-4 block text-sm font-medium">Independent reviewer</label>
            <select
              id="autopilot-reviewer"
              name="reviewer"
              class="mt-1 max-w-full rounded border border-zinc-600 bg-zinc-900 px-3 py-2 text-sm"
            >
              <option value="codex" selected={@reviewer == "codex"}>Codex</option>
              <option value="claude" selected={@reviewer == "claude"}>Claude</option>
            </select>
          </fieldset>
          <p id="autopilot-authorization" class="text-sm text-zinc-300">
            <%= if @plans_from_docs do %>
              Start authorizes project planning and execution of the generated tasks.
            <% else %>
              Start authorizes execution of the entire current Backlog.
            <% end %>
            Each task can use up to three repair cycles and integrates automatically into <strong class="break-all">{@project.base_branch}</strong>.
            A task reaches Done only after verified review, publication and postchecks. An unresolved failure stops Autopilot.
          </p>
          <p id="autopilot-provider-help" class="text-xs text-zinc-400">
            Codex plans and implements; the selected reviewer checks the result. Runs use your configured CLI accounts and may incur charges.
          </p>
          <p class="text-xs text-zinc-400">
            The target branch must not be checked out in your workspace. BOSS retains your checkout and failed work for inspection.
          </p>
          <button
            id="start-autopilot"
            type="submit"
            disabled={!@ready || (!@plans_from_docs && length(@choices) not in 1..256)}
            aria-describedby="autopilot-authorization"
            class="rounded bg-emerald-400 px-4 py-2 text-sm font-semibold text-zinc-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
          >Start Autopilot</button>
        </form>
        <p :if={@acting} role="status" class="text-sm text-zinc-400">Saving Autopilot request…</p>
        <p :if={@error} id="autopilot-error" role="alert" class="break-words text-sm text-amber-300">
          {@error}
        </p>
        <button
          :if={@pending && !@acting}
          id="retry-autopilot"
          type="button"
          phx-target={@myself}
          phx-click="retry"
          class="rounded border border-zinc-600 px-3 py-2 text-sm"
        >Retry saved request</button>
        <button
          :if={@error && !@pending}
          type="button"
          phx-target={@myself}
          phx-click="reload"
          class="rounded border border-zinc-600 px-3 py-2 text-sm"
        >Reload Autopilot</button>
      </div>
    </section>
    """
  end

  defp label("ready_to_merge"), do: "Awaiting integration"
  defp label("needs_input"), do: "Needs input"
  defp label("done"), do: "Done"
  defp label("blocked"), do: "Needs attention"
  defp label(value) when is_binary(value), do: String.capitalize(String.replace(value, "_", " "))
end
