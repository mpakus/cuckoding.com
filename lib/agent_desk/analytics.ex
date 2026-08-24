defmodule AgentDesk.Analytics do
  @moduledoc """
  Rebuildable view of what agents persist in SQLite, XERJ/search, and A2A.

  Canonical counts come from SQLite. XERJ is a projection: missing or unhealthy
  search never hides coordination rows.
  """

  import Ecto.Query

  alias AgentDesk.A2A.Artifact
  alias AgentDesk.A2A.Delivery
  alias AgentDesk.A2A.Message
  alias AgentDesk.A2A.Task
  alias AgentDesk.Agents.Session
  alias AgentDesk.Events.Event
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Resources.Lease
  alias AgentDesk.Search.Document
  alias AgentDesk.Search.Memory
  alias AgentDesk.Storage
  alias AgentDesk.Usage
  alias AgentDesk.Usage.Sample

  @spec format_bytes(non_neg_integer()) :: String.t()
  def format_bytes(bytes) when is_integer(bytes) and bytes < 1024, do: "#{bytes} B"

  def format_bytes(bytes) when is_integer(bytes) and bytes < 1_048_576 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  def format_bytes(bytes) when is_integer(bytes) do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  def format_bytes(_), do: "0 B"

  @spec report(Project.t()) :: map()
  def report(%Project{} = project) do
    %{
      sqlite: sqlite(project),
      memory: memory(project),
      runtime: runtime(),
      xerj: xerj(project),
      exchange: exchange(project)
    }
  end

  defp runtime do
    mem = :erlang.memory()

    %{
      total: mem[:total] || 0,
      processes: mem[:processes] || 0,
      ets: mem[:ets] || 0,
      atom: mem[:atom] || 0,
      binary: mem[:binary] || 0,
      process_count: :erlang.system_info(:process_count)
    }
  end

  defp sqlite(%Project{} = project) do
    path = repo_path()
    bytes = file_bytes(path) + file_bytes(path <> "-wal") + file_bytes(path <> "-shm")

    %{
      path: path,
      bytes: bytes,
      tables: [
        table("sessions", count(Session, project.id)),
        table("messages", count(Message, project.id)),
        table("deliveries", delivery_count(project.id)),
        table("artifacts", count(Artifact, project.id)),
        table("events", count(Event, project.id)),
        table("memories", count(Memory, project.id)),
        table("search_docs", count(Document, project.id)),
        table("leases", count(Lease, project.id)),
        table("tasks", count(Task, project.id)),
        table("usage_samples", count(Sample, project.id))
      ]
    }
  end

  defp memory(%Project{id: project_id}) do
    rows =
      Memory
      |> where([m], m.project_id == ^project_id)
      |> group_by([m], m.namespace)
      |> select([m], {m.namespace, count(m.id), sum(fragment("length(?)", m.text))})
      |> Repo.all()

    namespaces =
      Enum.map(rows, fn {namespace, count, bytes} ->
        %{
          "namespace" => namespace,
          "kind" => namespace_kind(namespace, project_id),
          "count" => count,
          "bytes" => as_int(bytes)
        }
      end)

    %{
      namespaces: namespaces,
      total: Enum.reduce(namespaces, 0, &(&1["count"] + &2)),
      bytes: Enum.reduce(namespaces, 0, &(&1["bytes"] + &2))
    }
  end

  defp xerj(%Project{} = project) do
    status = AgentDesk.Search.status(project)
    dir = Storage.xerj_dir()

    %{
      adapter: status.adapter,
      health: health_label(status.health),
      status: status.status,
      last_indexed_at: status.last_indexed_at,
      error: status.error,
      data_dir: dir,
      data_present: File.dir?(dir)
    }
  end

  defp exchange(%Project{} = project) do
    messages = grouped(Message, project.id, :kind)
    scopes = grouped(Message, project.id, :scope)
    artifacts = grouped(Artifact, project.id, :kind)
    events = grouped(Event, project.id, :type)

    %{
      messages: messages,
      scopes: scopes,
      artifacts: artifacts,
      events: Enum.take(events, 8),
      usage: Usage.summary(project),
      sessions: count(Session, project.id),
      pending_deliveries: pending_deliveries(project.id)
    }
  end

  defp grouped(schema, project_id, field) do
    schema
    |> where([q], q.project_id == ^project_id)
    |> group_by([q], field(q, ^field))
    |> select([q], {field(q, ^field), count(q.id)})
    |> Repo.all()
    |> Enum.map(fn {name, count} -> %{"name" => name || "unknown", "count" => count} end)
    |> Enum.sort_by(& &1["count"], :desc)
  end

  defp count(schema, project_id) do
    schema
    |> where([q], q.project_id == ^project_id)
    |> Repo.aggregate(:count)
  end

  defp delivery_count(project_id) do
    Delivery
    |> join(:inner, [d], m in Message, on: d.message_id == m.id)
    |> where([_d, m], m.project_id == ^project_id)
    |> Repo.aggregate(:count)
  end

  defp pending_deliveries(project_id) do
    Delivery
    |> join(:inner, [d], m in Message, on: d.message_id == m.id)
    |> where([d, m], m.project_id == ^project_id and d.state == "pending")
    |> Repo.aggregate(:count)
  end

  defp table(name, rows), do: %{"name" => name, "rows" => rows}

  defp namespace_kind(namespace, project_id) when is_binary(namespace) do
    prefix = "project-" <> project_id <> "-"
    rest = String.replace_prefix(namespace, prefix, "")

    cond do
      rest == namespace -> "other"
      rest == "shared" -> "shared"
      String.starts_with?(rest, "agent-") -> "agent"
      String.starts_with?(rest, "task-") -> "task"
      String.starts_with?(rest, "context-") -> "context"
      true -> "other"
    end
  end

  defp namespace_kind(_, _), do: "other"

  defp health_label(:ok), do: "ok"
  defp health_label({:error, reason}), do: inspect(reason)

  defp repo_path do
    :agent_desk
    |> Application.fetch_env!(AgentDesk.Repo)
    |> Keyword.get(:database)
  end

  defp file_bytes(path) when is_binary(path) do
    case File.stat(path) do
      {:ok, %{size: size}} -> size
      _ -> 0
    end
  end

  defp as_int(nil), do: 0
  defp as_int(value) when is_integer(value), do: value
  defp as_int(%Decimal{} = value), do: Decimal.to_integer(value)
  defp as_int(_), do: 0
end
