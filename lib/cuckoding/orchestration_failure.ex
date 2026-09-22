defmodule Cuckoding.OrchestrationFailure do
  @moduledoc "Persists safe failure evidence and blocks a failed orchestration run."

  import Ecto.Query

  alias Cuckoding.Adapters.Types
  alias Cuckoding.Execution
  alias Cuckoding.Execution.AgentSession
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Repo

  def guard(run_id, kind, callback)
      when is_binary(run_id) and kind in [:task_intake, :workflow] and
             is_function(callback, 0) do
    case callback.() do
      {:error, reason} = error ->
        fail(run_id, kind, reason)
        error

      result ->
        result
    end
  rescue
    _error ->
      fail(run_id, kind, {:unexpected_failure, safe_site(__STACKTRACE__)})
      {:error, :unexpected_failure}
  catch
    _kind, _reason ->
      fail(run_id, kind, {:unexpected_failure, safe_site(__STACKTRACE__)})
      {:error, :unexpected_failure}
  end

  def fail(run_id, kind, reason)
      when is_binary(run_id) and kind in [:task_intake, :workflow] do
    summary = public_failure(kind, reason)
    {attempt, session} = latest_context(run_id)

    _recorded = record(run_id, kind, reason, summary, attempt, session)
    _attempt = fail_attempt(attempt, kind)
    _run = block_run(run_id, kind, summary)
    :ok
  end

  defp record(run_id, kind, reason, summary, attempt, session) do
    payload =
      %{"code" => failure_code(kind, reason)}
      |> maybe_put("stage_attempt_id", attempt && attempt.id)
      |> maybe_put("agent_session_id", session && session.id)
      |> maybe_put("diagnostic_site", failure_site(reason))

    projection = fn repo, _sequence ->
      if session,
        do: repo.update(AgentSession.observation_changeset(session, %{state: "failed"})),
        else: {:ok, nil}
    end

    EventStore.append(
      run_id,
      %{
        event_type: event_type(kind),
        public_summary: summary,
        payload: payload
      },
      projection
    )
  end

  defp latest_context(run_id) do
    attempt =
      Repo.one(
        from(attempt in StageAttempt,
          where: attempt.run_id == ^run_id,
          order_by: [desc: attempt.inserted_at, desc: attempt.id],
          limit: 1
        )
      )

    session =
      if attempt do
        Repo.one(
          from(session in AgentSession,
            where: session.stage_attempt_id == ^attempt.id,
            order_by: [desc: session.inserted_at, desc: session.id],
            limit: 1
          )
        )
      end

    {attempt, session}
  end

  defp fail_attempt(%StageAttempt{state: "running"} = attempt, kind) do
    Execution.transition_stage_attempt(
      attempt.id,
      "failed",
      "#{kind}:#{attempt.id}:failed"
    )
  end

  defp fail_attempt(_attempt, _kind), do: :ok

  defp block_run(run_id, kind, summary) do
    case Repo.get(Run, run_id) do
      %Run{state: "running"} ->
        Execution.transition_run(run_id, "blocked", "#{kind}:#{run_id}:blocked",
          wait_reason: summary
        )

      _run ->
        :ok
    end
  end

  defp public_failure(:task_intake, :invalid_output_schema),
    do:
      "The agent runtime rejected Cuckoding's task output schema. Update Cuckoding and create a new planning run."

  defp public_failure(:task_intake, :invalid_task_proposals),
    do:
      "The agent returned task proposals that failed validation. Review the cited files and create a new planning run."

  defp public_failure(:task_intake, {:adapter_exit, status}) when is_integer(status),
    do:
      "The planning agent exited with status #{status}. Inspect the redacted process log and create a new planning run."

  defp public_failure(:task_intake, %Types.Error{category: :malformed_output}),
    do:
      "Cuckoding could not read the agent's structured task response. Inspect the redacted process log and create a new planning run."

  defp public_failure(:task_intake, {:unexpected_failure, _site}),
    do:
      "Task planning stopped unexpectedly. Inspect recent activity and the redacted process log, then create a new planning run."

  defp public_failure(:task_intake, _reason),
    do: "Task planning failed. Inspect recent activity and create a new planning run."

  defp public_failure(:workflow, {:adapter_exit, status}) when is_integer(status),
    do:
      "The agent exited with status #{status}. Inspect the redacted process log before retrying this task."

  defp public_failure(:workflow, :review_attempt_budget_exceeded),
    do:
      "Review still found blocking issues after three correction attempts. Inspect the findings and logs before retrying."

  defp public_failure(:workflow, :invalid_review_output),
    do:
      "The reviewer returned an invalid result. Inspect the redacted process log before retrying."

  defp public_failure(:workflow, %Types.Error{category: :malformed_output}),
    do:
      "Cuckoding could not read the agent's structured response. Inspect the redacted process log before retrying."

  defp public_failure(:workflow, {:unexpected_failure, _site}),
    do:
      "The workflow stopped unexpectedly. Its safe failure code, timeline, and available process logs were preserved for inspection."

  defp public_failure(:workflow, _reason),
    do:
      "The workflow failed. Inspect its timeline, findings, and redacted process logs before retrying."

  defp failure_code(_kind, {:adapter_exit, _status}), do: "adapter_exit"
  defp failure_code(_kind, {:unexpected_failure, _site}), do: "unexpected_failure"

  defp failure_code(_kind, %Types.Error{code: {code, _detail}}) when is_atom(code),
    do: Atom.to_string(code)

  defp failure_code(_kind, %Types.Error{code: code}) when is_atom(code),
    do: Atom.to_string(code)

  defp failure_code(_kind, %Types.Error{}), do: "adapter_error"
  defp failure_code(_kind, reason) when is_atom(reason), do: Atom.to_string(reason)
  defp failure_code(:task_intake, _reason), do: "task_intake_failed"
  defp failure_code(:workflow, _reason), do: "workflow_failed"

  defp event_type(:task_intake), do: "task_intake.failed"
  defp event_type(:workflow), do: "workflow.failed"

  defp failure_site({:unexpected_failure, site}), do: site
  defp failure_site(_reason), do: nil

  defp safe_site(stacktrace), do: Enum.find_value(stacktrace, &site/1)

  defp site({module, function, arity, location})
       when is_atom(module) and is_atom(function) and
              is_integer(arity) and is_list(location) do
    name = Atom.to_string(module)
    line = Keyword.get(location, :line)
    source = "#{String.replace_prefix(name, "Elixir.", "")}.#{function}/#{arity}:#{line}"

    if String.starts_with?(name, "Elixir.Cuckoding.") and module != __MODULE__ and
         is_integer(line) and line > 0 and byte_size(source) <= 200,
       do: source
  end

  defp site(_frame), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
