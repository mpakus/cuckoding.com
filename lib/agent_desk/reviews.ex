defmodule AgentDesk.Reviews do
  @moduledoc """
  Review/merge queue. Acceptance is durable; Git integration is explicit and
  never runs when policy gates fail.
  """

  import Ecto.Query

  alias AgentDesk.A2A.Artifact
  alias AgentDesk.Clock
  alias AgentDesk.Events
  alias AgentDesk.Git
  alias AgentDesk.Ids
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Reviews.Item
  alias AgentDesk.Reviews.Policy
  alias AgentDesk.Scope
  alias AgentDesk.Worktrees
  alias AgentDesk.Worktrees.Worktree

  @spec list_open(Project.t() | Ecto.UUID.t()) :: [Item.t()]
  def list_open(%Project{id: id}), do: list_open(id)

  def list_open(project_id) when is_binary(project_id) do
    Item
    |> where([i], i.project_id == ^project_id and i.status in ["queued", "accepted"])
    |> order_by([i], desc: i.inserted_at)
    |> Repo.all()
  end

  @spec enqueue(Scope.t(), Artifact.t(), map()) :: {:ok, Item.t()} | {:error, term()}
  def enqueue(%Scope{} = scope, %Artifact{} = artifact, attrs) do
    project = Repo.get!(Project, scope.project.id)
    worktree = session_worktree(scope)
    checks = List.wrap(Map.get(attrs, :checks) || Map.get(attrs, "checks"))
    report = Policy.evaluate(project, checks)
    commit = commit_sha(artifact, attrs)
    branch = branch_name(worktree, artifact)
    target = project.default_branch || "HEAD"

    attrs = %{
      id: Ids.generate(),
      project_id: project.id,
      artifact_id: artifact.id,
      agent_session_id: scope.agent_session && scope.agent_session.id,
      worktree_id: worktree && worktree.id,
      branch_name: branch,
      commit_sha: commit,
      target_ref: target,
      summary: summary(attrs),
      status: "queued",
      policy_status: report.status,
      policy_report: stringify(report)
    }

    %Item{}
    |> Item.changeset(attrs)
    |> Repo.insert()
    |> tap_event(project.id, "merge_queue.enqueued")
    |> tap_broadcast(project.id)
  end

  @spec accept(Scope.t(), Ecto.UUID.t()) :: {:ok, Item.t()} | {:error, term()}
  def accept(%Scope{} = scope, artifact_id) when is_binary(artifact_id) do
    with {:ok, item} <- fetch_item(scope.project.id, artifact_id) do
      transition(scope, item, "accepted", fn item ->
        Item.changeset(item, %{
          status: "accepted",
          accepted_by_id: scope.agent_session && scope.agent_session.id
        })
      end)
    end
  end

  @spec reject(Scope.t(), Ecto.UUID.t()) :: {:ok, Item.t()} | {:error, term()}
  def reject(%Scope{} = scope, artifact_id) when is_binary(artifact_id) do
    with {:ok, item} <- fetch_item(scope.project.id, artifact_id) do
      transition(scope, item, "rejected", fn item ->
        Item.changeset(item, %{status: "rejected"})
      end)
    end
  end

  @spec merge(Project.t(), Ecto.UUID.t()) :: {:ok, Item.t()} | {:error, term()}
  def merge(%Project{} = project, item_id) when is_binary(item_id) do
    project = Repo.get!(Project, project.id)

    with {:ok, item} <- get_item(project.id, item_id),
         :ok <- mergeable?(project, item),
         {:ok, _sha} <-
           Git.merge_commit(project.canonical_path, item.commit_sha, merge_message(item)) do
      now = Clock.utc_now()

      item
      |> Item.changeset(%{status: "merged", merged_at: now})
      |> Repo.update()
      |> tap_event(project.id, "merge_queue.merged")
      |> tap_broadcast(project.id)
    end
  end

  @spec mergeable?(Project.t(), Item.t()) :: :ok | {:error, term()}
  def mergeable?(%Project{} = project, %Item{} = item) do
    repo = project.canonical_path

    cond do
      item.status != "accepted" ->
        {:error, :not_accepted}

      item.policy_status != "passed" ->
        {:error, :policy_failed}

      Git.dirty?(repo) ->
        {:error, :dirty_worktree}

      not on_target_branch?(repo, item.target_ref) ->
        {:error, :wrong_branch}

      Git.merge_conflict?(repo, "HEAD", item.commit_sha) ->
        {:error, :conflict}

      true ->
        :ok
    end
  end

  defp transition(scope, %Item{status: status} = item, status, _fun) do
    tap_broadcast({:ok, item}, scope.project.id)
  end

  defp transition(_scope, %Item{status: "merged"}, _to, _fun), do: {:error, :already_merged}
  defp transition(_scope, %Item{status: "rejected"}, _to, _fun), do: {:error, :closed}

  defp transition(scope, item, to, fun) do
    case item |> fun.() |> Repo.update() do
      {:ok, updated} ->
        _ = tap_event({:ok, updated}, scope.project.id, "merge_queue." <> to)
        tap_broadcast({:ok, updated}, scope.project.id)

      error ->
        error
    end
  end

  defp fetch_item(project_id, artifact_id) do
    case Repo.get_by(Item, project_id: project_id, artifact_id: artifact_id) do
      %Item{} = item -> {:ok, item}
      nil -> {:error, :not_found}
    end
  end

  defp get_item(project_id, id) do
    case Repo.get_by(Item, id: id, project_id: project_id) do
      %Item{} = item -> {:ok, item}
      nil -> {:error, :not_found}
    end
  end

  defp session_worktree(%Scope{agent_session: %{id: id}}), do: Worktrees.get_for_session(id)
  defp session_worktree(_scope), do: nil

  defp commit_sha(artifact, attrs) do
    Map.get(attrs, :commit) || Map.get(attrs, "commit") || artifact.metadata["commit"] || ""
  end

  defp branch_name(%Worktree{branch_name: name}, _artifact), do: name

  defp branch_name(_worktree, artifact) do
    artifact.metadata["branch"] || "HEAD"
  end

  defp summary(attrs) do
    Map.get(attrs, :summary) || Map.get(attrs, "summary") || "AgentDesk handoff"
  end

  defp stringify(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end

  defp merge_message(item), do: "Merge #{item.branch_name}: #{item.summary}"

  defp on_target_branch?(repo, target) do
    case Git.default_branch(repo) do
      {:ok, name} -> name == target
      _ -> false
    end
  end

  defp tap_event({:ok, item} = result, project_id, type) do
    payload = %{
      "item_id" => item.id,
      "artifact_id" => item.artifact_id,
      "status" => item.status
    }

    {:ok, _} =
      Events.append(%{
        project_id: project_id,
        type: type,
        source: "reviews",
        payload: payload
      })

    result
  end

  defp tap_event(result, _project_id, _type), do: result

  defp tap_broadcast({:ok, _item} = result, project_id) do
    Phoenix.PubSub.broadcast(
      AgentDesk.PubSub,
      "project:" <> project_id <> ":reviews",
      {:merge_queue_changed, project_id}
    )

    result
  end

  defp tap_broadcast(result, _project_id), do: result
end
