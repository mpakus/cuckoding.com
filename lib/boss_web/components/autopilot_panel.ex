defmodule BossWeb.AutopilotPanel do
  use BossWeb, :html

  def panel(assigns) do
    assigns =
      assigns
      |> assign_new(:intake_attempts, fn -> [] end)
      |> assign_new(:interrupted_tasks, fn -> [] end)
      |> assign_new(:implementer_pool_size, fn -> 1 end)
      |> assign_new(:loop_cfg, fn -> nil end)
      |> assign_new(:spec_loop, fn -> true end)
      |> assign_new(:brief_selection, fn -> nil end)
      |> assign_new(:reviewer_tag, fn -> nil end)
      |> assign_new(:active_blocker, fn -> nil end)
      |> assign_new(:stopping_blocker, fn -> false end)

    assigns =
      assign(
        assigns,
        :replan_source,
        assigns.intake && Map.get(assigns.intake, :replan_source_id)
      )

    assigns = assign(assigns, :brief_task, assigns.intake && Map.get(assigns.intake, :brief_task))

    assigns =
      assign(
        assigns,
        :form_visible,
        assigns.loaded && !match?(%{status: "planning"}, assigns.intake) &&
          (is_nil(assigns.batch) || assigns.batch.status in ["blocked", "completed", "cancelled"])
      )

    ~H"""
    <section
      id={@id}
      aria-labelledby="autopilot-heading"
      class="min-w-0 rounded-lg border border-line bg-surface/85 px-3.5 py-2.5"
    >
      <div class="flex flex-wrap items-center gap-2.5">
        <div class="mr-auto flex flex-wrap items-center gap-2">
          <span
            class={[
              "inline-block h-2 w-2 rounded-full",
              if(@batch && @batch.status == "running",
                do: "board-live-dot",
                else: "bg-control-line"
              )
            ]}
            aria-hidden="true"
          ></span>
          <h2 id="autopilot-heading" class="text-xs font-semibold tracking-wide text-ink">
            Autopilot
          </h2>
          <span
            :if={@batch}
            id="autopilot-status"
            role="status"
            class={batch_status_badge_class(@batch.status)}
          >
            {label(@batch.status)}
          </span>
          <span
            :if={!@open && !@plans_from_docs && @loaded}
            class="font-mono text-[11px] text-muted"
          >
            {length(@choices)} ready
          </span>
          <span
            :if={@implementer_pool_size > 1}
            class="app-badge"
          >
            {@implementer_pool_size}× parallel
          </span>
          <span
            :if={@loop_cfg && @loop_cfg.spec_loop_enabled == 1}
            class="app-pill"
          >
            Loop {@loop_cfg.loop_pass}/{@loop_cfg.max_passes}
          </span>
        </div>

        <button
          id="open-autopilot"
          type="button"
          phx-target={@myself}
          phx-click="toggle"
          aria-expanded={to_string(@open)}
          aria-controls="autopilot-content"
          class="app-button-secondary min-h-7 px-2.5 py-1 text-xs"
        >{if @open, do: "Collapse", else: "Controls"}</button>
      </div>

      <div
        id="autopilot-content"
        hidden={!@open}
        class="mt-2.5 min-w-0 space-y-2.5 border-t border-line pt-2.5"
      >
        <p :if={!@supported} role="status" class="text-xs text-warning">
          Agent execution currently requires macOS.
        </p>
        <p :if={!@loaded && !@error} role="status" class="text-xs text-muted">
          Loading Autopilot…
        </p>

        <div
          :if={@intake && @intake.status != "finished"}
          id="autopilot-intake"
          class="flex flex-wrap items-center justify-between gap-2 rounded-md border border-line bg-paper px-3 py-2"
        >
          <div class="min-w-0 space-y-0.5">
            <p id="autopilot-intake-status" role="status" class="text-xs font-medium text-ink">
              {if @intake.status == "planning",
                do: "Planning tasks from documentation…",
                else: label(@intake.status)}
            </p>
            <p
              :if={@intake.reason}
              id="autopilot-intake-reason"
              role="status"
              class="break-words text-xs text-warning"
            >
              {@intake.reason}
            </p>
          </div>
          <button
            :if={@intake.status == "planning"}
            id="stop-autopilot-intake"
            type="button"
            phx-target={@myself}
            phx-click="stop_intake"
            disabled={@pending != nil}
            class="app-button-danger px-2.5 py-1 text-xs"
          >Stop planning</button>
        </div>

        <div
          :if={@intake_attempts != [] && !match?(%{status: "finished"}, @intake)}
          id="intake-attempt-history"
          class="rounded-md border border-line bg-paper px-3 py-2"
        >
          <h3 class="font-mono text-[11px] uppercase tracking-wider text-muted">Planning attempts</h3>
          <ol class="mt-1.5 space-y-1.5 text-xs">
            <li
              :for={attempt <- @intake_attempts}
              id={"intake-attempt-#{attempt.number}"}
              class="flex flex-wrap items-baseline justify-between gap-2"
            >
              <span class="font-mono text-ink">
                #{attempt.number} · {attempt.model_profile["model"]} · {label(attempt.status)}
              </span>
              <span class="text-muted">{attempt_reason(attempt)}</span>
            </li>
          </ol>
        </div>

        <p
          :if={match?(%{status: "finished", batch_id: nil}, @intake)}
          id="autopilot-intake-empty"
          role="status"
          class="text-xs text-muted"
        >
          Planning found no outstanding tasks.
        </p>

        <p :if={@brief_task} id="autopilot-brief-status" role="status" class="text-xs text-muted">
          Whole-brief acceptance
          <.link patch={~p"/projects/#{@project.id}/tasks/#{@brief_task.id}"} class="underline">
            {label(@brief_task.state)}
          </.link>
        </p>
        <form
          :if={@form_visible}
          id="autopilot-form"
          phx-target={@myself}
          phx-change="edit"
          phx-submit={if @replan_source, do: "replan", else: "start"}
          class="min-w-0 space-y-2.5"
        >
          <fieldset disabled={@pending != nil || !@supported} class="min-w-0 space-y-2.5">
            <input
              :if={@replan_source}
              type="hidden"
              name="previous_intake_id"
              value={@replan_source}
            />
            <legend class="sr-only">
              {if @plans_from_docs, do: "Project documentation", else: "Eligible unfinished tasks"}
            </legend>
            <p id="autopilot-selection-help" class="sr-only">
              <%= if @plans_from_docs do %>
                The Analytic role will inspect the committed documentation and code. Autopilot saves the resulting tasks with their dependencies and begins the first ready task.
              <% else %>
                A new Start saves all eligible New, Failed, Blocked and Needs input tasks (up to 256).
                Each receives a fresh workflow request; earlier batches and evidence stay unchanged.
              <% end %>
            </p>

            <div class="flex flex-wrap items-center gap-2">
              <button
                id="start-autopilot"
                type="submit"
                disabled={
                  !@ready || @active_blocker != nil || @stopping_blocker ||
                    (!@plans_from_docs && length(@choices) not in 1..256 && @interrupted_tasks == [])
                }
                aria-describedby="autopilot-authorization"
                class="app-button-primary px-4 py-1.5 text-xs font-semibold"
              >{if @replan_source, do: "Replan changed documentation", else: "Start Autopilot"}</button>

              <span
                :if={!@plans_from_docs}
                id="autopilot-selection-count"
                class="app-pill"
              >
                {length(@choices)} eligible unfinished tasks
              </span>

              <span
                id="autopilot-bound-reviewer"
                class="app-pill"
                title={"Verified by #{agent_name(@reviewer)} → #{@project.base_branch}"}
              >
                <span class="text-muted">Reviewer</span>
                <span class="font-semibold text-forest">{@reviewer_tag || agent_name(@reviewer)}</span>
                <span class="sr-only">{agent_name(@reviewer)}</span>
              </span>

              <div class="flex items-center gap-1.5">
                <label for="autopilot-spec-loop" class="sr-only">Reviewer spec-rework loop</label>
                <select
                  id="autopilot-spec-loop"
                  name="spec_loop"
                  class="app-field min-h-8 px-2.5 py-1 text-xs"
                >
                  <option value="true" selected={@spec_loop}>
                    Auto-loop (up to 2 passes)
                  </option>
                  <option value="false" selected={!@spec_loop}>
                    Single pass
                  </option>
                </select>
              </div>
            </div>

            <div
              :if={!@plans_from_docs && @interrupted_tasks != []}
              id="autopilot-interrupted-banner"
              class="flex flex-wrap items-center justify-between gap-2 rounded-md border border-warning-line bg-warning-soft px-3 py-2 text-xs text-warning"
            >
              <span>
                <strong>{length(@interrupted_tasks)} interrupted task(s)</strong>
                ({Enum.map_join(Enum.take(@interrupted_tasks, 2), ", ", & &1.title)}) can be recovered for Backlog dependencies.
              </span>
              <button
                id="recover-interrupted-autopilot"
                type="button"
                phx-target={@myself}
                phx-click="recover_interrupted"
                class="app-button-secondary px-2.5 py-1 text-xs"
              >
                Recover &amp; include ({length(@interrupted_tasks)})
              </button>
            </div>

            <p
              :if={!@plans_from_docs && @choices == [] && !@documentation}
              class="text-xs text-muted"
            >
              No eligible unfinished tasks. Import a spec or inspect tasks with unresolved work.
            </p>

            <div class="flex flex-wrap items-start gap-2">
              <details
                :if={!@plans_from_docs && @choices != []}
                class="app-disclosure-pill"
              >
                <summary>
                  <span>Selected tasks ({length(@choices)})</span>
                </summary>
                <ul class="mt-2 max-h-52 w-full max-w-xl space-y-1.5 overflow-y-auto rounded-lg border border-line bg-paper p-2.5 text-xs">
                  <li
                    :for={entry <- @choices}
                    id={"autopilot-task-#{entry.task_id}"}
                    class="flex flex-wrap items-baseline justify-between gap-2 border-b border-line/50 pb-1.5 last:border-b-0 last:pb-0"
                  >
                    <span class="font-medium text-ink">{entry.title}</span>
                    <span class="font-mono text-[11px] text-muted">
                      {if entry.state == "new", do: "New", else: "Retry · " <> label(entry.state)} · v{entry.task_revision}
                    </span>
                    <span class="sr-only">{entry.relative_path}</span>
                  </li>
                </ul>
              </details>

              <details
                id="autopilot-check-disclosure"
                open={@plans_from_docs || @text != ""}
                class="app-disclosure-pill"
              >
                <summary>
                  <span>CLI check {cond do
                    @text != "" -> "• set"
                    @plans_from_docs -> "(required)"
                    true -> "(optional)"
                  end}</span>
                </summary>
                <div class="mt-2 w-full max-w-md rounded-lg border border-line bg-paper p-2.5 text-xs">
                  <label for="autopilot-command" class="block font-medium text-body">
                    {cond do
                      @brief_selection -> "Saved executable check"
                      @plans_from_docs -> "Required executable check"
                      true -> "Optional CLI check command"
                    end}
                  </label>
                  <input
                    id="autopilot-command"
                    name="command"
                    type="text"
                    value={@text}
                    readonly={!!@brief_selection}
                    placeholder={
                      if @plans_from_docs, do: "e.g. python3 acceptance.py", else: "e.g. mix test"
                    }
                    maxlength="4096"
                    autocomplete="off"
                    aria-describedby="autopilot-command-help"
                    class="app-field mt-1 w-full min-w-0 px-2.5 py-1 font-mono text-xs"
                  />
                  <p id="autopilot-command-help" class="mt-1 text-[11px] text-muted">
                    <%= cond do %>
                      <% @brief_selection -> %>
                        This selection includes whole-brief acceptance. It uses the check and reviewer saved with the original documentation Start.
                      <% @plans_from_docs -> %>
                        Enter a trusted command that exercises the application. It runs on task candidates and at whole-brief acceptance.
                      <% true -> %>
                        Leave blank for Reviewer specification verification.
                    <% end %>
                  </p>
                </div>
              </details>

              <details
                id="autopilot-rules-disclosure"
                class="app-disclosure-pill"
              >
                <summary>
                  <span>Safety &amp; billing</span>
                </summary>
                <div class="mt-2 max-w-2xl space-y-1.5 rounded-lg border border-line bg-paper p-3 text-xs leading-5">
                  <p id="autopilot-authorization" class="text-body">
                    <%= if @plans_from_docs do %>
                      Start authorizes project planning and execution of the generated tasks.
                      Invalid plans can pass to another model for up to three planning attempts.
                    <% else %>
                      Start authorizes a new execution of the entire eligible unfinished selection, including retries of failed tasks.
                      It does not resume an earlier batch.
                    <% end %>
                    Start also authorizes automatic integration into <strong class="break-all text-forest">{@project.base_branch}</strong>.
                    A task reaches Done only after verified review, publication and postchecks.
                    Stop, unknown cleanup and integration failures halt the batch.
                  </p>
                  <p id="autopilot-provider-help" class="text-muted">
                    Runs use your configured CLI accounts and may incur charges. Keep the target branch unchecked in your working tree.
                  </p>
                </div>
              </details>

              <details
                :if={@intake_attempts != [] && match?(%{status: "finished"}, @intake)}
                id="intake-attempt-history"
                class="app-disclosure-pill"
              >
                <summary>
                  <span>Intake ({length(@intake_attempts)})</span>
                </summary>
                <ol class="mt-2 max-w-md space-y-1.5 rounded-lg border border-line bg-paper p-2.5 text-xs">
                  <li
                    :for={attempt <- @intake_attempts}
                    id={"intake-attempt-#{attempt.number}"}
                    class="flex flex-wrap items-baseline justify-between gap-2"
                  >
                    <span class="font-mono text-ink">
                      #{attempt.number} · {attempt.model_profile["model"]} · {label(attempt.status)}
                    </span>
                    <span class="text-muted">{attempt_reason(attempt)}</span>
                  </li>
                </ol>
              </details>
            </div>
          </fieldset>

          <div
            :if={@active_blocker != nil}
            id="autopilot-active-blocker"
            role="status"
            class="flex flex-wrap items-center justify-between gap-2.5 rounded-md border border-warning-line bg-warning-soft px-3 py-2 text-xs text-ink"
          >
            <%= case @active_blocker.kind do %>
              <% :project_delivery -> %>
                <span class="min-w-0">
                  Paused: <strong>{@active_blocker.task_title}</strong>
                  is {String.downcase(label(@active_blocker.status))}.
                </span>
                <div class="flex flex-wrap items-center gap-1.5">
                  <button
                    id="autopilot-stop-active-delivery"
                    type="button"
                    phx-target={@myself}
                    phx-click="stop_blocking_delivery"
                    phx-value-delivery-id={@active_blocker.delivery_id}
                    disabled={@acting || @stopping_blocker}
                    class="app-button-danger px-2.5 py-1 text-xs"
                  >
                    {if @stopping_blocker,
                      do: "Stopping…",
                      else: "Stop & include in Autopilot"}
                  </button>
                  <.link
                    patch={~p"/projects/#{@project.id}/tasks/#{@active_blocker.task_id}"}
                    class="app-button-secondary px-2.5 py-1 text-xs"
                  >
                    Inspect
                  </.link>
                </div>
              <% :other_project_delivery -> %>
                <span>
                  Unavailable while “{@active_blocker.task_title}” is active in “{@active_blocker.project_name}”.
                </span>
              <% :other_autopilot -> %>
                <span>
                  Unavailable while project “{@active_blocker.project_name}” has a {@active_blocker.status} Autopilot batch.
                </span>
              <% :manual_run -> %>
                <span>
                  Unavailable while manual run on “{@active_blocker.task_title}” is {@active_blocker.status}{if @active_blocker.cleanup ==
                                                                                                                  "unknown",
                                                                                                                do:
                                                                                                                  " (cleanup unconfirmed)",
                                                                                                                else:
                                                                                                                  ""}.
                </span>
              <% _ -> %>
                <span>
                  Unavailable until unconfirmed process cleanup from an interrupted run is inspected.
                </span>
            <% end %>
          </div>

          <p
            :if={@error}
            id="autopilot-error"
            role="alert"
            class="break-words rounded-md border border-warning-line bg-warning-soft px-3 py-2 text-xs text-warning"
          >
            {@error}
          </p>
        </form>

        <div
          :if={!@documentation}
          id="documentation-conversion"
          class="pt-0.5"
        >
          <details class="app-disclosure-pill">
            <summary>
              <span>Convert specs to docs mode</span>
            </summary>
            <div class="mt-2 flex flex-wrap items-center justify-between gap-2 rounded-lg border border-line bg-paper p-2.5 text-xs">
              <p id="documentation-conversion-help" class="max-w-xl text-muted">
                Seal imported files as planning reference history, then generate new tasks from documentation.
              </p>
              <button
                id="plan-from-documentation"
                type="button"
                phx-target={@myself}
                phx-click="plan_from_documentation"
                phx-value-command-id={@command}
                disabled={!@conversion_ready}
                aria-describedby="documentation-conversion-help"
                class="app-button-secondary px-3 py-1.5 text-xs"
              >Plan from documentation</button>
            </div>
          </details>
        </div>

        <%= if @batch && @batch.status in ["blocked", "completed", "cancelled"] && @form_visible do %>
          <details
            id="autopilot-batch"
            class="min-w-0 rounded-md border border-line bg-paper px-3 py-2"
          >
            <summary class="cursor-pointer font-mono text-xs text-muted hover:text-ink">
              Previous batch · {label(@batch.status)} ({length(@batch.items)} tasks)
            </summary>
            <div class="mt-2.5 min-w-0 space-y-3 border-t border-line pt-2.5">
              <.batch_body batch={@batch} project={@project} myself={@myself} pending={@pending} />
            </div>
          </details>
        <% else %>
          <div :if={@batch} id="autopilot-batch" class="min-w-0 space-y-3">
            <.batch_body batch={@batch} project={@project} myself={@myself} pending={@pending} />
          </div>
        <% end %>

        <p :if={@acting} role="status" class="text-xs text-muted">Saving Autopilot request…</p>
        <p
          :if={@error && !@form_visible}
          id="autopilot-error"
          role="alert"
          class="break-words rounded-md border border-warning-line bg-warning-soft px-3 py-2 text-xs text-warning"
        >
          {@error}
        </p>
        <button
          :if={@pending && !@acting}
          id="retry-autopilot"
          type="button"
          phx-target={@myself}
          phx-click="retry"
          class="app-button-secondary px-3 py-1.5 text-xs"
        >Retry saved request</button>
        <button
          :if={@error && !@pending}
          type="button"
          phx-target={@myself}
          phx-click="reload"
          class="app-button-secondary px-3 py-1.5 text-xs"
        >Reload Autopilot</button>
      </div>
    </section>
    """
  end

  defp batch_body(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between gap-2 rounded-md border border-line bg-paper px-3 py-2 text-xs">
      <div class="flex flex-wrap items-center gap-x-3 gap-y-1">
        <span class="font-medium text-ink">
          Reviewer: <span class="text-forest">{agent_name(@batch.reviewer)}</span>
        </span>
        <span class="text-muted">
          <%= if Boss.Checks.Command.spec_only?(@batch.check_config) do %>
            Spec check
          <% else %>
            <code class="font-mono text-body">{JSON.encode!(@batch.check_config["argv"])}</code>
          <% end %>
        </span>
      </div>
      <div class="flex flex-wrap items-center gap-2.5 font-mono text-[11px] text-muted">
        <span class="text-forest">active {batch_counts(@batch).active}</span>
        <span>done {batch_counts(@batch).done}</span>
        <span :if={batch_counts(@batch).failed > 0} class="text-warning">
          attn {batch_counts(@batch).failed}
        </span>
        <span>queued {batch_counts(@batch).waiting}</span>
      </div>
    </div>

    <div
      id="autopilot-flow"
      phx-hook="AutopilotFlowCanvas"
      data-flow={flow_payload(@batch, @project.id)}
      class="autopilot-dashboard space-y-2.5 rounded-lg border border-line bg-surface p-3"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <p class="app-eyebrow">Live pipeline telemetry</p>
        <div class="flex flex-wrap items-center gap-2.5 font-mono text-[10px] text-muted">
          <span class="inline-flex items-center gap-1">
            <span class="inline-block h-2 w-2 rounded-full bg-forest"></span>Active
          </span>
          <span class="inline-flex items-center gap-1">
            <span class="inline-block h-2 w-2 rounded-full border border-forest bg-sage"></span>Done
          </span>
          <span class="inline-flex items-center gap-1">
            <span class="inline-block h-2 w-2 rounded-full bg-warning"></span>Attention
          </span>
          <span class="inline-flex items-center gap-1">
            <span class="inline-block h-2 w-2 rounded-full bg-line"></span>Queued
          </span>
        </div>
      </div>

      <div
        id="autopilot-flow-canvas"
        data-flow-canvas
        phx-update="ignore"
        class="autopilot-canvas-host"
      >
      </div>

      <p
        id="autopilot-flow-readout"
        data-flow-readout
        class="min-h-4 truncate font-mono text-xs text-body"
      >
        {flow_summary(@batch)}
      </p>

      <ol aria-label="Workflow stages" class="grid grid-cols-2 gap-1.5 sm:grid-cols-6">
        <li
          :for={stage <- flow_stages(@batch)}
          data-state={stage.state}
          class="autopilot-node"
        >
          <span class="autopilot-node-mark" aria-hidden="true"></span>
          <span>{stage.label}</span>
        </li>
      </ol>

      <div aria-label="Tasks in this run" class="flex flex-wrap gap-1.5">
        <.link
          :for={item <- @batch.items}
          id={"autopilot-pixel-#{item.task_id}"}
          patch={~p"/projects/#{@project.id}/tasks/#{item.task_id}"}
          data-state={pixel_state(item.delivery_status || item.request_status)}
          title={pixel_title(item)}
          aria-label={"#{item.position + 1}. #{item.title}. #{pixel_title(item)}"}
          class="autopilot-pixel"
        >
          {item.position + 1}
        </.link>
      </div>
    </div>

    <p
      :if={@batch.reason}
      id="autopilot-reason"
      role="status"
      class="break-words rounded-md border border-warning-line bg-warning-soft px-3 py-2 text-xs text-warning"
    >
      {@batch.reason}
    </p>

    <details class="rounded-md border border-line bg-paper px-3 py-2 text-xs">
      <summary class="cursor-pointer font-mono text-muted hover:text-ink">
        Batch task manifest ({length(@batch.items)})
      </summary>
      <ol id="autopilot-items" class="mt-2 max-h-48 space-y-1.5 overflow-y-auto">
        <li
          :for={item <- @batch.items}
          id={"autopilot-item-#{item.task_id}"}
          class="flex flex-wrap items-baseline justify-between gap-2"
        >
          <.link
            patch={~p"/projects/#{@project.id}/tasks/#{item.task_id}"}
            class="min-w-0 break-words text-forest hover:underline"
          >
            {item.position + 1}. {item.title}
          </.link>
          <span class="font-mono text-[11px] text-muted">
            {label(item.delivery_status || item.request_status)}
          </span>
        </li>
      </ol>
    </details>

    <div :if={@batch.status in ["running", "paused"]} class="flex flex-wrap items-center gap-2">
      <button
        :if={@batch.status == "running"}
        id="pause-autopilot"
        type="button"
        phx-target={@myself}
        phx-click="pause"
        disabled={@pending != nil}
        class="app-button-secondary px-3 py-1.5 text-xs"
      >Pause Autopilot</button>
      <button
        :if={@batch.status == "paused"}
        id="resume-autopilot"
        type="button"
        phx-target={@myself}
        phx-click="resume"
        disabled={@pending != nil}
        class="app-button-primary px-3 py-1.5 text-xs"
      >Resume Autopilot</button>
      <button
        id="stop-autopilot"
        type="button"
        phx-target={@myself}
        phx-click="cancel"
        disabled={@pending != nil}
        class="app-button-danger px-3 py-1.5 text-xs"
      >Stop Autopilot</button>
    </div>
    """
  end

  defp attempt_reason(%{status: "running"}), do: "Planning from documentation…"
  defp attempt_reason(%{receipt: %{"validation_code" => "valid"}}), do: "Plan validated."

  defp attempt_reason(%{receipt: %{"error_class" => "rate_limit"}}),
    do: "Provider rate or quota limit."

  defp attempt_reason(%{receipt: %{"error_class" => "auth"}}),
    do: "Authentication rejected."

  defp attempt_reason(%{receipt: %{"error_class" => "model_unavailable"}}),
    do: "Selected model unavailable."

  defp attempt_reason(%{receipt: %{"error_class" => "schema"}}),
    do: "Structured schema rejected."

  defp attempt_reason(%{receipt: %{"error_class" => "transport"}}),
    do: "CLI transport failed."

  defp attempt_reason(%{receipt: %{"validation_code" => "report_too_large"} = r}) do
    case r["report_bytes"] do
      bytes when is_integer(bytes) -> "Plan exceeded the 32 KiB limit (#{bytes} bytes)."
      _ -> "Plan exceeded the 32 KiB limit."
    end
  end

  defp attempt_reason(%{receipt: %{"validation_code" => "task_limit"}}),
    do: "Plan exceeded 32-task limit."

  defp attempt_reason(%{receipt: %{"validation_code" => "dependency_cycle"}}),
    do: "Plan contained dependency cycle."

  defp attempt_reason(%{receipt: %{"validation_code" => code}}) when is_binary(code),
    do: "Invalid output (#{String.replace(code, "_", " ")})."

  defp attempt_reason(%{status: "cancelled"}), do: "Planning stopped."
  defp attempt_reason(%{status: "interrupted"}), do: "Cleanup needs verification."

  defp attempt_reason(%{receipt: %{"exit_code" => code}}) when is_integer(code) and code != 0,
    do: "CLI exited #{code}."

  defp attempt_reason(_), do: "Attempt incomplete."

  @flow [
    {"plan", "Plan"},
    {"resolve", "Diagnose"},
    {"implement", "Write"},
    {"check", "Check"},
    {"review", "Review"},
    {"publish", "Integrate"}
  ]

  defp flow_stages(batch) do
    items = Map.get(batch, :items, [])

    current =
      Enum.find(
        items,
        &(&1.delivery_status in ~w(planning implementing testing reviewing integrating))
      )

    marker = if current, do: status_stage(current.delivery_status), else: failed_stage(items)

    index_map = Map.new(Enum.with_index(@flow), fn {{id, _}, idx} -> {id, idx} end)
    active_index = Map.get(index_map, marker)

    Enum.map(@flow, fn {id, label} ->
      idx = Map.fetch!(index_map, id)

      state =
        cond do
          marker == id and current -> "current"
          marker == id -> "failed"
          current != nil and is_integer(active_index) and idx < active_index -> "done"
          batch.status == "completed" -> "done"
          true -> "waiting"
        end

      %{id: id, label: label, state: state}
    end)
  end

  defp status_stage("planning"), do: "plan"
  defp status_stage("implementing"), do: "implement"
  defp status_stage("testing"), do: "check"
  defp status_stage("reviewing"), do: "review"
  defp status_stage("integrating"), do: "publish"
  defp status_stage(_), do: nil

  defp failed_stage(items) do
    case Enum.find(items, &(&1.delivery_status == "failed")) do
      nil ->
        nil

      item ->
        item
        |> Map.get(:stages, [])
        |> Enum.reverse()
        |> Enum.find(&(&1.status == "failed"))
        |> case do
          %{kind: kind} -> kind
          _ -> "plan"
        end
    end
  end

  defp flow_summary(batch) do
    items = Map.get(batch, :items, [])
    failed = Enum.count(items, &(&1.delivery_status == "failed"))

    running =
      Enum.count(
        items,
        &(&1.delivery_status in ~w(planning implementing testing reviewing integrating))
      )

    cond do
      running > 0 -> "#{running} active workflow(s) in flight."
      failed > 0 -> "#{failed} task(s) halted — select a node to inspect."
      true -> "Select any task node to inspect stage telemetry."
    end
  end

  defp pixel_state(status) when status in ~w(planning implementing testing reviewing integrating),
    do: "current"

  defp pixel_state(status) when status in ~w(failed needs_input blocked), do: "failed"
  defp pixel_state(status) when status in ~w(done ready_to_merge), do: "done"
  defp pixel_state(_), do: "waiting"

  defp batch_counts(batch) do
    items = Map.get(batch, :items, [])

    Enum.reduce(items, %{active: 0, done: 0, failed: 0, waiting: 0}, fn item, acc ->
      case pixel_state(item.delivery_status || item.request_status) do
        "current" -> %{acc | active: acc.active + 1}
        "done" -> %{acc | done: acc.done + 1}
        "failed" -> %{acc | failed: acc.failed + 1}
        _ -> %{acc | waiting: acc.waiting + 1}
      end
    end)
  end

  defp flow_payload(batch, project_id) do
    stages = flow_stages(batch)

    items =
      for item <- Map.get(batch, :items, []) do
        status = item.delivery_status || item.request_status

        %{
          task_id: item.task_id,
          position: item.position,
          title: item.title,
          state: pixel_state(status),
          stage: item_stage(item),
          note: item_note(item),
          href: "/projects/#{project_id}/tasks/#{item.task_id}"
        }
      end

    JSON.encode!(%{
      status: batch.status,
      reviewer: batch.reviewer,
      stages: stages,
      items: items
    })
  end

  defp item_stage(item) do
    status = item.delivery_status || item.request_status

    cond do
      status in ~w(planning implementing testing reviewing integrating) ->
        status_stage(status) || "plan"

      status in ~w(done ready_to_merge) ->
        "publish"

      true ->
        item
        |> Map.get(:stages, [])
        |> Enum.reverse()
        |> Enum.find(&(&1.status in ["failed", "interrupted"]))
        |> case do
          %{kind: kind} when kind in ~w(plan resolve implement check review publish) -> kind
          %{kind: kind} when kind in ~w(merge merge_check merge_review post_check) -> "publish"
          _ -> "plan"
        end
    end
  end

  defp item_note(item) do
    item
    |> Map.get(:stages, [])
    |> Enum.reverse()
    |> Enum.find_value(fn stage ->
      text = Map.get(stage, :note)
      if is_binary(text) and String.trim(text) != "", do: String.trim(text)
    end)
  end

  defp pixel_title(item) do
    [item.delivery_status || item.request_status, item_note(item)]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(". ")
  end

  defp agent_name(id) do
    Enum.find_value(Boss.Agents.Metadata.catalog(), id, fn agent ->
      Atom.to_string(agent.id) == id && agent.name
    end)
  end

  defp batch_status_badge_class(status) when status in ["blocked", "needs_input"],
    do:
      "inline-flex items-center rounded-full border border-warning-line bg-warning-soft px-2 py-0.5 font-mono text-[11px] font-medium text-warning"

  defp batch_status_badge_class("cancelled"), do: "app-pill"
  defp batch_status_badge_class(_), do: "app-badge"

  defp label("ready_to_merge"), do: "Awaiting integration"
  defp label("needs_input"), do: "Needs input"
  defp label("done"), do: "Done"
  defp label("blocked"), do: "Needs attention"
  defp label(value) when is_binary(value), do: String.capitalize(String.replace(value, "_", " "))
end
