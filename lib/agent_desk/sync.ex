defmodule AgentDesk.Sync do
  @moduledoc """
  User-initiated coordination bundles between machines.

  Git remains the code transport. This copies tasks, workflows, and roles after
  redaction. It is not a network listener and not a public A2A gateway.
  """

  import Ecto.Query

  alias AgentDesk.A2A
  alias AgentDesk.A2A.Graph
  alias AgentDesk.A2A.Task
  alias AgentDesk.A2A.Workflows
  alias AgentDesk.Clock
  alias AgentDesk.Events
  alias AgentDesk.Git
  alias AgentDesk.Ids
  alias AgentDesk.Projects
  alias AgentDesk.Projects.Project
  alias AgentDesk.Providers.Redactor
  alias AgentDesk.Repo
  alias AgentDesk.Roles
  alias AgentDesk.Scope
  alias AgentDesk.Storage

  @format "agentdesk.sync.v1"
  @max_bytes 2_000_000
  @max_tasks 500
  @statuses ~w(queued assigned working input_required auth_required blocked review completed failed cancelled rejected)

  @spec export(Project.t()) :: {:ok, String.t()} | {:error, term()}
  def export(%Project{} = project) do
    with {:ok, project, sync_id} <- ensure_sync_id(project),
         {:ok, path} <- write_bundle(project, sync_id) do
      _ = record(project.id, "sync.exported", %{"path" => path, "sync_id" => sync_id})
      {:ok, path}
    end
  end

  @spec import_bundle(Project.t(), Path.t()) :: {:ok, map()} | {:error, term()}
  def import_bundle(%Project{} = project, path) when is_binary(path) do
    with {:ok, json} <- read_bundle(path),
         {:ok, bundle} <- decode(json),
         :ok <- compatible?(project, bundle),
         {:ok, project} <- adopt_sync_id(project, bundle["sync_id"]),
         {:ok, counts} <- apply_bundle(project, bundle) do
      _ = record(project.id, "sync.imported", counts)
      {:ok, counts}
    end
  end

  defp ensure_sync_id(%Project{settings: settings} = project) do
    case settings["sync_id"] do
      id when is_binary(id) and id != "" -> {:ok, project, id}
      _ -> assign_sync_id(project)
    end
  end

  defp assign_sync_id(project) do
    id = Ids.generate()

    case Projects.put_settings(project, %{"sync_id" => id}) do
      {:ok, updated} -> {:ok, updated, id}
      error -> error
    end
  end

  defp adopt_sync_id(%Project{settings: %{"sync_id" => id}} = project, id), do: {:ok, project}

  defp adopt_sync_id(project, sync_id) when is_binary(sync_id) and sync_id != "" do
    Projects.put_settings(project, %{"sync_id" => sync_id})
  end

  defp adopt_sync_id(_project, _sync_id), do: {:error, :invalid_bundle}

  defp write_bundle(project, sync_id) do
    dir = Storage.sync_dir(project.id)
    File.mkdir_p!(dir)
    path = Path.join(dir, "bundle.json")
    payload = Redactor.redact(bundle_map(project, sync_id))
    File.write!(path, Jason.encode!(payload))
    {:ok, path}
  rescue
    error -> {:error, error}
  end

  defp bundle_map(project, sync_id) do
    scope = Scope.for_project(project)
    tasks = project_tasks(scope)

    %{
      "format" => @format,
      "exported_at" => DateTime.to_iso8601(Clock.utc_now()),
      "sync_id" => sync_id,
      "origin" => origin_url(project),
      "project_name" => project.name,
      "tasks" => Enum.map(tasks, &task_map/1),
      "dependencies" => Enum.map(Graph.list_edges(project.id), &edge_map/1),
      "workflows" => Enum.map(Workflows.list(scope), &workflow_map/1),
      "roles" => Enum.map(Roles.list(project), &role_map/1)
    }
  end

  defp project_tasks(scope) do
    scope
    |> A2A.list_tasks()
    |> Enum.take(@max_tasks)
  end

  defp task_map(task) do
    %{
      "id" => task.id,
      "title" => task.title,
      "description" => task.description,
      "status" => task.status,
      "priority" => task.priority,
      "parent_task_id" => task.parent_task_id,
      "metadata" => public_metadata(task.metadata),
      "updated_at" => DateTime.to_iso8601(task.updated_at)
    }
  end

  defp edge_map(edge) do
    %{"task_id" => edge.task_id, "depends_on_id" => edge.depends_on_id}
  end

  defp workflow_map(workflow) do
    %{
      "name" => workflow.name,
      "description" => workflow.description,
      "definition" => workflow.definition
    }
  end

  defp role_map(role) do
    %{
      "name" => role.name,
      "description" => role.description,
      "prompt" => role.prompt,
      "permission_profile" => role.permission_profile,
      "skills" => role.skills
    }
  end

  defp read_bundle(path) do
    expanded = Path.expand(path)

    case File.stat(expanded) do
      {:ok, %{size: size}} when size <= @max_bytes -> File.read(expanded)
      {:ok, _} -> {:error, :too_large}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, %{"format" => @format} = bundle} -> validate_bundle(bundle)
      {:ok, _} -> {:error, :unsupported_format}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_bundle(%{"sync_id" => id} = bundle) when is_binary(id) and id != "" do
    {:ok, bundle}
  end

  defp validate_bundle(_bundle), do: {:error, :invalid_bundle}

  defp compatible?(project, bundle) do
    sync_match?(project.settings["sync_id"], bundle["sync_id"])
    |> Kernel.||(origin_match?(origin_url(project), bundle["origin"]))
    |> accept_match()
  end

  defp sync_match?(left, right) when is_binary(left) and left != "" and left == right, do: true
  defp sync_match?(_left, _right), do: false

  defp origin_match?(left, right) do
    key = origin_key(right)
    present?(key) and origin_key(left) == key
  end

  defp accept_match(true), do: :ok
  defp accept_match(false), do: {:error, :sync_mismatch}

  defp apply_bundle(project, bundle) do
    scope = Scope.for_project(project)

    Repo.transaction(fn ->
      case A2A.ensure_working_context(scope) do
        {:ok, context} -> apply_parts(scope, context, bundle)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp apply_parts(scope, context, bundle) do
    tasks = List.wrap(bundle["tasks"])
    existing = imported_index(scope.project.id)
    id_map = Enum.reduce(tasks, %{}, &upsert_task(scope, context, existing, &1, &2))
    _ = Enum.each(tasks, &relink_parent(id_map, &1))
    _ = Enum.each(List.wrap(bundle["dependencies"]), &import_edge(scope, id_map, &1))
    _ = Enum.each(List.wrap(bundle["workflows"]), &Workflows.upsert(scope, &1))
    _ = Enum.each(List.wrap(bundle["roles"]), &Roles.upsert(scope.project, &1))

    %{
      "tasks" => map_size(id_map),
      "workflows" => length(List.wrap(bundle["workflows"])),
      "roles" => length(List.wrap(bundle["roles"]))
    }
  end

  defp imported_index(project_id) do
    Task
    |> where([t], t.project_id == ^project_id)
    |> Repo.all()
    |> Map.new(&{sync_origin_id(&1), &1})
  end

  defp sync_origin_id(%Task{id: id, metadata: metadata}) do
    metadata["sync_origin_id"] || id
  end

  defp upsert_task(scope, context, existing, row, id_map) do
    case cast_uuid(row["id"]) do
      {:ok, origin_id} -> put_task(scope, context, existing, row, origin_id, id_map)
      :error -> id_map
    end
  end

  defp put_task(scope, context, existing, row, origin_id, id_map) do
    case Map.get(existing, origin_id) do
      %Task{} = task ->
        maybe_update(task, row)
        Map.put(id_map, origin_id, task.id)

      nil ->
        local_id = Ids.generate()
        insert_imported(scope, context, row, local_id, origin_id, id_map)
    end
  end

  defp insert_imported(scope, context, row, local_id, origin_id, id_map) do
    attrs = imported_attrs(scope, context, row, local_id, origin_id)

    case %Task{} |> Task.changeset(attrs) |> Repo.insert() do
      {:ok, _task} -> Map.put(id_map, origin_id, local_id)
      {:error, _changeset} -> id_map
    end
  end

  defp maybe_update(task, row) do
    if newer?(row["updated_at"], task.updated_at) do
      task
      |> Task.changeset(update_attrs(row))
      |> Repo.update()
    else
      {:ok, task}
    end
  end

  defp imported_attrs(scope, context, row, local_id, origin_id) do
    metadata =
      row["metadata"]
      |> public_metadata()
      |> Map.put("sync_origin_id", origin_id)

    %{
      id: local_id,
      project_id: scope.project.id,
      context_id: context.id,
      title: clamp(row["title"] || "Imported task", 200),
      description: clamp(row["description"] || "", 10_000),
      status: import_status(row["status"]),
      created_by: "user",
      lock_version: 1,
      priority: import_priority(row["priority"]),
      metadata: metadata
    }
  end

  defp update_attrs(row) do
    origin = row["id"]

    metadata =
      row["metadata"]
      |> public_metadata()
      |> Map.put("sync_origin_id", origin)

    %{
      title: clamp(row["title"] || "Imported task", 200),
      description: clamp(row["description"] || "", 10_000),
      status: import_status(row["status"]),
      priority: import_priority(row["priority"]),
      metadata: metadata
    }
  end

  defp relink_parent(id_map, row) do
    with {:ok, origin} <- cast_uuid(row["id"]),
         {:ok, parent_origin} <- cast_uuid(row["parent_task_id"]),
         {:ok, local} <- Map.fetch(id_map, origin),
         {:ok, parent} <- Map.fetch(id_map, parent_origin),
         %Task{} = task <- Repo.get(Task, local) do
      task
      |> Task.changeset(%{parent_task_id: parent})
      |> Repo.update()
    else
      _ -> :ok
    end
  end

  defp import_edge(scope, id_map, edge) do
    link_edge(scope, remap(id_map, edge["task_id"]), remap(id_map, edge["depends_on_id"]))
  end

  defp link_edge(scope, task_id, prereq_id) when is_binary(task_id) and is_binary(prereq_id) do
    Graph.ensure_dependency(scope, task_id, prereq_id)
  end

  defp link_edge(_scope, _task_id, _prereq_id), do: :ok

  defp remap(id_map, id) do
    case cast_uuid(id) do
      {:ok, uuid} -> Map.get(id_map, uuid)
      :error -> nil
    end
  end

  defp import_status(status) when status in @statuses, do: status
  defp import_status(_status), do: "queued"

  defp import_priority(priority) when is_integer(priority), do: priority
  defp import_priority(_priority), do: 0

  defp public_metadata(map) when is_map(map) do
    map
    |> Map.drop(["capability_token", "token", "secret", "password", :capability_token, :token])
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp public_metadata(_other), do: %{}

  defp newer?(bundle_iso, %DateTime{} = local) do
    case parse_dt(bundle_iso) do
      nil -> true
      bundle_dt -> DateTime.compare(bundle_dt, local) != :lt
    end
  end

  defp parse_dt(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> DateTime.truncate(datetime, :microsecond)
      _ -> nil
    end
  end

  defp parse_dt(_value), do: nil

  defp origin_url(%Project{canonical_path: path}) do
    case Git.remote_origin(path) do
      {:ok, url} -> url
      {:error, _} -> nil
    end
  end

  defp origin_key(nil), do: nil
  defp origin_key(""), do: nil

  defp origin_key(url) when is_binary(url) do
    normalized =
      url
      |> String.trim()
      |> String.downcase()
      |> String.replace_suffix(".git", "")
      |> ssh_to_https()

    host_path(URI.parse(normalized), normalized)
  end

  defp ssh_to_https("git@" <> rest) do
    String.replace("git@" <> rest, ~r/^git@([^:]+):/, "https://\\1/")
  end

  defp ssh_to_https("ssh://git@" <> rest), do: "https://" <> rest
  defp ssh_to_https(url), do: url

  defp host_path(%URI{host: host, path: path}, _fallback) when is_binary(host) do
    "https://" <> host <> (path || "")
  end

  defp host_path(_uri, fallback), do: fallback

  defp present?(value) when is_binary(value) and value != "", do: true
  defp present?(_value), do: false

  defp clamp(text, max) when is_binary(text), do: String.slice(text, 0, max)
  defp clamp(_text, _max), do: ""

  defp cast_uuid(id) when is_binary(id), do: Ecto.UUID.cast(id)
  defp cast_uuid(_id), do: :error

  defp record(project_id, type, payload) do
    Events.append(%{
      project_id: project_id,
      type: type,
      source: "sync",
      payload: payload
    })
  end
end
