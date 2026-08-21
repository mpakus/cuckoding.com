defmodule AgentDesk.A2A.Graph do
  @moduledoc """
  Task dependency DAG. Completing a prerequisite unblocks dependents that have
  no remaining incomplete edges.
  """

  import Ecto.Query

  alias AgentDesk.A2A.Dependency
  alias AgentDesk.A2A.Task
  alias AgentDesk.Events
  alias AgentDesk.Ids
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @done ~w(completed)

  @spec list_edges(Ecto.UUID.t()) :: [Dependency.t()]
  def list_edges(project_id) when is_binary(project_id) do
    Dependency
    |> where([d], d.project_id == ^project_id)
    |> order_by([d], asc: d.inserted_at)
    |> Repo.all()
  end

  @spec blockers(Ecto.UUID.t(), Ecto.UUID.t()) :: [Task.t()]
  def blockers(project_id, task_id) do
    ids =
      Dependency
      |> where([d], d.project_id == ^project_id and d.task_id == ^task_id)
      |> select([d], d.depends_on_id)
      |> Repo.all()

    Task
    |> where([t], t.id in ^ids)
    |> Repo.all()
  end

  @spec ensure_dependency(Scope.t(), Ecto.UUID.t(), Ecto.UUID.t()) :: :ok | {:error, term()}
  def ensure_dependency(%Scope{project: project} = scope, task_id, depends_on_id) do
    if edge_exists?(project.id, task_id, depends_on_id) do
      :ok
    else
      wrap_ensure(add_dependency(scope, task_id, depends_on_id))
    end
  end

  @spec add_dependency(Scope.t(), Ecto.UUID.t(), Ecto.UUID.t()) ::
          {:ok, Dependency.t()} | {:error, term()}
  def add_dependency(%Scope{project: project} = scope, task_id, depends_on_id) do
    with {:ok, task} <- fetch_task(project.id, task_id),
         {:ok, prereq} <- fetch_task(project.id, depends_on_id),
         :ok <- acyclic?(project.id, task.id, prereq.id) do
      %Dependency{}
      |> Dependency.changeset(%{
        id: Ids.generate(),
        project_id: project.id,
        task_id: task.id,
        depends_on_id: prereq.id
      })
      |> Repo.insert()
      |> maybe_block(scope, task)
    end
  end

  @spec release_ready(Task.t()) :: :ok
  def release_ready(%Task{status: status} = task) when status in @done do
    dependents =
      Dependency
      |> where([d], d.project_id == ^task.project_id and d.depends_on_id == ^task.id)
      |> Repo.all()

    Enum.each(dependents, &unblock_if_ready/1)
    :ok
  end

  def release_ready(%Task{}), do: :ok

  defp edge_exists?(project_id, task_id, depends_on_id) do
    Dependency
    |> where(
      [d],
      d.project_id == ^project_id and d.task_id == ^task_id and d.depends_on_id == ^depends_on_id
    )
    |> Repo.exists?()
  end

  defp wrap_ensure({:ok, _edge}), do: :ok
  defp wrap_ensure({:error, :cycle}), do: :ok
  defp wrap_ensure({:error, :not_found}), do: :ok
  defp wrap_ensure({:error, %Ecto.Changeset{}}), do: :ok
  defp wrap_ensure({:error, reason}), do: {:error, reason}

  defp fetch_task(project_id, id) do
    case Repo.get_by(Task, id: id, project_id: project_id) do
      %Task{} = task -> {:ok, task}
      nil -> {:error, :not_found}
    end
  end

  defp acyclic?(project_id, task_id, depends_on_id) do
    if reaches?(project_id, depends_on_id, task_id) do
      {:error, :cycle}
    else
      :ok
    end
  end

  defp reaches?(project_id, start_id, target_id) do
    walk([start_id], %{}, project_id, target_id)
  end

  defp walk([], _seen, _project_id, _target), do: false
  defp walk([target | _rest], _seen, _project_id, target), do: true

  defp walk([id | rest], seen, project_id, target) do
    if Map.has_key?(seen, id) do
      walk(rest, seen, project_id, target)
    else
      next = prereq_ids(project_id, id)
      walk(next ++ rest, Map.put(seen, id, true), project_id, target)
    end
  end

  defp prereq_ids(project_id, task_id) do
    Dependency
    |> where([d], d.project_id == ^project_id and d.task_id == ^task_id)
    |> select([d], d.depends_on_id)
    |> Repo.all()
  end

  defp maybe_block({:ok, edge} = result, scope, task) do
    _ = block_until_ready(task)
    emit(scope.project.id, "task.dependency_added", edge)
    result
  end

  defp maybe_block(error, _scope, _task), do: error

  defp block_until_ready(%Task{status: status} = task) when status in ["queued", "blocked"] do
    if ready?(task) do
      {:ok, task}
    else
      task
      |> Task.changeset(%{
        status: "blocked",
        status_reason: "waiting on dependencies",
        lock_version: task.lock_version + 1
      })
      |> Repo.update()
    end
  end

  defp block_until_ready(task), do: {:ok, task}

  defp unblock_if_ready(%Dependency{} = edge) do
    task = Repo.get!(Task, edge.task_id)

    if task.status == "blocked" and ready?(task) do
      {:ok, _} =
        task
        |> Task.changeset(%{
          status: "queued",
          status_reason: nil,
          lock_version: task.lock_version + 1
        })
        |> Repo.update()

      emit(task.project_id, "task.unblocked", edge)
    end
  end

  defp ready?(%Task{} = task) do
    prereqs = blockers(task.project_id, task.id)
    Enum.all?(prereqs, &(&1.status in @done))
  end

  defp emit(project_id, type, %Dependency{} = edge) do
    {:ok, _} =
      Events.append(%{
        project_id: project_id,
        type: type,
        source: "a2a",
        payload: %{"task_id" => edge.task_id, "depends_on_id" => edge.depends_on_id}
      })

    :ok
  end
end
