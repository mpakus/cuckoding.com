defmodule BossWeb.DeliveryPanel do
  use BossWeb, :html

  @active ~w(planning implementing testing reviewing integrating)
  attr :details, :map, required: true
  attr :deliveries, :list, required: true
  attr :scope_blockers, :map, default: %{}
  attr :request, :map, required: true
  attr :queued_workflows, :list, default: []
  attr :queue_actions, :map, default: %{}
  attr :queue_starting, :any, default: nil
  attr :queue_error, :any, default: nil
  attr :queue_available, :boolean, default: false
  attr :queue_controls_available, :boolean, default: true
  attr :integration_requests, :map, required: true
  attr :start_available, :boolean, required: true
  attr :integrate_available, :boolean, required: true
  attr :uncertain, :boolean, required: true
  attr :starting, :any, default: nil
  attr :stopping, :any, default: nil
  attr :error, :any, default: nil
  attr :supported, :boolean, required: true

  def panel(assigns) do
    ~H"""
    <section
      id="task-deliveries"
      aria-labelledby="task-deliveries-heading"
      class="min-w-0 border-t border-line pt-5"
    >
      <h3 id="task-deliveries-heading" class="app-panel-heading">Task workflow</h3>
      <p id="delivery-help" class="mt-3 text-sm leading-6 text-body">
        Plan, implement, check and review task snapshot revision {@details.pinned_revision.number}.
        The Implementer role plans and writes the code. The Analytic role answers questions when work is stuck.
        New workflows can use up to five implementation/check/review cycles.
        An approved result waits for you to integrate it.
      </p>
      <p id="delivery-account" class="mt-3 text-xs leading-5 text-muted">
        Uses the Implementer and Analytic accounts you assigned, and the selected reviewer's account for review.
        These calls may incur charges for multiple runs.
        Source, plans, diffs, check output and prior feedback are sent to the selected agents.
        Closing this drawer keeps the workflow active.
      </p>
      <p
        id="delivery-queue-help"
        class="mt-3 border-l-2 border-line pl-3 text-xs leading-5 text-muted"
      >
        Queue a workflow to start when its prerequisites are Done and capacity is available.
        Workflow capacity is shared across projects. Known overlapping file predictions wait before implementation.
        Unknown or incomplete predictions can still cause conflicts.
        Queued work pauses after restart and needs Resume. Source changes require explicit adoption.
        If the target advances, integration checks and reviews a new merge candidate before publication.
      </p>
      <p :if={!@supported} class="mt-3 text-sm text-warning">
        Task workflows currently require macOS.
      </p>
      <form
        :if={@details.task.state in ~w(new failed interrupted cancelled blocked needs_input)}
        id="delivery-form"
        phx-change="edit_delivery"
        phx-submit="start_delivery"
        class="mt-5 space-y-2 rounded-sm border border-line bg-surface p-4"
      >
        <input type="hidden" name="command_id" value={@request.id} />
        <label for="delivery-reviewer" class="block text-sm font-medium">Workflow reviewer</label>
        <select
          id="delivery-reviewer"
          name="reviewer"
          disabled={(!@start_available && !@queue_available) || @request.locked}
          aria-describedby="delivery-reviewer-help delivery-account"
          class="app-field w-full min-w-0 px-3 py-2 text-sm disabled:opacity-50"
        >
          <option
            :for={agent <- Boss.Agents.Roles.reviewer_choices()}
            value={agent.id}
            selected={@request.reviewer == agent.id}
          >
            {agent.name}
          </option>
        </select>
        <input :if={@request.locked} type="hidden" name="reviewer" value={@request.reviewer} />
        <p id="delivery-reviewer-help" class="text-xs text-muted">
          <%= if @request.reviewer == "claude" do %>
            Claude reviews the supplied spec, plan, full diff, check output and prior feedback.
            It has no model filesystem or shell tools. The Implementer role plans and writes the code.
          <% else %>
            <%= if @request.reviewer == "cursor" do %>
              Cursor Agent reviews the supplied evidence in ask mode and does not write the candidate.
            <% else %>
              Codex reviews the supplied evidence and can inspect the candidate's source read-only.
            <% end %>
          <% end %>
        </p>
        <label for="delivery-command" class="block pt-3 text-sm font-medium">Workflow check command</label>
        <input
          id="delivery-command"
          name="command"
          value={@request.text}
          required
          maxlength="4096"
          readonly={@request.locked}
          disabled={!@start_available && !@queue_available}
          autocomplete="off"
          spellcheck="false"
          placeholder="mix test"
          aria-describedby="delivery-command-help delivery-account"
          class="app-field w-full min-w-0 px-3 py-2 font-mono text-sm"
        />
        <p id="delivery-command-help" class="text-xs text-muted">
          Use a trusted command. It runs locally on each candidate and after integration.
          Arguments support quoting, without shell expansion. Keep secrets out of arguments and output.
        </p>
        <div class="flex flex-wrap gap-2 pt-2">
          <button
            id="start-delivery"
            type="submit"
            name="intent"
            value="start"
            disabled={!@start_available}
            aria-describedby="delivery-help delivery-account"
            class="app-button-primary px-4 py-2 font-semibold disabled:opacity-50"
          >{cond do
            @starting && Map.get(@request, :action, :start) == :start -> "Starting workflow…"
            @request.locked && Map.get(@request, :action, :start) == :start -> "Retry workflow start"
            true -> "Start workflow"
          end}</button>
          <button
            id="queue-delivery"
            type="submit"
            name="intent"
            value="queue"
            disabled={!@queue_available}
            aria-describedby="delivery-queue-help delivery-account"
            class="app-button-secondary px-4 py-2 font-semibold disabled:opacity-50"
          >{cond do
            @starting && Map.get(@request, :action) == :queue -> "Adding to queue…"
            @request.locked && Map.get(@request, :action) == :queue -> "Retry queue request"
            true -> "Queue workflow"
          end}</button>
        </div>
      </form>
      <p
        :if={@uncertain && is_nil(@starting)}
        id="delivery-request-pending"
        role="status"
        class="mt-3 text-sm text-warning"
      >
        A workflow request is unresolved. Retry its saved request on the original task before starting other work.
      </p>
      <p :if={@error} id="delivery-error" role="alert" class="mt-3 text-sm text-danger">{@error}</p>
      <section
        :if={@queued_workflows != []}
        id="workflow-queue"
        aria-label="Workflow queue"
        class="mt-4"
      >
        <h4 class="text-sm font-semibold">Workflow queue</h4>
        <p :if={@queue_error} id="queue-error" role="alert" class="mt-2 text-sm text-danger">
          {@queue_error}
        </p>
        <ol class="divide-y divide-line">
          <li
            :for={request <- @queued_workflows}
            id={"queued-workflow-#{request.id}"}
            class="space-y-2 py-3 text-sm"
          >
            <p role="status" class="font-medium">{queue_status(request.status)}</p>
            <p :if={request.status == "queued"} class="text-xs text-muted">
              Waiting for prerequisites to be Done and available workflow capacity.
            </p>
            <p :if={request.status == "paused"} class="text-xs text-muted">
              Resume uses the saved source, reviewer and command. It does not adopt newer source.
            </p>
            <p class="text-xs text-muted">
              Source revision {BossWeb.TaskRevision.number(@details, request.spec_revision_id)}
              <span :if={request.spec_revision_id != @details.pinned_revision.id}> · historical snapshot</span>
              · Reviewer: {reviewer(request.reviewer)}
            </p>
            <p class="text-xs text-muted">
              Saved check command
              <code class="block break-all text-body">{JSON.encode!(request.check_config["argv"])}</code>
            </p>
            <p :if={request.reason} class="whitespace-pre-wrap break-words text-warning">
              {request.reason}
            </p>
            <div :if={request.status in ~w(queued paused)} class="flex flex-wrap gap-2">
              <button
                :if={request.status == "paused"}
                id={"resume-queue-#{request.id}"}
                type="button"
                phx-click="resume_queue"
                phx-value-queue-id={request.id}
                disabled={
                  !@supported || !@queue_controls_available || @queue_starting != nil ||
                    (@uncertain && @queue_actions[request.id] != :resume)
                }
                class="app-button-secondary px-3 py-2 disabled:opacity-50"
              >{if @queue_actions[request.id] == :resume, do: "Retry Resume", else: "Resume"}</button>
              <button
                id={"cancel-queue-#{request.id}"}
                type="button"
                phx-click="cancel_queue"
                phx-value-queue-id={request.id}
                disabled={
                  !@queue_controls_available || @queue_starting != nil ||
                    (@uncertain && @queue_actions[request.id] != :cancel)
                }
                class="app-button-danger px-3 py-2 disabled:opacity-50"
              >{if @queue_actions[request.id] == :cancel, do: "Retry Cancel", else: "Cancel queue"}</button>
            </div>
            <p :if={request.status == "started"} class="text-xs text-muted">
              This request started a workflow. Active workflows can be stopped below.
            </p>
          </li>
        </ol>
      </section>
      <p :if={@deliveries == []} class="mt-4 text-sm text-muted">No workflows yet.</p>
      <ol id="delivery-attempts" class="mt-3 divide-y divide-line">
        <li
          :for={delivery <- @deliveries}
          id={"delivery-#{delivery.id}"}
          class="space-y-3 py-4 text-sm"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <p role="status" class="font-medium">
              {if Map.get(@scope_blockers, delivery.id, []) != [],
                do: "Waiting for file scope",
                else: status(delivery)}
            </p>
            <button
              :if={active?(delivery)}
              id={"stop-delivery-#{delivery.id}"}
              type="button"
              phx-click="stop_delivery"
              phx-value-delivery-id={delivery.id}
              disabled={@stopping == delivery.id}
              class="app-button-danger px-3 py-2 disabled:opacity-50"
            >{if @stopping == delivery.id, do: "Stopping…", else: "Stop workflow"}</button>
          </div>
          <p class="text-xs text-muted">
            Source revision {BossWeb.TaskRevision.number(@details, delivery.spec_revision_id)}
            <span :if={delivery.spec_revision_id != @details.pinned_revision.id}> · historical snapshot</span>
          </p>
          <p class="text-xs text-muted">
            Cycle {delivery.cycle} of {Boss.Deliveries.ModelPolicy.max_cycles(
              Map.get(delivery, :autonomy_version, 0)
            )}
          </p>
          <p class="text-xs text-muted">
            Implementer: {reviewer(Map.get(delivery, :implementer) || "codex")} · Analytic: {reviewer(
              Map.get(delivery, :analytic) || "codex"
            )} · Reviewer: {reviewer(delivery.reviewer)}
          </p>
          <p :if={delivery.check_config["argv"]} class="text-xs text-muted">
            Saved check command
            <code class="block break-all text-body">{JSON.encode!(delivery.check_config["argv"])}</code>
          </p>
          <p :if={!merge_stage(delivery) && candidate(delivery)} class="text-xs text-muted">
            Candidate commit <code class="block break-all text-body">{candidate(delivery)}</code>
          </p>
          <p :if={delivery.reason} class="whitespace-pre-wrap break-words text-warning">
            {delivery.reason}
          </p>
          <ol
            :if={agent_notes(delivery) != []}
            id={"delivery-stages-#{delivery.id}"}
            aria-label="Agent notes"
            class="space-y-2"
          >
            <li
              :for={stage <- agent_notes(delivery)}
              class="rounded-sm border border-line bg-paper px-3 py-2"
            >
              <p class="font-medium">
                {stage.label} · {stage.agent} · {stage.status}
              </p>
              <p :if={stage.note} class="mt-1 whitespace-pre-wrap break-words">{stage.note}</p>
              <p class="mt-1 font-mono text-xs text-muted">
                outcome {stage.outcome} · exit {stage.exit_code || "none"} · cleanup {stage.cleanup} · class {stage.error_class ||
                  "none"}
              </p>
            </li>
          </ol>
          <p :if={delivery.cleanup == "unknown"} class="text-warning">
            Cleanup or publication could not be confirmed. Workspaces are retained; automatic restart is blocked.
          </p>
          <p
            :if={Map.get(@scope_blockers, delivery.id, []) != []}
            id={"scope-wait-#{delivery.id}"}
            role="status"
            class="text-warning"
          >
            Waiting for an overlapping workflow to finish. Implementation has not started; Stop remains available.
          </p>
          <.file_scopes :if={report(delivery, "plan")} report={report(delivery, "plan")} />
          <.plan :if={report(delivery, "plan")} report={report(delivery, "plan")} />
          <.integration_candidate :if={merge_stage(delivery)} step={merge_stage(delivery)} />
          <.review
            :if={report(delivery, "review")}
            report={report(delivery, "review")}
            label={if merge_stage(delivery), do: "Original review", else: "Review"}
            candidate={
              if merge_stage(delivery), do: report_candidate(delivery, "review") || "Unavailable"
            }
          />
          <.review
            :if={report(delivery, "merge_review")}
            report={report(delivery, "merge_review")}
            label="Integration review"
            candidate={report_candidate(delivery, "merge_review") || "Unavailable"}
          />
          <div
            :if={delivery.status == "ready_to_merge"}
            class="space-y-3 rounded-sm border border-line bg-sage/50 p-4"
          >
            <p>
              Ready to integrate into <strong class="break-all">{delivery.intent["base_branch"]}</strong>.
            </p>
            <p class="text-xs text-muted">
              Original base commit <code class="break-all">{delivery.intent["base_commit"]}</code>
            </p>
            <p class="text-xs text-muted">
              An unchanged target fast-forwards to this approved commit. If the target has advanced,
              BOSS prepares a merge candidate, reruns the saved checks and requests a fresh review
              from {reviewer(delivery.reviewer)} before publication.
              Conflicts, failed checks, a rejected review or another target change block integration
              without automatic repair or retry.
              The target branch must not be checked out in your working folders.
              Done requires successful checks after publication.
            </p>
            <button
              :if={Map.has_key?(@integration_requests, delivery.id)}
              id={"integrate-delivery-#{delivery.id}"}
              type="button"
              phx-click="integrate_delivery"
              phx-value-delivery-id={delivery.id}
              phx-value-command-id={@integration_requests[delivery.id].id}
              disabled={
                !@integrate_available || (@uncertain && !@integration_requests[delivery.id].locked)
              }
              class="app-button-secondary px-3 py-2 font-medium disabled:opacity-50"
            >{if @integration_requests[delivery.id].locked,
              do: "Retry integration request",
              else: "Integrate approved result"}</button>
          </div>
          <details :if={delivery.steps != []}>
            <summary class="cursor-pointer text-body focus-visible:outline-2 focus-visible:outline-forest">
              Saved stages
            </summary>
            <ol class="mt-2 space-y-1 text-xs text-muted">
              <li :for={step <- delivery.steps} class="space-y-1">
                <p>{step.number}. {stage(step.kind)} · {step.status}</p>
                <p :if={is_map(step.input["model_profile"])} class="break-words">
                  {step.input["model_profile"]["model"]} · {step.input["model_profile"][
                    "reasoning_effort"
                  ]}
                </p>
                <details :if={step.kind == "resolve" && is_map(step.receipt["report"])}>
                  <summary class="cursor-pointer focus-visible:outline-2 focus-visible:outline-forest">
                    Resolution and assumptions
                  </summary>
                  <p class="mt-2 break-words">
                    {step.receipt["report"]["summary"]}
                  </p>
                  <ol class="mt-2 list-decimal space-y-1 pl-4">
                    <li :for={item <- step.receipt["report"]["steps"] || []} class="break-words">
                      {item}
                    </li>
                  </ol>
                  <p
                    :for={assumption <- step.receipt["report"]["assumptions"] || []}
                    class="mt-2 break-words"
                  >
                    Assumption: {assumption}
                  </p>
                  <p
                    :if={step.receipt["report"]["external_action"]}
                    class="mt-2 break-words text-warning"
                  >
                    External action: {step.receipt["report"]["external_action"]}
                  </p>
                </details>
                <%= if step.status == "failed" do %>
                  <p :if={is_integer(step.receipt["exit_code"])}>
                    Process exit code: {step.receipt["exit_code"]}
                  </p>
                  <p
                    :if={Boss.Deliveries.Diagnostics.message(step.receipt["outcome"])}
                    class="text-warning"
                  >
                    {Boss.Deliveries.Diagnostics.message(step.receipt["outcome"])}
                  </p>
                <% end %>
              </li>
            </ol>
          </details>
        </li>
      </ol>
    </section>
    """
  end

  attr :report, :map, required: true

  defp file_scopes(assigns) do
    ~H"""
    <section aria-label="Predicted file scopes" class="space-y-2 text-xs text-muted">
      <h4 class="font-medium text-body">Predicted file scopes</h4>
      <%= if is_list(@report["file_scopes"]) && @report["file_scopes"] != [] do %>
        <ul class="space-y-1">
          <li :for={scope <- @report["file_scopes"]} class="break-all">
            <span>{if scope["kind"] == "directory", do: "Directory", else: "File"}:</span>
            <code>{scope["path"]}</code>
          </li>
        </ul>
        <p>
          Predictions serialize known overlaps. They do not prevent unpredicted edits or semantic conflicts.
        </p>
      <% else %>
        <p>
          File scope is unknown. This workflow may overlap other work; potential conflicts remain.
        </p>
      <% end %>
    </section>
    """
  end

  attr :report, :map, required: true

  defp plan(assigns) do
    ~H"""
    <details>
      <summary class="cursor-pointer font-medium focus-visible:outline-2 focus-visible:outline-forest">
        Saved plan and criteria
      </summary>
      <p class="mt-3 whitespace-pre-wrap break-words">{@report["summary"]}</p>
      <ol class="mt-3 list-decimal space-y-2 pl-5 text-body">
        <li :for={step <- @report["steps"] || []} class="break-words">{step}</li>
      </ol>
      <ul aria-label="Planned acceptance criteria" class="mt-3 space-y-2">
        <li :for={criterion <- @report["acceptance"] || []} class="break-words">{criterion}</li>
      </ul>
    </details>
    """
  end

  attr :step, :map, required: true

  defp integration_candidate(assigns) do
    ~H"""
    <section
      aria-label="Integration candidate"
      class="space-y-3 rounded-sm border border-line bg-surface p-4 text-xs"
    >
      <h4 class="text-sm font-medium">Integration candidate</h4>
      <p class="text-muted">The original approval stays attached to its original commit.</p>
      <dl class="space-y-2 text-muted">
        <div>
          <dt>Original approved commit</dt>
          <dd class="break-all font-mono text-body">
            {commit(@step.input["original_candidate"])}
          </dd>
        </div>
        <div>
          <dt>Target pinned for integration</dt>
          <dd class="break-all font-mono text-body">{commit(@step.input["target_commit"])}</dd>
        </div>
        <div :if={@step.status == "finished"}>
          <dt>Merge candidate commit</dt>
          <dd class="break-all font-mono text-body">
            {commit(@step.receipt["candidate_commit"])}
          </dd>
        </div>
      </dl>
      <p :if={@step.status != "finished"} class="text-muted">
        A merge candidate has not been recorded.
      </p>
    </section>
    """
  end

  attr :report, :map, required: true
  attr :label, :string, default: "Review"
  attr :candidate, :any, default: nil

  defp review(assigns) do
    ~H"""
    <section
      aria-label={if @label == "Review", do: "Workflow review", else: @label}
      class="space-y-3 rounded-sm border border-line bg-surface p-4"
    >
      <p class="font-medium">{@label}: {verdict(@report["verdict"])}</p>
      <p :if={@candidate} class="text-xs text-muted">
        Reviewed commit <code class="block break-all text-body">{commit(@candidate)}</code>
      </p>
      <p class="whitespace-pre-wrap break-words">{@report["summary"]}</p>
      <details>
        <summary class="cursor-pointer focus-visible:outline-2 focus-visible:outline-forest">
          Acceptance and issues
        </summary>
        <ul aria-label="Reviewed acceptance criteria" class="mt-3 space-y-3">
          <li :for={item <- @report["acceptance"] || []} class="break-words">
            <p>{item["status"]}: {item["criterion"]}</p>
            <p class="whitespace-pre-wrap text-body">{item["evidence"]}</p>
          </li>
        </ul>
        <ul aria-label="Workflow review issues" class="mt-3 space-y-3">
          <li :for={issue <- @report["issues"] || []} class="break-words">
            <p>{issue["criterion"]}</p>
            <p class="whitespace-pre-wrap text-body">{issue["message"]}</p>
          </li>
        </ul>
      </details>
    </section>
    """
  end

  defp report(delivery, kind) do
    delivery.steps
    |> Enum.reverse()
    |> Enum.find_value(fn step ->
      if step.kind == kind && step.status == "finished" && is_map(step.receipt["report"]),
        do: step.receipt["report"]
    end)
  end

  defp report_candidate(delivery, kind) do
    delivery.steps
    |> Enum.reverse()
    |> Enum.find_value(fn step ->
      if step.kind == kind && step.status == "finished" && is_map(step.receipt["report"]),
        do: step.receipt["candidate_commit"] || step.input["candidate_commit"]
    end)
  end

  defp merge_stage(delivery),
    do: delivery.steps |> Enum.reverse() |> Enum.find(&(&1.kind == "merge"))

  defp commit(value) when is_binary(value), do: value
  defp commit(_), do: "Unavailable"

  defp candidate(delivery) do
    delivery.steps
    |> Enum.reverse()
    |> Enum.find_value(fn step ->
      step.receipt["candidate_commit"] || step.input["candidate_commit"]
    end)
  end

  defp queue_status("queued"), do: "Queued — waiting to start"
  defp queue_status("paused"), do: "Paused — waiting for Resume"
  defp queue_status("started"), do: "Started workflow"
  defp queue_status("cancelled"), do: "Queue cancelled"
  defp queue_status("stale"), do: "Queue source or task changed — start a fresh workflow"
  defp queue_status(_), do: "Queue status unavailable"

  defp active?(delivery), do: delivery.status in @active

  defp agent_notes(delivery) do
    delivery
    |> Map.get(:steps, [])
    |> Enum.filter(&(&1.status in ["failed", "interrupted"]))
    |> Enum.map(fn step ->
      receipt = Map.get(step, :receipt) || %{}

      %{
        label: stage(step.kind),
        agent: stage_agent(delivery, step.kind),
        status: step.status,
        note: receipt["reason"],
        outcome: receipt["outcome"] || "none",
        exit_code: receipt["exit_code"],
        cleanup: receipt["cleanup"] || "none",
        error_class: get_in(receipt, ["summary", "error_class"])
      }
    end)
  end

  defp stage_agent(delivery, kind) when kind in ["review", "merge_review"],
    do: reviewer(delivery.reviewer)

  defp stage_agent(delivery, "resolve"),
    do: reviewer(Map.get(delivery, :analytic) || "codex")

  defp stage_agent(delivery, kind) when kind in ["plan", "implement"],
    do: reviewer(Map.get(delivery, :implementer) || "codex")

  defp stage_agent(_, _), do: "Workflow"

  defp reviewer(id) do
    Enum.find_value(Boss.Agents.Metadata.catalog(), "Unavailable", fn agent ->
      Atom.to_string(agent.id) == id && agent.name
    end)
  end

  defp verdict("approved"), do: "Approved"
  defp verdict("changes_requested"), do: "Changes requested"
  defp verdict("needs_spec_revision"), do: "Specification needs clarification"
  defp verdict(_), do: "Unavailable"
  defp stage("plan"), do: "Planning"
  defp stage("resolve"), do: "Resolving with another model"
  defp stage("retry_snapshot"), do: "Preparing retained candidate"
  defp stage("retry_check"), do: "Rechecking retained candidate"
  defp stage("implement"), do: "Implementation"
  defp stage("snapshot"), do: "Snapshot"
  defp stage("check"), do: "Checks"
  defp stage("review"), do: "Review"
  defp stage("merge"), do: "Merge candidate"
  defp stage("merge_check"), do: "Merge checks"
  defp stage("merge_review"), do: "Merge review"
  defp stage("publish"), do: "Publication"
  defp stage("post_check"), do: "Post-integration checks"
  defp stage(kind), do: kind

  defp delivery_status(%{status: "integrating", steps: steps}) do
    case List.last(steps) do
      %{kind: "merge", status: "running"} -> "Preparing merge candidate"
      %{kind: "merge_check", status: "running"} -> "Checking merge candidate"
      %{kind: "merge_review", status: "running"} -> "Reviewing merge candidate"
      _ -> status("integrating")
    end
  end

  defp delivery_status(%{status: status}), do: status(status)

  defp status(%{steps: steps} = delivery) when is_list(steps) do
    case List.last(steps) do
      %{kind: "resolve", status: "running"} -> "Resolving with another model"
      _ -> delivery_status(delivery)
    end
  end

  defp status(%{status: status}), do: status(status)
  defp status("planning"), do: "Preparing plan"
  defp status("implementing"), do: "Implementing task"
  defp status("testing"), do: "Checking candidate"
  defp status("reviewing"), do: "Reviewing candidate"
  defp status("ready_to_merge"), do: "Ready to integrate — waiting for you"
  defp status("integrating"), do: "Integrating approved result"
  defp status("done"), do: "Done — integrated and checks passed"
  defp status("blocked"), do: "Blocked — needs attention"
  defp status("needs_input"), do: "Specification needs clarification"
  defp status("failed"), do: "Workflow failed"
  defp status("cancelled"), do: "Workflow stopped — workspaces retained"
  defp status("interrupted"), do: "Workflow interrupted — needs attention"
  defp status(_), do: "Workflow status unavailable"
end
