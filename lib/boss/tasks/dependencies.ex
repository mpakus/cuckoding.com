defmodule Boss.Tasks.Dependencies do
  @moduledoc "Reads dependency gates from pinned sources inside the caller's Repo transaction."

  import Ecto.Query
  alias Boss.Projects.{Spec, SpecDocument, SpecRevision}
  alias Boss.Repo
  alias Boss.Tasks.Task

  @max_nodes 64
  @max_source_bytes 8 * 1_048_576
  @budget_ms 1_000
  @max_issues 33

  def check(project_id, task_id) do
    case snapshot(project_id, task_id) do
      {:ok, %{ready?: true}} -> :ok
      {:ok, snapshot} -> {:error, {:dependencies_blocked, snapshot}}
      error -> error
    end
  end

  def snapshot(project_id, task_id) when is_integer(project_id) and is_integer(task_id) do
    context = %{
      project_id: project_id,
      deadline: System.monotonic_time(:millisecond) + @budget_ms,
      nodes: %{},
      references: %{},
      visited: MapSet.new(),
      source_bytes: 0,
      issues: [],
      halted?: false
    }

    case Repo.one(
           from [task, spec] in node_query(),
             where: task.id == ^task_id and spec.project_id == ^project_id
         ) do
      nil ->
        {:error, :not_found}

      row ->
        {node, context} = load_node(row, context)
        context = visit(node, nil, MapSet.new(), context)
        {dependencies, context} = direct_dependencies(node, context)

        {:ok,
         %{
           ready?: context.issues == [],
           dependencies: dependencies,
           issues: Enum.reverse(context.issues)
         }}
    end
  end

  def snapshot(_, _), do: {:error, :not_found}

  defp node_query do
    from task in Task,
      join: spec in Spec,
      on: spec.id == task.spec_id,
      left_join: revision in SpecRevision,
      on: revision.id == task.spec_revision_id and revision.spec_id == spec.id,
      select: %{
        task_id: task.id,
        title: task.title,
        state: task.state,
        missing: spec.missing,
        identity_key: spec.identity_key,
        source: revision.original_text
      }
  end

  defp load_node(row, context) do
    cond do
      Map.has_key?(context.nodes, row.task_id) ->
        {context.nodes[row.task_id], context}

      map_size(context.nodes) >= @max_nodes ->
        {nil, halt(context, "Dependency graph exceeds 64 tasks.")}

      context.source_bytes + source_size(row.source) > @max_source_bytes ->
        {nil, halt(context, "Dependency graph source exceeds 8 MiB.")}

      expired?(context) ->
        {nil, halt(context, "Dependency graph exceeded its traversal time budget.")}

      true ->
        result = SpecDocument.dependencies(row.source)
        node = row |> Map.delete(:source) |> Map.put(:dependencies, result)

        context = %{
          context
          | nodes: Map.put(context.nodes, node.task_id, node),
            source_bytes: context.source_bytes + source_size(row.source)
        }

        context =
          case node.identity_key do
            "id:" <> reference ->
              %{context | references: Map.put(context.references, reference, node.task_id)}

            _ ->
              context
          end

        if expired?(context),
          do: {nil, halt(context, "Dependency graph exceeded its traversal time budget.")},
          else: {node, context}
    end
  end

  defp source_size(source) when is_binary(source), do: byte_size(source)
  defp source_size(_), do: 0

  defp resolve(reference, context) do
    case Map.fetch(context.references, reference) do
      {:ok, task_id} ->
        {context.nodes[task_id], context}

      :error ->
        identity = "id:" <> reference
        project_id = context.project_id

        case Repo.one(
               from [_, spec] in node_query(),
                 where: spec.project_id == ^project_id and spec.identity_key == ^identity
             ) do
          nil ->
            {nil, %{context | references: Map.put(context.references, reference, nil)}}

          row ->
            load_node(row, context)
        end
    end
  end

  defp visit(_, _, _, %{halted?: true} = context), do: context

  defp visit(node, reference, path, context) do
    cond do
      expired?(context) ->
        halt(context, "Dependency graph exceeded its traversal time budget.")

      MapSet.member?(path, node.task_id) ->
        issue(
          context,
          :cycle,
          reference,
          node.task_id,
          "Dependency cycle includes #{node.title}."
        )

      MapSet.member?(context.visited, node.task_id) ->
        context

      true ->
        context =
          if node.missing and node.state != "done",
            do:
              issue(
                context,
                :missing,
                reference,
                node.task_id,
                "Source for #{node.title} is missing and the task is not Done."
              ),
            else: context

        context =
          case node.dependencies do
            {:error, reason} ->
              issue(
                context,
                :invalid,
                reference,
                node.task_id,
                "Invalid dependencies for #{node.title}: #{reason}"
              )

            {:ok, references} ->
              path = MapSet.put(path, node.task_id)

              Enum.reduce_while(references, context, fn reference, context ->
                context = visit_reference(reference, path, context)
                if context.halted?, do: {:halt, context}, else: {:cont, context}
              end)
          end

        %{context | visited: MapSet.put(context.visited, node.task_id)}
    end
  end

  defp visit_reference(reference, path, context) do
    if expired?(context) do
      halt(context, "Dependency graph exceeded its traversal time budget.")
    else
      case resolve(reference, context) do
        {_, %{halted?: true} = context} ->
          context

        {nil, context} ->
          issue(
            context,
            :missing,
            reference,
            nil,
            "No task has the explicit ID #{reference} in this project."
          )

        {node, context} ->
          visit(node, reference, path, context)
      end
    end
  end

  defp direct_dependencies(_, %{halted?: true} = context), do: {[], context}
  defp direct_dependencies(%{dependencies: {:error, _}}, context), do: {[], context}

  defp direct_dependencies(%{dependencies: {:ok, references}}, context) do
    Enum.map_reduce(references, context, fn reference, context ->
      node = context.nodes[context.references[reference]]

      dependency = %{
        reference: reference,
        task_id: node && node.task_id,
        title: node && node.title,
        state: node && node.state,
        missing: is_nil(node) or node.missing,
        satisfied?: not is_nil(node) and node.state == "done"
      }

      context =
        if node && not dependency.satisfied? && not node.missing,
          do:
            issue(
              context,
              :waiting,
              reference,
              node.task_id,
              "Waiting for #{node.title} to reach Done."
            ),
          else: context

      {dependency, context}
    end)
  end

  defp expired?(context), do: System.monotonic_time(:millisecond) >= context.deadline

  defp halt(context, message) do
    issue = %{kind: :limit, reference: nil, task_id: nil, message: message}
    %{context | halted?: true, issues: [issue | Enum.take(context.issues, @max_issues - 1)]}
  end

  defp issue(context, kind, reference, task_id, message) do
    if length(context.issues) < @max_issues,
      do: %{
        context
        | issues: [
            %{kind: kind, reference: reference, task_id: task_id, message: message}
            | context.issues
          ]
      },
      else: context
  end
end
