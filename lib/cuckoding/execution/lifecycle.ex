defmodule Cuckoding.Execution.Lifecycle do
  @moduledoc "Durable pause, hibernate, resume, and owned-worktree cleanup orchestration."

  import Ecto.Query

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.LocalProcessRunner
  alias Cuckoding.Execution.PortAllocator
  alias Cuckoding.Execution.Run
  alias Cuckoding.Execution.StageAttempt
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo

  @active_attempt_states ~w(pending running waiting)
  @cancellable_states ~w(queued running waiting paused hibernated blocked)

  @doc "Persists the active stage checkpoint, verifies process ownership, and pauses scheduling."
  def pause(%Run{} = run, %Environment{} = environment, idempotency_key, options \\ []) do
    runner = Keyword.get(options, :runner, LocalProcessRunner)

    with {:ok, persisted_run, persisted_environment, attempt} <- context(run, environment),
         :ok <- require_state(persisted_run, ~w(running waiting)),
         {:ok, _checkpointed} <- checkpoint(attempt, options),
         {:ok, ^persisted_environment} <- runner.pause(persisted_environment, options),
         {:ok, command} <-
           Execution.transition_run(persisted_run.id, "paused", idempotency_key) do
      {:ok,
       %{command: command, environment: persisted_environment, stage_attempt: reload(attempt)}}
    end
  end

  @doc "Checkpoints, stops owned process groups, releases the port, and preserves the worktree."
  def hibernate(%Run{} = run, %Environment{} = environment, idempotency_key, options \\ []) do
    runner = Keyword.get(options, :runner, LocalProcessRunner)

    with {:ok, persisted_run, persisted_environment, attempt} <- context(run, environment),
         :ok <- require_state(persisted_run, ~w(running waiting paused)),
         {:ok, _checkpointed} <- checkpoint(attempt, options),
         :ok <- runner.hibernate(persisted_environment, options),
         {:ok, hibernated_environment} <-
           release_port(persisted_environment, "hibernated", options),
         {:ok, command} <-
           Execution.transition_run(persisted_run.id, "hibernated", idempotency_key) do
      {:ok,
       %{
         command: command,
         environment: hibernated_environment,
         stage_attempt: reload(attempt)
       }}
    end
  end

  @doc "Revalidates durable ownership, allocates a fresh port, and resumes the existing attempt."
  def resume(%Run{} = run, %Environment{} = environment, idempotency_key, options \\ []) do
    runner = Keyword.get(options, :runner, LocalProcessRunner)

    with {:ok, persisted_run, persisted_environment, attempt} <- context(run, environment),
         :ok <- require_state(persisted_run, ["hibernated"]),
         {:ok, _status} <- GitService.inspect(persisted_environment),
         {:ok, project} <- project(persisted_run.id),
         {:ok, ^persisted_environment} <- runner.resume(persisted_environment, options),
         {:ok, allocation} <- PortAllocator.allocate(project, persisted_environment, options) do
      finish_resume(persisted_run, attempt, allocation, idempotency_key, options)
    else
      {:drift, reason} -> {:error, {:resume_blocked, reason}}
      :missing -> {:error, :resume_worktree_missing}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stops owned resources, removes only the verified clean worktree, and retains artifacts."
  def destroy(%Run{} = run, %Environment{} = environment, idempotency_key, options \\ []) do
    runner = Keyword.get(options, :runner, LocalProcessRunner)

    with {:ok, persisted_run, persisted_environment, _attempt} <- context(run, environment),
         :ok <- runner.destroy(persisted_environment, options),
         {:ok, stopped_environment} <- release_port(persisted_environment, "stopped", options),
         {:ok, cleanup} <- GitService.cleanup(stopped_environment),
         {:ok, command} <- maybe_cancel(persisted_run, idempotency_key) do
      {:ok, Map.put(cleanup, :command, command)}
    end
  end

  defp finish_resume(run, attempt, allocation, idempotency_key, options) do
    result = resume_attempt(attempt, allocation, options)

    with {:ok, resume_result} <- result,
         {:ok, running_environment} <-
           Execution.update_environment_preview(allocation.environment, %{state: "running"}),
         {:ok, command} <- Execution.transition_run(run.id, "running", idempotency_key) do
      {:ok,
       %{
         allocation: %{allocation | environment: running_environment},
         command: command,
         resume_result: resume_result,
         stage_attempt: reload(attempt)
       }}
    else
      {:error, reason} -> release_failed_resume(allocation, reason)
    end
  end

  defp resume_attempt(nil, _allocation, _options), do: {:ok, :no_active_stage}

  defp resume_attempt(attempt, allocation, options) do
    callback =
      Keyword.get(options, :resume_stage, fn existing, _allocation -> {:ok, existing.id} end)

    case callback.(attempt, allocation) do
      {:ok, _result} = result -> result
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_resume_result}
    end
  end

  defp release_failed_resume(allocation, reason) do
    case PortAllocator.release(allocation, "hibernated") do
      {:ok, _environment} -> {:error, reason}
      {:error, release_reason} -> {:error, {:resume_failed, reason, release_reason}}
    end
  end

  defp checkpoint(nil, _options), do: {:ok, nil}

  defp checkpoint(attempt, options) do
    with {:ok, callback} <- Keyword.fetch(options, :checkpoint),
         true <- is_function(callback, 1),
         {:ok, checkpoint} when is_map(checkpoint) <- callback.(attempt),
         {:ok, {_event, checkpointed}} <-
           Execution.checkpoint_stage_attempt(attempt, checkpoint) do
      {:ok, checkpointed}
    else
      :error -> {:error, :checkpoint_required}
      false -> {:error, :invalid_checkpoint_callback}
      {:ok, _invalid} -> {:error, :invalid_checkpoint}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_checkpoint_result}
    end
  end

  defp release_port(%Environment{port: nil} = environment, state, _options),
    do: Execution.update_environment_preview(environment, %{state: state})

  defp release_port(environment, state, options) do
    case Keyword.fetch(options, :allocation) do
      {:ok, %PortAllocator.Allocation{} = allocation} ->
        release_allocation(allocation, environment, state)

      _other ->
        {:error, :port_allocation_required}
    end
  end

  defp release_allocation(allocation, environment, state) do
    if allocation.environment.id == environment.id and
         allocation.environment.port == environment.port,
       do: PortAllocator.release(allocation, state),
       else: {:error, :port_allocation_mismatch}
  end

  defp context(run, environment) do
    with %Run{} = persisted_run <- Repo.get(Run, run.id),
         %Environment{} = persisted_environment <- Repo.get(Environment, environment.id),
         true <- persisted_environment.run_id == persisted_run.id do
      {:ok, persisted_run, persisted_environment, active_attempt(persisted_run.id)}
    else
      nil -> {:error, :lifecycle_target_not_found}
      false -> {:error, :environment_run_mismatch}
    end
  end

  defp active_attempt(run_id) do
    Repo.one(
      from(attempt in StageAttempt,
        where: attempt.run_id == ^run_id and attempt.state in ^@active_attempt_states
      )
    )
  end

  defp project(run_id) do
    query =
      from(project in Project,
        join: board in Cuckoding.Workflows.Board,
        on: board.project_id == project.id,
        join: task in Cuckoding.Workflows.Task,
        on: task.board_id == board.id,
        join: run in Run,
        on: run.task_id == task.id,
        where: run.id == ^run_id
      )

    case Repo.one(query) do
      %Project{} = project -> {:ok, project}
      nil -> {:error, :project_not_found}
    end
  end

  defp require_state(%Run{state: state}, states) do
    if state in states, do: :ok, else: {:error, {:invalid_lifecycle_state, state}}
  end

  defp maybe_cancel(%Run{state: state} = run, key) when state in @cancellable_states,
    do: Execution.transition_run(run.id, "cancelled", key)

  defp maybe_cancel(_run, _key), do: {:ok, nil}

  defp reload(nil), do: nil
  defp reload(attempt), do: Repo.get!(StageAttempt, attempt.id)
end
