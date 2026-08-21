defmodule AgentDesk.Diagnostics do
  @moduledoc """
  Redacted diagnostic export for local support. Never includes capability tokens.
  """

  alias AgentDesk.A2A
  alias AgentDesk.Agents
  alias AgentDesk.Events
  alias AgentDesk.Projects.Project
  alias AgentDesk.Providers.Redactor
  alias AgentDesk.Resources.Manager
  alias AgentDesk.Scope
  alias AgentDesk.Storage
  alias AgentDesk.Worktrees

  @spec export(Project.t()) :: {:ok, String.t()} | {:error, term()}
  def export(%Project{} = project) do
    scope = Scope.for_project(project)
    dir = Storage.diagnostics_dir(project.id)
    File.mkdir_p!(dir)
    path = Path.join(dir, "export.json")

    payload = %{
      "project" => %{
        "id" => project.id,
        "name" => project.name,
        "canonical_path" => project.canonical_path
      },
      "sessions" => Enum.map(Agents.list_sessions(project.id), &session_map/1),
      "events" => Enum.map(Events.list_for_project(project.id, limit: 200), &event_map/1),
      "leases" => Enum.map(Manager.list_project(project.id), &lease_map/1),
      "artifacts" => Enum.map(A2A.list_artifacts(scope), &artifact_map/1),
      "worktrees" => Enum.map(Worktrees.list_project(project.id), &worktree_map/1)
    }

    File.write!(path, Jason.encode!(Redactor.redact(payload)))
    {:ok, path}
  rescue
    error -> {:error, error}
  end

  defp session_map(session) do
    %{
      "id" => session.id,
      "provider" => session.provider,
      "status" => session.status,
      "display_name" => session.display_name,
      "process_identity" => session.process_identity
    }
  end

  defp event_map(event) do
    %{"id" => event.id, "type" => event.type, "payload" => event.payload}
  end

  defp lease_map(lease) do
    %{"id" => lease.id, "key" => lease.resource_key, "status" => lease.status}
  end

  defp artifact_map(artifact) do
    %{"id" => artifact.id, "name" => artifact.name, "kind" => artifact.kind}
  end

  defp worktree_map(worktree) do
    %{"id" => worktree.id, "path" => worktree.path, "status" => worktree.status}
  end
end
