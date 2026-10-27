defmodule BossWeb.DeliveryPanel do
  use BossWeb, :html

  @active ~w(planning implementing testing reviewing integrating)
  attr :details, :map, required: true
  attr :deliveries, :list, required: true
  attr :request, :map, required: true
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
      class="border-t border-zinc-800 py-5"
    >
      <h3 id="task-deliveries-heading" class="font-semibold">Task workflow</h3>
      <p id="delivery-help" class="mt-2 text-sm text-zinc-300">
        Plan, implement, check and review task snapshot revision {@details.pinned_revision.number}.
        Codex can make fixes within a maximum of three implementation/check/review cycles.
        An approved result waits for you to integrate it.
      </p>
      <p id="delivery-account" class="mt-2 text-xs text-zinc-400">
        Uses your local Codex account and may incur charges for multiple runs.
        Source, plans, diffs and check output are sent to Codex. Closing this drawer keeps the workflow active.
      </p>
      <p :if={!@supported} class="mt-3 text-sm text-amber-300">
        Task workflows currently require macOS.
      </p>
      <form
        :if={@details.task.state in ~w(new failed interrupted cancelled blocked needs_input)}
        id="delivery-form"
        phx-change="edit_delivery"
        phx-submit="start_delivery"
        class="mt-4 space-y-2"
      >
        <input type="hidden" name="command_id" value={@request.id} />
        <label for="delivery-command" class="block text-sm font-medium">Workflow check command</label>
        <input
          id="delivery-command"
          name="command"
          value={@request.text}
          required
          maxlength="4096"
          readonly={@request.locked}
          disabled={!@start_available}
          autocomplete="off"
          spellcheck="false"
          placeholder="mix test"
          aria-describedby="delivery-command-help delivery-account"
          class="w-full min-w-0 rounded border border-zinc-600 bg-zinc-900 px-3 py-2 font-mono text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
        />
        <p id="delivery-command-help" class="text-xs text-zinc-400">
          Use a trusted command. It runs locally on each candidate and after integration.
          Arguments support quoting, without shell expansion. Keep secrets out of arguments and output.
        </p>
        <button
          id="start-delivery"
          type="submit"
          disabled={!@start_available}
          aria-describedby="delivery-help delivery-account"
          class="rounded-md bg-emerald-400 px-4 py-2 font-semibold text-zinc-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
        >{cond do
          @starting -> "Starting workflow…"
          @request.locked -> "Retry workflow start"
          true -> "Start workflow"
        end}</button>
      </form>
      <p
        :if={@uncertain && is_nil(@starting)}
        id="delivery-request-pending"
        role="status"
        class="mt-3 text-sm text-amber-300"
      >
        A workflow request is unresolved. Retry its saved request on the original task before starting other work.
      </p>
      <p :if={@error} id="delivery-error" role="alert" class="mt-3 text-sm text-red-300">{@error}</p>
      <p :if={@deliveries == []} class="mt-4 text-sm text-zinc-400">No workflows yet.</p>
      <ol id="delivery-attempts" class="mt-3 divide-y divide-zinc-800">
        <li
          :for={delivery <- @deliveries}
          id={"delivery-#{delivery.id}"}
          class="space-y-3 py-4 text-sm"
        >
          <div class="flex flex-wrap items-center justify-between gap-3">
            <p role="status" class="font-medium">{status(delivery.status)}</p>
            <button
              :if={active?(delivery)}
              id={"stop-delivery-#{delivery.id}"}
              type="button"
              phx-click="stop_delivery"
              phx-value-delivery-id={delivery.id}
              disabled={@stopping == delivery.id}
              class="rounded border border-zinc-600 px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
            >{if @stopping == delivery.id, do: "Stopping…", else: "Stop workflow"}</button>
          </div>
          <p class="text-xs text-zinc-400">Cycle {delivery.cycle} of 3</p>
          <p :if={delivery.check_config["argv"]} class="text-xs text-zinc-400">
            Saved check command
            <code class="block break-all text-zinc-300">{JSON.encode!(delivery.check_config["argv"])}</code>
          </p>
          <p :if={candidate(delivery)} class="text-xs text-zinc-400">
            Candidate commit <code class="block break-all text-zinc-300">{candidate(delivery)}</code>
          </p>
          <p :if={delivery.reason} class="whitespace-pre-wrap break-words text-amber-300">
            {delivery.reason}
          </p>
          <p :if={delivery.cleanup == "unknown"} class="text-amber-300">
            Cleanup or publication could not be confirmed. Workspaces are retained; automatic restart is blocked.
          </p>
          <.plan :if={report(delivery, "plan")} report={report(delivery, "plan")} />
          <.review :if={report(delivery, "review")} report={report(delivery, "review")} />
          <div
            :if={delivery.status == "ready_to_merge"}
            class="space-y-2 rounded border border-emerald-800 p-3"
          >
            <p>
              Ready to integrate into <strong class="break-all">{delivery.intent["base_branch"]}</strong>.
            </p>
            <p class="text-xs text-zinc-400">
              Saved target commit <code class="break-all">{delivery.intent["base_commit"]}</code>
            </p>
            <p class="text-xs text-zinc-400">
              Integration only fast-forwards the unchanged target to this approved commit.
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
              class="rounded border border-emerald-600 px-3 py-2 font-medium text-emerald-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
            >{if @integration_requests[delivery.id].locked,
              do: "Retry integration request",
              else: "Integrate approved result"}</button>
          </div>
          <details :if={delivery.steps != []}>
            <summary class="cursor-pointer text-zinc-300 focus-visible:outline-2 focus-visible:outline-emerald-400">
              Saved stages
            </summary>
            <ol class="mt-2 space-y-1 text-xs text-zinc-400">
              <li :for={step <- delivery.steps}>{step.number}. {stage(step.kind)} · {step.status}</li>
            </ol>
          </details>
        </li>
      </ol>
    </section>
    """
  end

  attr :report, :map, required: true

  defp plan(assigns) do
    ~H"""
    <details>
      <summary class="cursor-pointer font-medium focus-visible:outline-2 focus-visible:outline-emerald-400">
        Saved plan and criteria
      </summary>
      <p class="mt-3 whitespace-pre-wrap break-words">{@report["summary"]}</p>
      <ol class="mt-3 list-decimal space-y-2 pl-5 text-zinc-300">
        <li :for={step <- @report["steps"] || []} class="break-words">{step}</li>
      </ol>
      <ul aria-label="Planned acceptance criteria" class="mt-3 space-y-2">
        <li :for={criterion <- @report["acceptance"] || []} class="break-words">{criterion}</li>
      </ul>
    </details>
    """
  end

  attr :report, :map, required: true

  defp review(assigns) do
    ~H"""
    <section aria-label="Workflow review" class="space-y-2 rounded border border-zinc-700 p-3">
      <p class="font-medium">Review: {verdict(@report["verdict"])}</p>
      <p class="whitespace-pre-wrap break-words">{@report["summary"]}</p>
      <details>
        <summary class="cursor-pointer focus-visible:outline-2 focus-visible:outline-emerald-400">
          Acceptance and issues
        </summary>
        <ul aria-label="Reviewed acceptance criteria" class="mt-3 space-y-3">
          <li :for={item <- @report["acceptance"] || []} class="break-words">
            <p>{item["status"]}: {item["criterion"]}</p>
            <p class="whitespace-pre-wrap text-zinc-300">{item["evidence"]}</p>
          </li>
        </ul>
        <ul aria-label="Workflow review issues" class="mt-3 space-y-3">
          <li :for={issue <- @report["issues"] || []} class="break-words">
            <p>{issue["criterion"]}</p>
            <p class="whitespace-pre-wrap text-zinc-300">{issue["message"]}</p>
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
      if step.kind == kind && step.status == "finished", do: step.receipt["report"]
    end)
  end

  defp candidate(delivery) do
    delivery.steps
    |> Enum.reverse()
    |> Enum.find_value(fn step ->
      step.receipt["candidate_commit"] || step.input["candidate_commit"]
    end)
  end

  defp active?(delivery), do: delivery.status in @active

  defp verdict("approved"), do: "Approved"
  defp verdict("changes_requested"), do: "Changes requested"
  defp verdict("needs_spec_revision"), do: "Specification needs clarification"
  defp verdict(_), do: "Unavailable"
  defp stage("plan"), do: "Planning"
  defp stage("implement"), do: "Implementation"
  defp stage("snapshot"), do: "Snapshot"
  defp stage("check"), do: "Checks"
  defp stage("review"), do: "Review"
  defp stage("publish"), do: "Publication"
  defp stage("post_check"), do: "Post-integration checks"
  defp stage(kind), do: kind
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
