defmodule Boss.Runs.Worker do
  @moduledoc false
  alias Boss.{Repo, Runs}
  alias Boss.Agents.{Codex, Workspace}
  alias Boss.Agents.Process, as: Runner

  def execute(run, repo, manager) do
    Repo.put_dynamic_repo(repo)
    result = perform(run, manager)
    send(manager, {:run_finished, run.id, self(), result})
  catch
    # An unexpected storage/worker failure must never produce a guessed receipt.
    _, _ ->
      send(
        manager,
        {:run_finished, run.id, self(),
         terminal(
           run,
           "interrupted",
           "unknown",
           "Run interrupted without a final receipt. Workspace retained."
         )}
      )
  end

  defp perform(run, manager) do
    {project, revision} = Runs.inputs(run)

    with executable when is_binary(executable) <- System.find_executable("codex"),
         {:ok, prompt} <- Codex.prompt(revision.original_text),
         :ok <- continue?(),
         {:ok, intent} <- Workspace.plan(project, run.id),
         {:ok, run} <-
           Runs.update(run.id,
             workspace: Map.new(intent, fn {key, value} -> {to_string(key), value} end)
           ),
         :ok <- continue?(),
         {:ok, _} <- Workspace.prepare(intent),
         :ok <- continue?(),
         {:ok, run} <- Runs.update(run.id, status: "launching"),
         :ok <- continue?() do
      Runs.broadcast(run)
      invoke(run, executable, prompt, manager)
    else
      nil ->
        terminal(
          run,
          "failed",
          "not_started",
          "Codex was not found in BOSS's PATH. Install it and restart BOSS."
        )

      {:error, :cancelled} ->
        terminal(run, "cancelled", "not_started", "Stopped before the agent was launched.")

      {:error, :cleanup_unknown} ->
        terminal(
          run,
          "interrupted",
          "unknown",
          "Workspace command cleanup is unknown. Retained for inspection."
        )

      {:error, :storage_error} ->
        terminal(
          run,
          "interrupted",
          "unknown",
          "Storage outcome is unknown. No automatic restart."
        )

      {:error, :input_too_large} ->
        terminal(
          run,
          "failed",
          "not_started",
          "Saved specification plus instructions exceeds the 1 MiB prompt limit."
        )

      {:error, _} ->
        terminal(
          run,
          "failed",
          "not_started",
          "Workspace preparation failed. Verify the saved repository/base branch and Git configuration."
        )
    end
  end

  defp invoke(run, executable, prompt, manager) do
    owner = self()
    table = :ets.new(__MODULE__, [:public, :set])
    :ets.insert(table, {:parser, Codex.new()})

    try do
      # One progress message can be outstanding; DB stalls never grow a run mailbox.
      callback = fn event ->
        [{:parser, parser}] = :ets.lookup(table, :parser)
        parser = Codex.feed(parser, event)
        :ets.insert(table, {:parser, parser})

        pid =
          case event do
            {:started, pid} -> pid
            _ -> nil
          end

        if pid, do: :ets.insert(table, [{:os_pid, pid}, {:started_at, DateTime.utc_now()}])
        progress(manager, run.id, owner, table, parser)
        if parser.error, do: :stop, else: :ok
      end

      result =
        Runner.run(executable, Codex.args(),
          cd: run.workspace["path"],
          input: prompt,
          timeout_ms: 1_200_000,
          output_limit: 8_388_608,
          on_event: callback
        )

      [{:parser, parser}] = :ets.lookup(table, :parser)
      attrs = receipt(result, parser)
      attrs = Keyword.put(attrs, :summary, Codex.summary(parser))

      attrs =
        case :ets.lookup(table, :os_pid) do
          [{_, pid}] ->
            [{_, started}] = :ets.lookup(table, :started_at)
            attrs |> Keyword.put(:os_pid, pid) |> Keyword.put(:started_at, started)

          _ ->
            attrs
        end

      # A lost helper is never followed by another command in the retained workspace.
      attrs =
        if result.cleanup == :group_empty do
          case Workspace.inspect(run.workspace) do
            {:ok, workspace} ->
              Keyword.put(
                attrs,
                :head_commit,
                workspace[:head_commit] || workspace["head_commit"]
              )

            {:error, :cleanup_unknown} ->
              [
                status: "interrupted",
                cleanup: "unknown",
                reason: "Final workspace inspection was interrupted."
              ] ++ Keyword.drop(attrs, [:status, :cleanup, :reason])

            _ ->
              attrs
          end
        else
          attrs
        end

      Runs.update(run.id, Keyword.put(attrs, :finished_at, DateTime.utc_now()))
    after
      :ets.delete(table)
    end
  end

  defp progress(manager, id, owner, table, parser) do
    pending = Process.get(:boss_progress)

    pending =
      if pending do
        receive do
          {:run_progress_ack, ^pending} -> nil
        after
          0 -> pending
        end
      end

    now = System.monotonic_time(:millisecond)

    if is_nil(pending) and now - Process.get(:boss_progress_time, now - 500) >= 500 do
      ref = make_ref()
      attrs = [summary: Codex.summary(parser), status: "running"]

      attrs =
        case :ets.lookup(table, :os_pid) do
          [{_, pid}] ->
            [{_, started}] = :ets.lookup(table, :started_at)
            [os_pid: pid, started_at: started] ++ attrs

          _ ->
            attrs
        end

      send(manager, {:run_progress, id, owner, self(), ref, attrs})
      Process.put(:boss_progress, ref)
      Process.put(:boss_progress_time, now)
    else
      Process.put(:boss_progress, pending)
    end

    :ok
  end

  @doc false
  def receipt(result, parser) do
    {status, reason} =
      cond do
        result.cleanup != :group_empty ->
          {"interrupted",
           if(result.outcome == :cancelled,
             do:
               "Stop was requested, but process-group cleanup is unknown. Workspace retained; no automatic restart.",
             else: "Process-group cleanup is unknown. Workspace retained; no automatic restart."
           )}

        result.outcome == :cancelled and Map.get(result, :reason) != :consumer_stopped ->
          {"cancelled", "Stopped. Workspace retained."}

        result.outcome == :timeout ->
          {"failed", "Run exceeded its time limit. Workspace retained."}

        parser.error ->
          {"failed",
           "Codex output was invalid, exceeded limits, or reported an error. Workspace retained."}

        result.outcome == :cancelled ->
          {"cancelled", "Stopped. Workspace retained."}

        result.outcome == :exited and result.exit_kind == :exit and result.exit_code == 0 and
          result.eof == %{stdout: true, stderr: true} and Codex.complete?(parser) ->
          {"finished",
           "Codex finished. Changes are unverified; task approval and merge are separate."}

        true ->
          {"failed",
           "Codex did not finish cleanly. Check its local installation/authentication and retained workspace."}
      end

    [
      status: status,
      reason: reason,
      cleanup: to_string(result.cleanup),
      exit_kind: if(result.exit_kind, do: to_string(result.exit_kind)),
      exit_code: result.exit_code,
      signal: result.signal
    ]
  end

  defp terminal(run, status, cleanup, reason),
    do:
      Runs.update(run.id,
        status: status,
        cleanup: cleanup,
        reason: reason,
        finished_at: DateTime.utc_now()
      )

  defp continue? do
    receive do
      :stop -> {:error, :cancelled}
    after
      0 -> :ok
    end
  end
end
