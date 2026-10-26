defmodule BossWeb.RunPanel do
  use BossWeb, :html
  alias Boss.Runs

  attr :details, :map, required: true
  attr :runs, :list, required: true
  attr :command_id, :string, required: true
  attr :starting, :boolean, required: true
  attr :stopping, :any, default: nil
  attr :available, :boolean, required: true
  attr :supported, :boolean, required: true
  attr :error, :any, default: nil

  def panel(assigns) do
    assigns = assign(assigns, :blocked, Enum.any?(assigns.runs, &(&1.cleanup == "unknown")))

    ~H"""
    <section id="task-runs" aria-labelledby="task-runs-heading" class="border-y border-zinc-800 py-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <h3 id="task-runs-heading" class="font-semibold">Codex runs</h3>
        <button
          id="start-codex"
          type="button"
          phx-click="start_run"
          phx-value-command-id={@command_id}
          disabled={!@available}
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
      <p :if={@error} id="run-error" role="alert" class="mt-3 text-sm text-red-300">{@error}</p>
      <p :if={@runs == []} class="mt-4 text-sm text-zinc-400">No runs yet.</p>
      <p :if={@runs != []} class="mt-4 text-xs text-zinc-400">
        Latest 10 attempts · results require review and checks
      </p>
      <ol id="run-attempts" class="mt-2 divide-y divide-zinc-800">
        <li :for={run <- @runs} id={"run-#{run.id}"} class="space-y-2 py-4 text-sm">
          <div class="flex flex-wrap items-center justify-between gap-3">
            <p role="status" class="font-medium">{status(run.status)}</p>
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
          <time datetime={DateTime.to_iso8601(run.inserted_at)} class="block text-xs text-zinc-400">
            {Calendar.strftime(run.inserted_at, "%Y-%m-%d %H:%M:%S UTC")}
          </time>
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
        </li>
      </ol>
    </section>
    """
  end

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
