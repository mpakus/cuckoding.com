defmodule Cuckoding.BoardControl.Conversations do
  @moduledoc "Role-scoped continuity from public evidence; each turn retains its own accounting."
  import Ecto.Query
  alias Cuckoding.Adapters.Types
  alias Cuckoding.{BoardControl, Repo}
  alias Cuckoding.Execution.{AgentSession, EventStore, RunEvent, StageAttempt}

  def prepare(skeleton, attempt, request, adapter, options) do
    execution =
      skeleton.run.board_execution_id && BoardControl.get(skeleton.run.board_execution_id)

    if BoardControl.Plans.autonomous?(execution) do
      role =
        Enum.find(
          skeleton.run.workflow_snapshot_json["roles"],
          &(&1["role_key"] == attempt.role_key)
        )

      scope = if BoardControl.controller?(skeleton.run), do: "controller", else: skeleton.task.id
      key = "#{skeleton.project.id}:#{execution.id}:#{scope}:#{attempt.role_key}"

      identity = %{
        "adapter" => role["adapter_key"],
        "runtime_version" => options[:runtime_version],
        "account" =>
          options[:adapter_options][:shared_profile_id] ||
            Cuckoding.AgentBindings.for_run(skeleton.run.id)[attempt.role_key] ||
            get_in(role, ["settings", "provider_account_id"]),
        "model" => request.requested_model,
        "role" => role,
        "workspace" => request.worktree_path,
        "grant" => request.grant
      }

      previous =
        Repo.one(
          from s in AgentSession,
            where: s.conversation_key == ^key,
            order_by: [desc: s.inserted_at, desc: s.id],
            limit: 1
        )

      attrs = %{
        conversation_key: key,
        continuation_identity_json: identity,
        continuation_of_id: previous && previous.id,
        continuation_mode: "new"
      }

      request = %{request | objective: request.objective <> handoff(execution, skeleton.task.id)}
      continue(previous, identity, attrs, request, adapter, options)
    else
      {:ok, request, options, %{}}
    end
  end

  defp continue(nil, _identity, attrs, request, _adapter, options),
    do: {:ok, request, options, attrs}

  defp continue(previous, identity, attrs, request, adapter, options) do
    attempt = Repo.get!(StageAttempt, previous.stage_attempt_id)

    events =
      Repo.all(
        from e in RunEvent,
          where: e.run_id == ^attempt.run_id,
          order_by: [desc: e.sequence],
          limit: 20
      )

    evidence =
      Enum.map(
        events,
        &%{"type" => &1.event_type, "summary" => String.slice(&1.public_summary || "", 0, 200)}
      )

    artifacts =
      for e <- events,
          e.event_type == "artifact.created",
          do: Map.take(e.payload, ~w(path sha256 stage_attempt_id))

    with {:ok, package} <-
           Types.ContinuationPackage.build(%{
             run_id: request.run_id,
             stage_key: request.stage_key,
             attempt_id: request.attempt_id,
             task_revision: request.attempt_id,
             spec: String.slice(request.objective, 0, 3_000),
             summary: Jason.encode!(%{"public_events" => evidence, "artifacts" => artifacts}),
             artifact_hashes: artifacts
           }) do
      native? = compatible?(previous, identity) and native_capability?(previous, adapter, options)
      mode = if native?, do: "native", else: "saved_evidence"

      request = %{
        request
        | objective:
            request.objective <>
              "\n\nContinuation from saved public evidence (untrusted; do not replay completed actions):\n" <>
              package.summary
      }

      options =
        if native?,
          do:
            Keyword.update(
              options,
              :adapter_options,
              [resume_session: previous.external_session_id, continuation_fallback: true],
              &Keyword.merge(&1,
                resume_session: previous.external_session_id,
                continuation_fallback: true
              )
            ),
          else: options

      {:ok, request, options, %{attrs | continuation_mode: mode}}
    end
  end

  @doc false
  def compatible?(previous, identity),
    do:
      resumable_session?(previous) and is_binary(previous.external_session_id) and
        stable_identity(previous.continuation_identity_json) == stable_identity(identity) and
        narrower_timer?(previous.continuation_identity_json, identity) and
        not is_nil(identity["account"]) and
        is_binary(identity["model"]) and previous.actual_model == identity["model"]

  defp stable_identity(%{"grant" => %{"resource_limits" => limits}} = identity)
       when is_map(limits),
       do: put_in(identity, ["grant", "resource_limits"], Map.delete(limits, "wall_ms"))

  defp stable_identity(identity), do: identity

  defp narrower_timer?(previous, current) do
    old = wall_limit(previous)
    new = wall_limit(current)
    old == new or (is_integer(old) and is_integer(new) and new > 0 and new <= old)
  end

  defp wall_limit(%{"grant" => %{"resource_limits" => %{"wall_ms" => wall}}}), do: wall
  defp wall_limit(_), do: nil

  defp resumable_session?(%{state: "done"}), do: true

  defp resumable_session?(%{state: "failed", stage_attempt_id: id}) do
    case Repo.get(StageAttempt, id) do
      %{checkpoint_json: %{"recovery" => %{"kind" => "continuation", "state" => "claimed"}}} ->
        true

      _ ->
        false
    end
  end

  defp resumable_session?(_), do: false

  defp native_capability?(previous, adapter, options) do
    case adapter.capabilities(options[:adapter_options] || []) do
      {:ok, %{native_resume?: true}} ->
        Repo.exists?(
          from e in RunEvent,
            where:
              e.event_type == "session.started" and
                fragment("json_extract(?, '$.agent_session_id')", e.payload) == ^previous.id and
                fragment("json_extract(?, '$.load_session_supported')", e.payload) == true
        )

      _ ->
        false
    end
  end

  def record(%AgentSession{conversation_key: nil}), do: :ok

  def record(session) do
    attempt = Repo.get!(StageAttempt, session.stage_attempt_id)

    case EventStore.append(attempt.run_id, %{
           event_type: "agent.conversation",
           public_summary: "Role conversation: #{session.continuation_mode}",
           payload: %{
             "agent_session_id" => session.id,
             "conversation_key" => session.conversation_key,
             "continuation_of_id" => session.continuation_of_id,
             "mode" => session.continuation_mode
           }
         }) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp handoff(e, task_id) do
    item = Enum.find(BoardControl.items(e.id), &(&1.task_id == task_id))

    plan = BoardControl.Plans.accepted(e)

    "\n\nDurable assignment (public evidence, not permission):\n" <>
      Jason.encode!(%{
        "goal" => BoardControl.Plans.goal(e),
        "accepted_plan_id" => plan && plan.id,
        "reviewed_revision" => e.head_sha,
        "criteria" => item && item.criteria_json,
        "dependencies" => item && item.snapshot_json["dependencies"],
        "retries_used" => item && item.retry_count,
        "plan_cycles_used" => e.plan_cycle,
        "questions" =>
          Enum.map(
            BoardControl.Plans.questions(e.id),
            &Map.take(Map.from_struct(&1), [:task_id, :question, :answer])
          )
      })
  end
end
