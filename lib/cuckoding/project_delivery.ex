defmodule Cuckoding.ProjectDelivery do
  @moduledoc "The project entry point for Describe → Run; the board remains the execution owner."
  alias Cuckoding.{BoardControl, Projects, ProjectWorkflow, Repo, Workflows}
  alias Cuckoding.Execution.{Command, Commands}

  def board(project_id) do
    case Repo.get_by(Command, idempotency_key: board_key(project_id)) do
      %{result: %{"board_id" => id}} -> Workflows.get_board(id)
      _ -> nil
    end
  end

  def prepare(project_id, brief, key) when is_binary(brief) do
    with true <- byte_size(brief) in 1..20_000 and String.trim(brief) != "",
         project when not is_nil(project) <- Projects.get_project(project_id),
         {:ok, board} <- ensure_board(project.id) do
      prepare_board(board, BoardControl.current(board.id), brief, key)
    else
      false -> {:error, :invalid_goal_or_limits}
      nil -> {:error, :project_not_found}
      error -> error
    end
  end

  def prepare(_project_id, _brief, _key), do: {:error, :invalid_goal_or_limits}

  defp prepare_board(board, nil, brief, key), do: BoardControl.prepare_goal(board.id, brief, key)

  defp prepare_board(_board, e, brief, _key) do
    if BoardControl.Plans.preparing?(e) and e.preparation_json["brief"] == String.trim(brief),
      do: {:ok, e},
      else: {:error, :project_goal_in_progress}
  end

  defp ensure_board(project_id) do
    with {:ok, %{result: %{"board_id" => id}}} <-
           Commands.execute_once(
             %{
               idempotency_key: board_key(project_id),
               kind: "project.delivery_board",
               target_type: "project",
               target_id: project_id
             },
             fn _ -> create_board(project_id) end
           ),
         do: {:ok, Workflows.get_board(id)}
  end

  defp create_board(project_id) do
    with {:ok, board} <-
           ProjectWorkflow.create_board(project_id, %{
             "name" => "Delivery",
             "description" => "Project goals and reviewed local results",
             "concurrency_limit" => "1"
           }),
         do: {:ok, %{"board_id" => board.id}}
  end

  defp board_key(id), do: "project:#{id}:delivery-board"
end
