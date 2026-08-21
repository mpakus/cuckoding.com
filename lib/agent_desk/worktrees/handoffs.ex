defmodule AgentDesk.Worktrees.Handoffs do
  @moduledoc """
  Commit, summary, changed-file, and warning bundles published as artifacts.
  """

  alias AgentDesk.A2A
  alias AgentDesk.Git
  alias AgentDesk.Ids
  alias AgentDesk.Scope
  alias AgentDesk.Storage
  alias AgentDesk.Worktrees
  alias AgentDesk.Worktrees.Worktree

  @spec publish(Scope.t(), map()) :: {:ok, map()} | {:error, term()}
  def publish(%Scope{} = scope, attrs) do
    session = scope.agent_session

    with %Worktree{} = worktree <- Worktrees.get_for_session(session.id),
         {:ok, commit} <- resolve_commit(worktree, attrs),
         true <- Git.contains_commit?(worktree.path, commit),
         {:ok, files} <- Git.changed_files(worktree.path, worktree.base_commit),
         {:ok, artifact} <- persist_artifact(scope, worktree, commit, files, attrs) do
      _ = maybe_review(scope, attrs)
      {:ok, %{artifact: artifact, commit: commit, changed_files: files}}
    else
      nil -> {:error, :no_worktree}
      false -> {:error, :commit_not_in_worktree}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec accept(Scope.t(), Ecto.UUID.t()) :: {:ok, term()} | {:error, term()}
  def accept(%Scope{} = scope, artifact_id) do
    with {:ok, artifact} <- A2A.get_artifact(scope, artifact_id) do
      metadata = Map.put(artifact.metadata || %{}, "accepted_by", scope.agent_session.id)
      {:ok, %{artifact_id: artifact.id, metadata: metadata, merged: false}}
    end
  end

  defp resolve_commit(worktree, attrs) do
    explicit = Map.get(attrs, :commit) || Map.get(attrs, "commit")

    if is_binary(explicit) and explicit != "" do
      {:ok, explicit}
    else
      commit_or_head(worktree, summary(attrs))
    end
  end

  defp commit_or_head(worktree, message) do
    case Worktrees.commit(worktree, message) do
      {:ok, updated} ->
        {:ok, updated.head_commit}

      {:error, {_code, out}} ->
        if String.contains?(to_string(out), "nothing to commit") do
          Git.rev_parse(worktree.path, "HEAD")
        else
          {:error, out}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp persist_artifact(scope, worktree, commit, files, attrs) do
    summary = summary(attrs)
    warnings = Map.get(attrs, :warnings) || Map.get(attrs, "warnings") || []
    checks = Map.get(attrs, :checks) || Map.get(attrs, "checks") || []

    body =
      Jason.encode!(%{
        summary: summary,
        commit: commit,
        changed_files: files,
        warnings: warnings,
        checks: checks
      })

    dir = Storage.session_dir(scope.project.id, scope.agent_session.id)
    File.mkdir_p!(dir)
    path = Path.join(dir, "handoff-#{Ids.generate()}.json")
    File.write!(path, body)
    sha = :sha256 |> :crypto.hash(body) |> Base.encode16(case: :lower)
    context_id = Map.get(attrs, :context_id) || Map.get(attrs, "context_id")

    with {:ok, context_id} <- resolve_context(scope, context_id) do
      A2A.publish_artifact(scope, %{
        context_id: context_id,
        task_id: Map.get(attrs, :task_id) || Map.get(attrs, "task_id"),
        kind: "handoff",
        name: "handoff.json",
        mime_type: "application/json",
        path: path,
        sha256: sha,
        size_bytes: byte_size(body),
        metadata: %{
          "commit" => commit,
          "branch" => worktree.branch_name,
          "changed_files" => Enum.take(files, 2_000)
        }
      })
    end
  end

  defp resolve_context(_scope, id) when is_binary(id), do: {:ok, id}
  defp resolve_context(scope, _), do: ensure_context(scope)

  defp ensure_context(scope) do
    case A2A.create_context(scope, %{title: "Handoff"}) do
      {:ok, context} -> {:ok, context.id}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_review(scope, attrs) do
    recipients =
      Map.get(attrs, :review_requested_from) || Map.get(attrs, "review_requested_from") || []

    Enum.each(recipients, &request_review(scope, &1, attrs))
  end

  defp request_review(scope, agent_id, attrs) do
    task_id = Map.get(attrs, :task_id) || Map.get(attrs, "task_id")

    if is_binary(task_id) do
      A2A.propose_delegation(scope, %{
        task_id: task_id,
        to_agent_id: agent_id,
        reason: "Please review this handoff",
        idempotency_key: Ids.generate()
      })
    end
  end

  defp summary(attrs) do
    Map.get(attrs, :summary) || Map.get(attrs, "summary") || "AgentDesk handoff"
  end
end
