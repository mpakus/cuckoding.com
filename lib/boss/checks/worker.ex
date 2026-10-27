defmodule Boss.Checks.Worker do
  @moduledoc false
  alias Boss.{Repo, Runs}
  alias Boss.Checks.Candidate
  alias Boss.Agents.Process, as: Runner

  def execute(run, repo, manager) do
    Repo.put_dynamic_repo(repo)

    result =
      try do
        prepare(run, manager)
      rescue
        _ ->
          finish(run, "interrupted", "unknown", "Check outcome is unknown. Workspace retained.")
      catch
        _, _ ->
          finish(run, "interrupted", "unknown", "Check outcome is unknown. Workspace retained.")
      end

    send(manager, {:run_finished, run.id, self(), result})
  end

  defp prepare(run, manager) do
    parent = Runs.get(run.project_id, run.parent_run_id)

    with :ok <- continue(),
         {:ok, intent} <- Candidate.plan(parent.workspace, run.id),
         {:ok, run} <- Runs.update(run.id, workspace: intent),
         :ok <- continue(),
         {:ok, candidate} <- Candidate.prepare(intent),
         {:ok, run} <-
           Runs.update(run.id, candidate_commit: candidate.candidate_commit, status: "launching"),
         :ok <- continue(),
         :ok <- Candidate.verify(intent, candidate.candidate_commit),
         {:ok, executable, args} <- executable(run.check_config["argv"], candidate.path),
         :ok <- continue() do
      Runs.broadcast(run)
      invoke(run, executable, args, manager)
    else
      {:error, :cancelled} ->
        finish(run, "cancelled", "group_empty", "Stopped. Check workspace retained.")

      {:error, reason} when reason in [:cleanup_unknown, :storage_error] ->
        finish(
          run,
          "interrupted",
          "unknown",
          "Check preparation could not be confirmed. Workspace retained."
        )

      {:error, :command_unavailable} ->
        finish(
          run,
          "failed",
          "group_empty",
          "Check executable is unavailable. Review the command and BOSS PATH."
        )

      _ ->
        finish(
          run,
          "failed",
          "group_empty",
          "Candidate could not be captured or verified. Original files retained."
        )
    end
  end

  defp invoke(run, executable, args, manager) do
    started = DateTime.utc_now()
    owner = self()
    table = :ets.new(__MODULE__, [:public, :set])

    try do
      callback = fn
        {:started, pid} ->
          :ets.insert(table, {:pid, pid})

          send(
            manager,
            {:run_progress, run.id, owner, self(), make_ref(),
             [status: "running", os_pid: pid, started_at: started]}
          )

          :ok

        _ ->
          :ok
      end

      config = run.check_config

      result =
        Runner.run(executable, args,
          cd: run.workspace["path"],
          input: "",
          timeout_ms: config["timeout_ms"],
          output_limit: config["output_limit"],
          on_event: callback
        )

      {status, cleanup, reason} = outcome(result, run)

      pid =
        case :ets.lookup(table, :pid) do
          [{:pid, pid}] -> pid
          _ -> nil
        end

      Runs.update(run.id,
        status: status,
        cleanup: cleanup,
        reason: reason,
        os_pid: pid,
        started_at: started,
        finished_at: DateTime.utc_now(),
        exit_kind: if(result.exit_kind, do: to_string(result.exit_kind)),
        exit_code: result.exit_code,
        signal: result.signal,
        summary: %{"stdout_bytes" => result.stdout_bytes, "stderr_bytes" => result.stderr_bytes}
      )
    after
      :ets.delete(table)
    end
  end

  defp outcome(%{cleanup: cleanup}, _) when cleanup != :group_empty,
    do: {"interrupted", "unknown", "Check process cleanup is unknown. New attempts are blocked."}

  defp outcome(%{outcome: :cancelled}, _),
    do: {"cancelled", "group_empty", "Stopped. Check workspace retained."}

  defp outcome(
         %{outcome: :exited, exit_kind: :exit, exit_code: 0, eof: %{stdout: true, stderr: true}},
         run
       ) do
    case Candidate.verify(run.workspace, run.candidate_commit) do
      :ok ->
        {"finished", "group_empty",
         "Checks passed for this candidate commit. Independent review is still required."}

      {:error, :cleanup_unknown} ->
        {"interrupted", "unknown", "Final candidate verification was interrupted."}

      {:error, :cancelled} ->
        {"cancelled", "group_empty", "Stopped during candidate verification."}

      _ ->
        {"failed", "group_empty",
         "Check changed the candidate or its identity could not be verified. No passing receipt."}
    end
  end

  defp outcome(%{outcome: :timeout}, _),
    do: {"failed", "group_empty", "Check exceeded its time limit. Workspace retained."}

  defp outcome(_, _),
    do:
      {"failed", "group_empty",
       "Check did not finish cleanly. Inspect the exit status and retained workspace."}

  defp executable([name | args], path) do
    executable =
      if String.contains?(name, "/"),
        do: Path.expand(name, path),
        else: System.find_executable(name)

    if is_binary(executable) and File.regular?(executable),
      do: {:ok, executable, args},
      else: {:error, :command_unavailable}
  end

  defp finish(run, status, cleanup, reason),
    do:
      Runs.update(run.id,
        status: status,
        cleanup: cleanup,
        reason: reason,
        finished_at: DateTime.utc_now()
      )

  defp continue do
    receive do
      :stop -> {:error, :cancelled}
    after
      0 -> :ok
    end
  end
end
