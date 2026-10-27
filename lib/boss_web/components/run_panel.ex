defmodule BossWeb.RunPanel do
  use BossWeb, :html
  alias Boss.Runs

  attr :details, :map, required: true
  attr :runs, :list, required: true
  attr :command_id, :string, required: true
  attr :starting, :boolean, required: true
  attr :stopping, :any, default: nil
  attr :available, :boolean, required: true
  attr :start_available, :boolean, default: true
  attr :supported, :boolean, required: true
  attr :error, :any, default: nil
  attr :check_requests, :map, default: %{}
  attr :review_requests, :map, default: %{}

  def panel(assigns) do
    assigns =
      assigns
      |> assign(:blocked, Enum.any?(assigns.runs, &(&1.cleanup == "unknown")))
      |> assign(
        :check_uncertain,
        Enum.any?(assigns.check_requests, fn {_, request} -> request.locked end)
      )
      |> assign(
        :review_uncertain,
        Enum.any?(assigns.review_requests, fn {_, request} -> request.locked end)
      )

    ~H"""
    <section id="task-runs" aria-labelledby="task-runs-heading" class="border-y border-zinc-800 py-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h3 id="task-runs-heading" class="font-semibold">Runs, checks and reviews</h3>
        <button
          id="start-codex"
          type="button"
          phx-click="start_run"
          phx-value-command-id={@command_id}
          disabled={!@available || !@start_available || @check_uncertain || @review_uncertain}
          aria-describedby="run-snapshot run-account"
          class="rounded-md bg-emerald-400 px-4 py-2 font-semibold text-zinc-950 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
        >{if @starting, do: "Starting…", else: "Start Codex"}</button>
      </div>
      <p id="run-snapshot" class="mt-3 text-sm text-zinc-300">
        Runs task snapshot revision {@details.pinned_revision.number}, even when viewing another revision.
      </p>
      <p id="run-account" class="mt-1 text-xs text-zinc-400">
        Uses your local Codex account and may incur usage charges. Closing this drawer keeps the run active.
      </p>
      <p :if={!@supported} class="mt-3 text-sm text-amber-300">Task runs currently require macOS.</p>
      <p :if={@blocked} id="run-cleanup-warning" role="alert" class="mt-3 text-sm text-amber-300">
        Process cleanup could not be confirmed. Workspace retained; new runs are blocked.
      </p>
      <p
        :if={@check_uncertain && !@starting}
        id="check-start-pending"
        role="status"
        class="mt-3 text-sm text-amber-300"
      >
        A checks start is unresolved. Retry its saved command on the original task before starting other work.
      </p>
      <p :if={@error} id="run-error" role="alert" class="mt-3 text-sm text-red-300">{@error}</p>
      <p
        :if={@review_uncertain && !@starting}
        id="review-start-pending"
        role="status"
        class="mt-3 text-sm text-amber-300"
      >
        A review start is unresolved. Retry its saved request on the original task before starting other work.
      </p>
      <p :if={@runs == []} class="mt-4 text-sm text-zinc-400">No runs yet.</p>
      <p :if={@runs != []} class="mt-4 text-xs text-zinc-400">
        Latest 10 attempts and source runs · results require review and checks
      </p>
      <ol id="run-attempts" class="mt-2 divide-y divide-zinc-800">
        <li :for={run <- @runs} id={"run-#{run.id}"} class="space-y-2 py-4 text-sm">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <p role="status" class="font-medium">{status(run.adapter, run.status)}</p>
            <button
              :if={Runs.active?(run)}
              id={"stop-run-#{run.id}"}
              type="button"
              phx-click="stop_run"
              phx-value-run-id={run.id}
              disabled={@stopping == run.id || run.status == "stopping"}
              class="rounded border border-zinc-600 px-3 py-2 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
            >{if @stopping == run.id || run.status == "stopping", do: "Stopping…", else: "Stop"}</button>
          </div>
          <p class="text-xs text-zinc-400">
            Source revision {BossWeb.TaskRevision.number(@details, run.spec_revision_id)}
            <span :if={run.spec_revision_id != @details.pinned_revision.id}> · historical snapshot</span>
          </p>
          <time datetime={DateTime.to_iso8601(run.inserted_at)} class="block text-xs text-zinc-400">
            {Calendar.strftime(run.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
          </time>
          <div :if={run.adapter in ["check", "review"]} class="space-y-2 text-xs text-zinc-400">
            <p :if={run.candidate_commit}>
              Snapshot commit
              <code class="block break-all text-zinc-300">{run.candidate_commit}</code>
            </p>
            <p :if={run.check_config["argv"]}>
              Command arguments
              <code class="block break-all text-zinc-300">{JSON.encode!(run.check_config["argv"])}</code>
            </p>
            <p :if={run.exit_kind == "exit"}>Exit code: {run.exit_code}</p>
            <p :if={run.exit_kind == "signal"}>Terminated by signal: {run.signal}</p>
            <p>Applies only to this snapshot. Later workspace edits have not been checked.</p>
          </div>
          <.review_report
            :if={run.adapter == "review" && run.status == "finished" && run.review_report != %{}}
            report={run.review_report}
          />
          <p :if={run.reason} class="break-words text-amber-300">{run.reason}</p>
          <p :if={run.workspace["path"]} class="text-zinc-400">
            Retained workspace
            <code class="mt-1 block break-all text-xs text-zinc-300">{run.workspace["path"]}</code>
          </p>
          <p class="text-xs text-zinc-400">
            {run.summary["event_count"] || 0} events · {run.summary["stdout_bytes"] || 0} stdout bytes · {run.summary[
              "stderr_bytes"
            ] || 0} stderr bytes
          </p>
          <p :if={run.summary["usage"] not in [nil, %{}]} class="text-xs text-zinc-400">
            Tokens: {tokens(run.summary["usage"], "input_tokens")} input · {tokens(
              run.summary["usage"],
              "output_tokens"
            )} output
          </p>
          <details :if={run.summary["events"] not in [nil, []]}>
            <summary class="cursor-pointer text-zinc-300 focus-visible:outline-2 focus-visible:outline-emerald-400">
              Recent event types
            </summary>
            <ol class="mt-2 space-y-1 font-mono text-xs text-zinc-400">
              <li :for={event <- run.summary["events"]}>
                {event["sequence"]}. {event_type(event["type"])}
              </li>
            </ol>
          </details>
          <.check_form
            :if={run.adapter == "codex" && run.status == "finished" && run.cleanup == "group_empty"}
            parent={run.id}
            request={Map.get(@check_requests, run.id)}
            available={
              @available && !@review_uncertain &&
                (!@check_uncertain || Map.get(@check_requests, run.id, %{})[:locked])
            }
          />
          <.review_action
            :if={run.adapter == "check" && run.status == "finished" && run.cleanup == "group_empty"}
            parent={run.id}
            request={Map.get(@review_requests, run.id)}
            available={
              @available && !@check_uncertain &&
                (!@review_uncertain || Map.get(@review_requests, run.id, %{})[:locked])
            }
          />
        </li>
      </ol>
    </section>
    """
  end

  attr :parent, :string, required: true
  attr :request, :any, required: true
  attr :available, :boolean, required: true

  defp review_action(assigns) do
    ~H"""
    <div
      :if={@request}
      id={"review-action-#{@parent}"}
      class="mt-4 space-y-2 rounded-md border border-zinc-700 p-3"
    >
      <p id={"review-help-#{@parent}"} class="text-xs text-zinc-400">
        Starts a separate read-only Codex session for this snapshot. Uses your Codex account and may incur charges.
        The report does not approve the task or merge changes.
      </p>
      <button
        id={"start-review-#{@parent}"}
        type="button"
        phx-click="start_review"
        phx-value-parent-id={@parent}
        phx-value-command-id={@request.id}
        disabled={!@available}
        aria-describedby={"review-help-#{@parent}"}
        class="rounded border border-emerald-600 px-3 py-2 font-medium text-emerald-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
      >{if @request.locked, do: "Retry review", else: "Review with Codex"}</button>
    </div>
    """
  end

  attr :report, :map, required: true

  defp review_report(assigns) do
    ~H"""
    <section aria-label="Model assessment" class="space-y-3 rounded-md border border-zinc-700 p-3">
      <p class="font-medium">Model assessment: {verdict(@report["verdict"])}</p>
      <p class="whitespace-pre-wrap break-words">{@report["summary"]}</p>
      <p class="text-xs text-zinc-400">
        Based on the saved spec, diff and check receipt. A refined plan and raw test output were not provided.
        Task approval and integration remain separate.
      </p>
      <details>
        <summary class="cursor-pointer focus-visible:outline-2 focus-visible:outline-emerald-400">
          Acceptance and issues
        </summary>
        <ul aria-label="Acceptance criteria" class="mt-3 space-y-3">
          <li :for={item <- @report["acceptance"]} class="space-y-1 break-words">
            <p class="font-medium">{acceptance(item["status"])}: {item["criterion"]}</p>
            <p class="whitespace-pre-wrap text-zinc-300">{item["evidence"]}</p>
          </li>
        </ul>
        <p :if={@report["issues"] == []} class="mt-3 text-zinc-400">No issues reported.</p>
        <ul :if={@report["issues"] != []} aria-label="Review issues" class="mt-3 space-y-3">
          <li :for={issue <- @report["issues"]} class="space-y-1 break-words">
            <p class="font-medium">{issue["criterion"]}</p>
            <p class="whitespace-pre-wrap text-zinc-300">{issue["message"]}</p>
          </li>
        </ul>
      </details>
    </section>
    """
  end

  defp verdict("approved"), do: "Approved"
  defp verdict("changes_requested"), do: "Changes requested"
  defp verdict("needs_spec_revision"), do: "Spec revision needed"
  defp verdict(_), do: "Unavailable"
  defp acceptance("passed"), do: "Passed"
  defp acceptance("failed"), do: "Failed"
  defp acceptance("unclear"), do: "Unclear"
  defp acceptance(_), do: "Unavailable"

  attr :parent, :string, required: true
  attr :request, :any, required: true
  attr :available, :boolean, required: true

  defp check_form(assigns) do
    ~H"""
    <form
      :if={@request}
      id={"check-form-#{@parent}"}
      phx-change="edit_check"
      phx-submit="start_check"
      class="mt-4 space-y-2 rounded-md border border-zinc-700 p-3"
    >
      <input type="hidden" name="parent_id" value={@parent} />
      <input type="hidden" name="command_id" value={@request.id} />
      <label for={"check-command-#{@parent}"} class="block font-medium">Check command</label>
      <input
        id={"check-command-#{@parent}"}
        name="command"
        value={@request.text}
        placeholder="mix test"
        required
        maxlength="4096"
        readonly={@request.locked}
        disabled={!@available}
        autocomplete="off"
        spellcheck="false"
        aria-describedby={"check-help-#{@parent}"}
        class="w-full min-w-0 rounded border border-zinc-600 bg-zinc-900 px-3 py-2 font-mono text-sm focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400"
      />
      <p id={"check-help-#{@parent}"} class="text-xs text-zinc-400">
        Runs this command locally on a captured copy using your account's access. Use trusted commands;
        do not put secrets in arguments. Arguments support quoting, without shell expansion.
      </p>
      <p :if={@request.locked} class="text-xs text-amber-300">
        Retry keeps the same command while its start outcome is unresolved.
      </p>
      <button
        type="submit"
        disabled={!@available}
        class="rounded border border-emerald-600 px-3 py-2 font-medium text-emerald-300 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-emerald-400 disabled:opacity-50"
      >{if @request.locked, do: "Retry checks", else: "Snapshot and run checks"}</button>
    </form>
    """
  end

  defp status("check", "preparing"), do: "Capturing check snapshot"
  defp status("check", "launching"), do: "Starting checks"
  defp status("check", "running"), do: "Checks running"
  defp status("check", "stopping"), do: "Stopping checks"
  defp status("check", "finished"), do: "Checks passed — review required"
  defp status("check", "failed"), do: "Checks failed"
  defp status("review", "preparing"), do: "Verifying review snapshot"
  defp status("review", "launching"), do: "Starting review"
  defp status("review", "running"), do: "Review running"
  defp status("review", "stopping"), do: "Stopping review"
  defp status("review", "finished"), do: "Review completed — model assessment"
  defp status("review", "failed"), do: "Review failed"
  defp status(_, status), do: status(status)

  defp status("preparing"), do: "Preparing workspace"
  defp status("launching"), do: "Starting Codex"
  defp status("running"), do: "Codex running"
  defp status("stopping"), do: "Stopping Codex"
  defp status("finished"), do: "Codex finished — unverified"
  defp status("cancelled"), do: "Cancelled — workspace retained"
  defp status("failed"), do: "Run failed"
  defp status("interrupted"), do: "Run interrupted — needs attention"
  defp status(_), do: "Run status unavailable"

  defp event_type(type)
       when type in ~w(thread.started turn.started turn.completed turn.failed error item.started item.updated item.completed),
       do: type

  defp event_type(_), do: "other"

  defp tokens(usage, key) do
    case usage[key] do
      value when is_integer(value) and value >= 0 -> value
      _ -> "unavailable"
    end
  end
end
