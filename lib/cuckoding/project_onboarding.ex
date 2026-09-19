defmodule Cuckoding.ProjectOnboarding do
  @moduledoc "Registers a project and trusted defaults without creating executable work."

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

  def default_roles, do: @default_roles

  def validate_repository(attrs) when is_map(attrs) do
    GitService.validate_registration(attrs["repo_path"], attrs["default_branch"])
  end

  def create(attrs) when is_map(attrs) do
    with {:ok, name} <- required_text(attrs["name"]),
         {:ok, {repo_path, base_sha}} <- validate_repository(attrs),
         {:ok, runtime} <- RuntimeConfiguration.validate(attrs) do
      persist(attrs, name, repo_path, base_sha, runtime)
    end
  end

  defp persist(attrs, name, repo_path, base_sha, runtime) do
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
           config = configuration(runtime, base_sha),
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

  defp configuration(runtime, base_sha) do
    %{
      "version" => 1,
      "runner" => "local_process",
      "plugins" => [],
      "base_sha_at_registration" => base_sha,
      "agent_connections" => [
        %{
          "key" => "primary",
          "adapter_key" => runtime.runtime,
          "settings" => runtime.settings
        }
      ],
      "default_roles" => Enum.map(@default_roles, &Map.put(&1, "agent_connection_key", "primary"))
    }
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
