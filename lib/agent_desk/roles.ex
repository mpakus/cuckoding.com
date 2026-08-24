defmodule AgentDesk.Roles do
  @moduledoc """
  Project-scoped agent roles and prompt templates.

  Prompt bodies stay in SQLite and the provider session. They never appear on
  Agent Cards, MCP list payloads, or diagnostic events.
  """

  import Ecto.Query

  alias AgentDesk.Agents.Session
  alias AgentDesk.Ids
  alias AgentDesk.Projects.Project
  alias AgentDesk.Repo
  alias AgentDesk.Roles.Role

  @spec list(Project.t() | Ecto.UUID.t()) :: [Role.t()]
  def list(%Project{id: id}), do: list(id)

  def list(project_id) when is_binary(project_id) do
    ensure_defaults(project_id)
    load(project_id)
  end

  @spec get(Project.t() | Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, Role.t()} | {:error, :not_found}
  def get(%Project{id: id}, role_id), do: get(id, role_id)

  def get(project_id, role_id) when is_binary(project_id) and is_binary(role_id) do
    case Repo.get_by(Role, id: role_id, project_id: project_id) do
      %Role{} = role -> {:ok, role}
      nil -> {:error, :not_found}
    end
  end

  @spec save(Project.t(), map()) :: {:ok, Role.t()} | {:error, term()}
  def save(%Project{} = project, attrs) do
    %Role{}
    |> Role.changeset(Map.put(attrs, :project_id, project.id) |> Map.put(:id, Ids.generate()))
    |> Repo.insert()
  end

  @spec upsert(Project.t(), map()) :: {:ok, Role.t()} | {:error, term()}
  def upsert(%Project{} = project, attrs) when is_map(attrs) do
    params = role_params(attrs)
    upsert_named(project, params, params.name)
  end

  @spec attach(Project.t(), map()) :: map()
  def attach(%Project{} = project, attrs) when is_map(attrs) do
    _ = list(project)

    case fetch_requested(project, attrs) do
      {:ok, role} -> put_role(attrs, role)
      :none -> attrs
    end
  end

  @spec prompt_for(Session.t()) :: {:ok, String.t()} | :none
  def prompt_for(%Session{} = session) do
    with {:ok, role} <- role_for(session),
         prompt when prompt != "" <- String.trim(role.prompt || "") do
      {:ok, render(prompt, session)}
    else
      _ -> :none
    end
  end

  @spec card_description(Session.t(), String.t()) :: String.t()
  def card_description(%Session{} = session, adapter_name) do
    case role_for(session) do
      {:ok, %Role{description: desc}} when is_binary(desc) and desc != "" -> desc
      _ -> "#{adapter_name} session"
    end
  end

  @spec public_map(Role.t()) :: map()
  def public_map(%Role{} = role) do
    %{
      "id" => role.id,
      "name" => role.name,
      "description" => role.description,
      "permission_profile" => role.permission_profile
    }
  end

  defp load(project_id) do
    Role
    |> where([r], r.project_id == ^project_id)
    |> order_by([r], asc: r.name)
    |> Repo.all()
  end

  defp ensure_defaults(project_id) do
    have = MapSet.new(load(project_id), & &1.name)

    Enum.each(defaults(), fn attrs ->
      if MapSet.member?(have, attrs.name) do
        :ok
      else
        _ =
          %Role{}
          |> Role.changeset(Map.merge(attrs, %{id: Ids.generate(), project_id: project_id}))
          |> Repo.insert()
      end
    end)
  end

  defp fetch_requested(project, attrs) do
    id = Map.get(attrs, :role_id) || Map.get(attrs, "role_id")
    name = Map.get(attrs, :role) || Map.get(attrs, "role")

    cond do
      is_binary(id) and id != "" -> get(project.id, id)
      is_binary(name) and name != "" -> get_by_name(project.id, name)
      true -> :none
    end
    |> normalize_fetch()
  end

  defp role_params(attrs) do
    %{
      name: attr(attrs, :name, "name"),
      description: attr(attrs, :description, "description") || "",
      prompt: attr(attrs, :prompt, "prompt") || "",
      permission_profile: attr(attrs, :permission_profile, "permission_profile") || "default",
      skills: attr(attrs, :skills, "skills") || %{}
    }
  end

  defp attr(attrs, atom, string) do
    Map.get(attrs, atom) || Map.get(attrs, string)
  end

  defp upsert_named(_project, _params, name) when not is_binary(name), do: {:error, :invalid_role}
  defp upsert_named(_project, _params, ""), do: {:error, :invalid_role}

  defp upsert_named(project, params, name) do
    case get_by_name(project.id, name) do
      {:ok, role} -> role |> Role.changeset(params) |> Repo.update()
      {:error, :not_found} -> save(project, params)
    end
  end

  defp get_by_name(project_id, name) do
    key =
      name
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9_-]+/, "-")

    case Repo.get_by(Role, project_id: project_id, name: key) do
      %Role{} = role -> {:ok, role}
      nil -> {:error, :not_found}
    end
  end

  defp normalize_fetch({:ok, role}), do: {:ok, role}
  defp normalize_fetch({:error, :not_found}), do: :none
  defp normalize_fetch(:none), do: :none

  defp put_role(attrs, role) do
    settings =
      attrs
      |> existing_settings()
      |> Map.merge(%{
        "permission_profile" => role.permission_profile,
        "role_id" => role.id
      })

    attrs
    |> Map.put(:role, role.name)
    |> Map.put(:settings, settings)
  end

  defp existing_settings(attrs) do
    case Map.get(attrs, :settings) || Map.get(attrs, "settings") || %{} do
      map when is_map(map) -> Map.new(map, fn {key, value} -> {to_string(key), value} end)
      _ -> %{}
    end
  end

  defp role_for(%Session{settings: settings, project_id: project_id, role: role}) do
    id = settings["role_id"]

    cond do
      is_binary(id) -> get(project_id, id)
      is_binary(role) and role != "" -> get_by_name(project_id, role)
      true -> {:error, :not_found}
    end
  end

  defp render(prompt, session) do
    prompt
    |> String.replace("{{display_name}}", session.display_name || "")
    |> String.replace("{{role}}", session.role || "")
  end

  defp defaults do
    [
      %{
        name: "lead",
        description: "Analyzes work, splits tasks across specialists, and reviews results.",
        permission_profile: "default",
        prompt: """
        You are {{display_name}} in the lead role. Analyze the goal, split work with hub_split_work, \
        and review specialist results through Agent Hub. Remember decisions with memory_remember. \
        Do not merge to the primary branch. Assignment is not a lease.
        """
      },
      %{
        name: "backend",
        description: "Implements server, data, and API tasks in an isolated worktree.",
        permission_profile: "default",
        prompt: """
        You are {{display_name}} in the backend role. Work only in your assigned worktree. \
        Claim leases before editing shared files. Do not merge to the primary branch.
        """
      },
      %{
        name: "frontend",
        description: "Implements UI and frontend tasks in an isolated worktree.",
        permission_profile: "default",
        prompt: """
        You are {{display_name}} in the frontend role. Work only in your assigned worktree. \
        Claim leases before editing shared files. Do not merge to the primary branch.
        """
      },
      %{
        name: "tester",
        description: "Writes and runs tests in an isolated worktree.",
        permission_profile: "default",
        prompt: """
        You are {{display_name}} in the tester role. Work only in your assigned worktree. \
        Claim leases before editing shared files. Do not merge to the primary branch.
        """
      },
      %{
        name: "implementer",
        description: "Implements assigned tasks in an isolated worktree.",
        permission_profile: "default",
        prompt: """
        You are {{display_name}} in the implementer role. Work only in your assigned worktree. \
        Claim leases before editing shared files. Do not merge to the primary branch.
        """
      },
      %{
        name: "reviewer",
        description: "Reviews diffs, artifacts, and handoffs.",
        permission_profile: "default",
        prompt: """
        You are {{display_name}} in the reviewer role. Review diffs and handoffs. \
        Do not edit the primary worktree. Request changes through Agent Hub tools.
        """
      },
      %{
        name: "observer",
        description: "Read-only coordination and search.",
        permission_profile: "observer",
        prompt: """
        You are {{display_name}} in the observer role. You may list agents, search, and recall. \
        You must not claim resources, merge, or edit files.
        """
      }
    ]
  end
end
