defmodule Cuckoding.ProjectOnboarding do
  @moduledoc "Registers projects and versions their agent and role defaults."

  alias Cuckoding.Adapters.RuntimeConfiguration
  alias Cuckoding.Clock
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Projects
  alias Cuckoding.Repo

  @default_roles [
    %{
      "key" => "spec_writer",
      "name" => "Specifications",
      "instructions" => "Clarify intent and produce testable acceptance criteria."
    },
    %{
      "key" => "implementer",
      "name" => "Coding",
      "instructions" => "Implement the approved specification and provide test evidence."
    },
    %{
      "key" => "reviewer",
      "name" => "Review",
      "instructions" => "Review independently and route findings to specifications or coding."
    }
  ]
  @default_role_keys MapSet.new(Enum.map(@default_roles, & &1["key"]))
  @key_pattern ~r/\A[a-z][a-z0-9_-]{0,63}\z/
  @max_connections 32
  @max_roles 64

  def default_roles, do: @default_roles

  def validate_repository(attrs) when is_map(attrs) do
    with {:ok, registration} <-
           GitService.inspect_registration(attrs["repo_path"], attrs["default_branch"]) do
      {:ok, {registration.repo, registration}}
    end
  end

  def suggested_branch(path, fallback),
    do: GitService.suggested_registration_branch(path, fallback)

  def create(attrs) when is_map(attrs) do
    with {:ok, name} <- required_text(attrs["name"]),
         {:ok, {repo_path, base_sha}} <-
           GitService.ensure_registration(attrs["repo_path"], attrs["default_branch"]) do
      persist(attrs, name, repo_path, base_sha)
    end
  end

  def update_configuration(project_id, expected_revision, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      with project when not is_nil(project) <- Projects.get_project(project_id),
           current when not is_nil(current) <- Projects.latest_config_version(project_id),
           :ok <- current_revision(current.revision, expected_revision),
           {:ok, connections} <- validate_connections(attrs["agent_connections"]),
           {:ok, roles} <- validate_roles(attrs["default_roles"], connections),
           config <-
             current.config_json
             |> Map.put("agent_connections", connections)
             |> Map.put("default_roles", roles),
           {:ok, version} <- put_config_version(project.id, current, config) do
        version
      else
        nil -> Repo.rollback(:project_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  def save_connection(project_id, expected_revision, attrs) when is_map(attrs) do
    Repo.transaction(fn ->
      with project when not is_nil(project) <- Projects.get_project(project_id),
           current when not is_nil(current) <- Projects.latest_config_version(project_id),
           :ok <- current_revision(current.revision, expected_revision),
           {:ok, connection} <- validate_connection(attrs),
           {:ok, connections} <-
             upsert_connection(current.config_json["agent_connections"] || [], connection),
           config <- Map.put(current.config_json, "agent_connections", connections),
           {:ok, version} <- put_config_version(project.id, current, config) do
        version
      else
        nil -> Repo.rollback(:project_not_found)
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp persist(attrs, name, repo_path, base_sha) do
    Repo.transaction(fn ->
      with {:ok, project} <-
             Projects.register(%{
               name: name,
               description: optional_text(attrs["description"]),
               repo_path: repo_path,
               default_branch: attrs["default_branch"],
               workspace_root: workspace_root(),
               port_range_start: 43_000,
               port_range_end: 43_999
             }),
           config = configuration(base_sha),
           {:ok, version} <-
             Projects.add_config_version(%{
               project_id: project.id,
               revision: 1,
               source_hash: hash(config),
               config_json: config,
               trusted_at: Clock.wall_now()
             }) do
        %{project: project, config: version}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp configuration(base_sha) do
    %{
      "version" => 1,
      "runner" => "local_process",
      "plugins" => [],
      "base_sha_at_registration" => base_sha,
      "agent_connections" => [],
      "default_roles" => Enum.map(@default_roles, &Map.put(&1, "agent_connection_key", nil))
    }
  end

  defp put_config_version(project_id, current, config) do
    hash = hash(config)

    if hash == current.source_hash do
      {:ok, current}
    else
      Projects.add_config_version(%{
        project_id: project_id,
        revision: current.revision + 1,
        source_hash: hash,
        config_json: config,
        trusted_at: Clock.wall_now()
      })
    end
  end

  defp current_revision(revision, revision), do: :ok
  defp current_revision(_current, _expected), do: {:error, :stale_configuration}

  defp validate_connections(connections)
       when is_list(connections) and length(connections) <= @max_connections do
    with {:ok, normalized} <- map_valid(connections, &validate_connection/1),
         :ok <- unique_keys(normalized, :duplicate_agent_key) do
      {:ok, normalized}
    end
  end

  defp validate_connections(_connections), do: {:error, :invalid_agent_connections}

  defp validate_connection(connection) when is_map(connection) do
    with {:ok, key} <- valid_key(connection["key"], :invalid_agent_key),
         {:ok, label} <- bounded_text(connection["label"], :agent_label_required, 120),
         {:ok, runtime} <-
           RuntimeConfiguration.validate(%{
             "runtime" => connection["adapter_key"],
             "executable_path" => connection["executable_path"],
             "api_key_helper" => connection["api_key_helper"]
           }) do
      {:ok,
       %{
         "key" => key,
         "label" => label,
         "adapter_key" => runtime.runtime,
         "settings" => runtime.settings
       }}
    end
  end

  defp validate_connection(_connection), do: {:error, :invalid_agent_connection}

  defp upsert_connection(connections, connection) when length(connections) < @max_connections do
    case Enum.find_index(connections, &(&1["key"] == connection["key"])) do
      nil -> {:ok, connections ++ [connection]}
      index -> {:ok, List.replace_at(connections, index, connection)}
    end
  end

  defp upsert_connection(connections, connection) when length(connections) == @max_connections do
    case Enum.find_index(connections, &(&1["key"] == connection["key"])) do
      nil -> {:error, :too_many_agent_connections}
      index -> {:ok, List.replace_at(connections, index, connection)}
    end
  end

  defp upsert_connection(_connections, _connection), do: {:error, :invalid_agent_connections}

  defp validate_roles(roles, connections)
       when is_list(roles) and roles != [] and length(roles) <= @max_roles do
    connection_keys = MapSet.new(connections, & &1["key"])

    with {:ok, normalized} <- map_valid(roles, &validate_role(&1, connection_keys)),
         :ok <- unique_keys(normalized, :duplicate_role_key),
         :ok <- default_roles_present(normalized) do
      {:ok, normalized}
    end
  end

  defp validate_roles(_roles, _connections), do: {:error, :invalid_roles}

  defp validate_role(role, connection_keys) when is_map(role) do
    with {:ok, key} <- valid_key(role["key"], :invalid_role_key),
         {:ok, name} <- bounded_text(role["name"], :role_name_required, 120),
         {:ok, instructions} <-
           bounded_text(role["instructions"], :role_instructions_required, 4_000),
         {:ok, connection_key} <-
           assigned_connection(role["agent_connection_key"], connection_keys) do
      {:ok,
       %{
         "key" => key,
         "name" => name,
         "instructions" => instructions,
         "agent_connection_key" => connection_key
       }}
    end
  end

  defp validate_role(_role, _connection_keys), do: {:error, :invalid_role}

  defp assigned_connection(key, connection_keys) when is_binary(key) do
    if MapSet.member?(connection_keys, key),
      do: {:ok, key},
      else: {:error, :role_agent_required}
  end

  defp assigned_connection(_key, _connection_keys), do: {:error, :role_agent_required}

  defp valid_key(value, error) when is_binary(value) do
    value = String.trim(value)
    if Regex.match?(@key_pattern, value), do: {:ok, value}, else: {:error, error}
  end

  defp valid_key(_value, error), do: {:error, error}

  defp bounded_text(value, error, max_length) when is_binary(value) do
    value = String.trim(value)

    if value != "" and String.length(value) <= max_length,
      do: {:ok, value},
      else: {:error, error}
  end

  defp bounded_text(_value, error, _max_length), do: {:error, error}

  defp map_valid(items, validator) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, normalized} ->
      case validator.(item) do
        {:ok, value} -> {:cont, {:ok, [value | normalized]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp unique_keys(items, error) do
    keys = Enum.map(items, & &1["key"])
    if length(keys) == MapSet.size(MapSet.new(keys)), do: :ok, else: {:error, error}
  end

  defp default_roles_present(roles) do
    keys = MapSet.new(roles, & &1["key"])
    if MapSet.subset?(@default_role_keys, keys), do: :ok, else: {:error, :default_role_missing}
  end

  defp required_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> {:error, :project_name_required}
      text -> {:ok, text}
    end
  end

  defp required_text(_value), do: {:error, :project_name_required}

  defp optional_text(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      text -> text
    end
  end

  defp optional_text(_value), do: nil

  defp hash(config),
    do: :crypto.hash(:sha256, Jason.encode!(config)) |> Base.encode16(case: :lower)

  defp workspace_root do
    Application.get_env(:cuckoding, :workspace_root) ||
      Application.fetch_env!(:cuckoding, Cuckoding.Repo)
      |> Keyword.fetch!(:database)
      |> Path.dirname()
      |> Path.join("workspaces")
  end
end
