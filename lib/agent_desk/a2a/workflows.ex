defmodule AgentDesk.A2A.Workflows do
  @moduledoc """
  Save and instantiate reusable task graphs.
  """

  import Ecto.Query

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Context
  alias AgentDesk.A2A.Graph
  alias AgentDesk.A2A.Workflow
  alias AgentDesk.Ids
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec list(Scope.t()) :: [Workflow.t()]
  def list(%Scope{project: project}) do
    Workflow
    |> where([w], w.project_id == ^project.id)
    |> order_by([w], asc: w.name)
    |> Repo.all()
  end

  @spec save(Scope.t(), map()) :: {:ok, Workflow.t()} | {:error, term()}
  def save(%Scope{project: project}, attrs) do
    steps = workflow_steps(attrs)
    name = Map.get(attrs, :name) || Map.get(attrs, "name")
    description = Map.get(attrs, :description) || Map.get(attrs, "description") || ""

    %Workflow{}
    |> Workflow.changeset(%{
      id: Ids.generate(),
      project_id: project.id,
      name: name,
      description: description,
      definition: %{"steps" => steps}
    })
    |> Repo.insert()
  end

  @spec upsert(Scope.t(), map()) :: {:ok, Workflow.t()} | {:error, term()}
  def upsert(%Scope{project: project} = scope, attrs) when is_map(attrs) do
    name = Map.get(attrs, :name) || Map.get(attrs, "name")
    upsert_named(scope, project.id, name, attrs)
  end

  @spec instantiate(Scope.t(), Ecto.UUID.t(), Context.t()) ::
          {:ok, [A2A.Task.t()]} | {:error, term()}
  def instantiate(%Scope{} = scope, workflow_id, %Context{} = context) do
    with {:ok, workflow} <- fetch(scope.project.id, workflow_id) do
      run_steps(scope, context, steps_of(workflow))
    end
  end

  @spec instantiate_linear(Scope.t(), Context.t(), String.t(), [String.t()]) ::
          {:ok, [A2A.Task.t()]} | {:error, term()}
  def instantiate_linear(%Scope{} = scope, %Context{} = context, name, titles)
      when is_list(titles) do
    steps =
      titles
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> linear_steps()

    with {:ok, workflow} <- save(scope, %{name: name, steps: steps}) do
      instantiate(scope, workflow.id, context)
    end
  end

  defp upsert_named(_scope, _project_id, name, _attrs) when not is_binary(name) do
    {:error, :invalid_workflow}
  end

  defp upsert_named(_scope, _project_id, "", _attrs), do: {:error, :invalid_workflow}

  defp upsert_named(scope, project_id, name, attrs) do
    case Repo.get_by(Workflow, project_id: project_id, name: name) do
      %Workflow{} = existing -> update_existing(existing, attrs)
      nil -> save(scope, attrs)
    end
  end

  defp update_existing(existing, attrs) do
    existing
    |> Workflow.changeset(%{
      description: Map.get(attrs, :description) || Map.get(attrs, "description") || "",
      definition: %{"steps" => workflow_steps(attrs)}
    })
    |> Repo.update()
  end

  defp workflow_steps(attrs) do
    attrs
    |> steps_from_attrs()
    |> normalize_steps()
  end

  defp steps_from_attrs(attrs) do
    [
      Map.get(attrs, :steps),
      Map.get(attrs, "steps"),
      nested_steps(Map.get(attrs, :definition) || Map.get(attrs, "definition"))
    ]
    |> Enum.find(&is_list/1)
    |> Kernel.||([])
  end

  defp nested_steps(%{"steps" => steps}), do: steps
  defp nested_steps(%{steps: steps}), do: steps
  defp nested_steps(_definition), do: nil

  defp fetch(project_id, id) do
    case Repo.get_by(Workflow, id: id, project_id: project_id) do
      %Workflow{} = workflow -> {:ok, workflow}
      nil -> {:error, :not_found}
    end
  end

  defp steps_of(%Workflow{definition: definition}) do
    List.wrap(definition["steps"] || definition[:steps])
  end

  defp run_steps(scope, context, steps) do
    with {:ok, pairs} <- create_all(scope, context, steps) do
      link_created(scope, steps, pairs)
      {:ok, Enum.map(pairs, fn {_key, task} -> task end)}
    end
  end

  defp link_created(scope, steps, pairs) do
    ids = Map.new(pairs, fn {key, task} -> {key, task.id} end)
    Enum.each(steps, &link_step(scope, &1, ids))
  end

  defp link_step(scope, step, ids) do
    case Map.fetch(ids, key(step)) do
      {:ok, task_id} -> link_prereqs(scope, task_id, step, ids)
      :error -> :ok
    end
  end

  defp create_all(scope, context, steps) do
    Enum.reduce_while(steps, {:ok, []}, fn step, {:ok, acc} ->
      title = step["title"] || step[:title]
      step_key = key(step)

      case A2A.create_task(scope, context, %{
             title: title,
             metadata: %{"workflow_key" => step_key}
           }) do
        {:ok, task} -> {:cont, {:ok, acc ++ [{step_key, task}]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp link_prereqs(scope, task_id, step, ids) do
    deps = List.wrap(step["depends_on"] || step[:depends_on])

    Enum.each(deps, fn dep_key ->
      case Map.fetch(ids, to_string(dep_key)) do
        {:ok, prereq_id} -> Graph.add_dependency(scope, task_id, prereq_id)
        :error -> :ok
      end
    end)
  end

  defp key(step), do: to_string(step["key"] || step[:key] || step["title"] || step[:title])

  defp normalize_steps(steps) when is_list(steps) do
    Enum.map(steps, fn
      title when is_binary(title) -> %{"key" => title, "title" => title, "depends_on" => []}
      step when is_map(step) -> stringify_step(step)
    end)
  end

  defp normalize_steps(_), do: []

  defp stringify_step(step) do
    %{
      "key" => to_string(step[:key] || step["key"] || step[:title] || step["title"]),
      "title" => to_string(step[:title] || step["title"] || "Task"),
      "depends_on" => Enum.map(List.wrap(step[:depends_on] || step["depends_on"]), &to_string/1)
    }
  end

  defp linear_steps(titles) do
    titles
    |> Enum.with_index()
    |> Enum.map(fn {title, index} ->
      deps = if index == 0, do: [], else: [Integer.to_string(index - 1)]
      %{"key" => Integer.to_string(index), "title" => title, "depends_on" => deps}
    end)
  end
end
