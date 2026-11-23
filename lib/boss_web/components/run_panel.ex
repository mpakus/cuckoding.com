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
    <section
      id="task-runs"
      aria-labelledby="task-runs-heading"
      class="min-w-0 space-y-2.5 border-t border-line pt-3 text-xs"
    >
      <div class="flex flex-wrap items-center justify-between gap-2">
        <div>
          <h3 id="task-runs-heading" class="font-semibold text-body">
            Manual Codex runs &amp; checks
          </h3>
          <p id="run-snapshot" class="text-[11px] text-muted">
            Runs snapshot revision {@details.pinned_revision.number}.
          </p>
        </div>
        <button
          id="start-codex"
          type="button"
          phx-click="start_run"
          phx-value-command-id={@command_id}
          disabled={!@available || !@start_available || @check_uncertain || @review_uncertain}
          aria-describedby="run-snapshot run-account"
          class="app-button-secondary px-3 py-1.5 text-xs"
        >{if @starting, do: "Starting…", else: "Start Codex"}</button>
      </div>

      <p id="run-account" class="sr-only">
        Uses your local Codex account and may incur usage charges. Closing this drawer keeps the run active.
      </p>
      <p :if={!@supported} class="text-warning">Task runs currently require macOS.</p>
      <p :if={@blocked} id="run-cleanup-warning" role="alert" class="text-warning">
        Process cleanup could not be confirmed. Workspace retained; new runs are blocked.
      </p>
      <p
        :if={@check_uncertain && !@starting}
        id="check-start-pending"
        role="status"
        class="text-warning"
      >
        A checks start is unresolved. Retry its saved command on the original task before starting other work.
      </p>
      <p :if={@error} id="run-error" role="alert" class="text-danger">{@error}</p>
      <p
        :if={@review_uncertain && !@starting}
        id="review-start-pending"
        role="status"
        class="text-warning"
      >
        A review start is unresolved. Retry its saved request on the original task before starting other work.
      </p>
      <p :if={@runs == []} class="text-muted">No manual runs.</p>
      <p :if={@runs != []} class="font-mono text-[11px] text-muted">
        Latest 10 attempts and source runs
      </p>

      <ol :if={@runs != []} id="run-attempts" class="space-y-2">
        <li
          :for={run <- @runs}
          id={"run-#{run.id}"}
          class="space-y-2 rounded border border-line bg-paper p-2.5"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <p role="status" class="font-medium text-ink">{status(run.adapter, run.status)}</p>
            <button
              :if={Runs.active?(run)}
              id={"stop-run-#{run.id}"}
              type="button"
              phx-click="stop_run"
              phx-value-run-id={run.id}
              disabled={@stopping == run.id || run.status == "stopping"}
              class="app-button-danger px-2.5 py-1 text-xs"
            >{if @stopping == run.id || run.status == "stopping", do: "Stopping…", else: "Stop"}</button>
          </div>
          <p class="font-mono text-[11px] text-muted">
            Source revision {BossWeb.TaskRevision.number(@details, run.spec_revision_id)}
            <span :if={run.spec_revision_id != @details.pinned_revision.id}> · historical snapshot</span>
            ·
            <time datetime={DateTime.to_iso8601(run.inserted_at)}>{Calendar.strftime(
              run.inserted_at,
              "%Y-%m-%d %H:%M:%S UTC"
            )}</time>
          </p>
          <div :if={run.adapter in ["check", "review"]} class="space-y-1 text-[11px] text-muted">
            <p :if={run.candidate_commit}>
              Snapshot commit
              <code class="break-all font-mono text-body">{run.candidate_commit}</code>
            </p>
            <p :if={run.check_config["argv"]}>
              Command
              <code class="break-all font-mono text-body">{JSON.encode!(run.check_config["argv"])}</code>
            </p>
            <p :if={run.exit_kind == "exit"}>Exit code: {run.exit_code}</p>
            <p :if={run.exit_kind == "signal"}>Terminated by signal: {run.signal}</p>
            <p>Applies only to this snapshot. Later workspace edits have not been checked.</p>
          </div>
          <.review_report
            :if={run.adapter == "review" && run.status == "finished" && run.review_report != %{}}
            report={run.review_report}
          />
          <p :if={run.reason} class="break-words text-warning">{run.reason}</p>
          <p :if={run.workspace["path"]} class="font-mono text-[11px] text-muted">
            Workspace: <code class="break-all text-body">{run.workspace["path"]}</code>
          </p>
          <p class="font-mono text-[11px] text-muted">
            {run.summary["event_count"] || 0} events · {run.summary["stdout_bytes"] || 0} stdout bytes · {run.summary[
              "stderr_bytes"
            ] || 0} stderr bytes
          </p>
          <p :if={run.summary["usage"] not in [nil, %{}]} class="font-mono text-[11px] text-muted">
            Tokens: {tokens(run.summary["usage"], "input_tokens")} input · {tokens(
              run.summary["usage"],
              "output_tokens"
            )} output
          </p>
          <details :if={run.summary["events"] not in [nil, []]}>
            <summary class="cursor-pointer font-mono text-[11px] text-muted hover:text-ink">
              Recent event types
            </summary>
            <ol class="mt-1.5 space-y-0.5 font-mono text-[11px] text-muted">
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
      class="mt-2 space-y-2 rounded border border-line bg-surface p-2.5"
    >
      <p id={"review-help-#{@parent}"} class="text-[11px] text-muted">
        Starts a separate read-only Codex session for this snapshot. Uses your Codex account and may incur charges.
      </p>
      <button
        id={"start-review-#{@parent}"}
        type="button"
        phx-click="start_review"
        phx-value-parent-id={@parent}
        phx-value-command-id={@request.id}
        disabled={!@available}
        aria-describedby={"review-help-#{@parent}"}
        class="app-button-secondary px-2.5 py-1 text-xs"
      >{if @request.locked, do: "Retry review", else: "Review with Codex"}</button>
    </div>
    """
  end

  attr :report, :map, required: true

  defp review_report(assigns) do
    ~H"""
    <section
      aria-label="Model assessment"
      class="space-y-2 rounded border border-line bg-surface p-2.5"
    >
      <p class="font-medium text-ink">Model assessment: {verdict(@report["verdict"])}</p>
      <p class="whitespace-pre-wrap break-words text-body">{@report["summary"]}</p>
      <p class="text-[11px] text-muted">
        Based on the saved spec, diff and check receipt. A refined plan and raw test output were not provided.
        Task approval and integration remain separate.
      </p>
      <details>
        <summary class="cursor-pointer font-mono text-[11px] text-muted hover:text-ink">
          Acceptance and issues
        </summary>
        <ul aria-label="Acceptance criteria" class="mt-2 space-y-1.5">
          <li :for={item <- @report["acceptance"]} class="break-words">
            <p class="font-medium text-ink">{acceptance(item["status"])}: {item["criterion"]}</p>
            <p class="whitespace-pre-wrap text-muted">{item["evidence"]}</p>
          </li>
        </ul>
        <p :if={@report["issues"] == []} class="mt-2 text-muted">No issues reported.</p>
        <ul :if={@report["issues"] != []} aria-label="Review issues" class="mt-2 space-y-1.5">
          <li :for={issue <- @report["issues"]} class="break-words">
            <p class="font-medium text-warning">{issue["criterion"]}</p>
            <p class="whitespace-pre-wrap text-body">{issue["message"]}</p>
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
      class="mt-2 space-y-2 rounded border border-line bg-surface p-2.5"
    >
      <input type="hidden" name="parent_id" value={@parent} />
      <input type="hidden" name="command_id" value={@request.id} />
      <label for={"check-command-#{@parent}"} class="block font-medium text-body">Check command</label>
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
        class="app-field w-full min-w-0 px-2.5 py-1 font-mono text-xs"
      />
      <p id={"check-help-#{@parent}"} class="text-[11px] text-muted">
        Runs locally on a captured copy using your account's access, without shell expansion.
      </p>
      <p :if={@request.locked} class="text-[11px] text-warning">
        Retry keeps the same command while its start outcome is unresolved.
      </p>
      <button
        type="submit"
        disabled={!@available}
        class="app-button-secondary px-2.5 py-1 text-xs"
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
