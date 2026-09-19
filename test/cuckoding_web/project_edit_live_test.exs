defmodule CuckodingWeb.ProjectEditLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.ProjectOnboarding
  alias Cuckoding.Projects
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo

  setup do
    repo_path =
      Path.join(
        System.tmp_dir!(),
        "cuckoding-project-edit-live-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(repo_path)
    git!(repo_path, ["init", "-b", "main"])
    git!(repo_path, ["config", "user.email", "tests@cuckoding.local"])
    git!(repo_path, ["config", "user.name", "Cuckoding Tests"])
    File.write!(Path.join(repo_path, "README.md"), "# Project settings\n")
    git!(repo_path, ["add", "README.md"])
    git!(repo_path, ["commit", "-m", "Initial commit"])

    assert {:ok, %{project: project}} =
             ProjectOnboarding.create(%{
               "name" => "Editable project",
               "description" => "",
               "repo_path" => repo_path,
               "default_branch" => "main"
             })

    on_exit(fn -> File.rm_rf!(repo_path) end)
    %{project: project}
  end

  test "adds agents, assigns built-in and custom roles, and saves a new revision", %{
    conn: conn,
    project: project
  } do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/edit")

    assert has_element?(view, "h1", project.name)
    assert has_element?(view, "#agents-empty", "No agents connected yet")
    assert has_element?(view, "#project-role-spec_writer")
    assert has_element?(view, "#project-role-implementer")
    assert has_element?(view, "#project-role-reviewer")

    render_click(view, "add_connection")
    render_click(view, "add_connection")
    render_click(view, "add_role")

    assert has_element?(view, "#agent-connection-0")
    assert has_element?(view, "#agent-connection-1")
    assert has_element?(view, "#project-role-custom-1")

    config = %{
      "agent_connections" => %{
        "0" => %{
          "key" => "agent-1",
          "label" => "Claude specifications",
          "adapter_key" => "claude_code",
          "executable_path" => "/usr/bin/true",
          "api_key_helper" => "/usr/bin/true"
        },
        "1" => %{
          "key" => "agent-2",
          "label" => "Codex implementation",
          "adapter_key" => "codex",
          "executable_path" => "/usr/bin/true"
        }
      },
      "default_roles" => role_params()
    }

    render_change(view, "sync", %{"config" => config})
    assert has_element?(view, "input[name='config[agent_connections][0][api_key_helper]']")
    refute has_element?(view, "input[name='config[agent_connections][1][api_key_helper]']")

    view
    |> form("#project-config-form", config: config)
    |> render_submit()

    assert has_element?(view, "#project-edit-status", "saved as revision 2")
    assert has_element?(view, "span", "Configuration revision 2")

    latest = Projects.latest_config_version(project.id)
    assert latest.revision == 2
    assert length(latest.config_json["agent_connections"]) == 2
    assert length(latest.config_json["default_roles"]) == 4

    original = Repo.get_by!(ProjectConfigVersion, project_id: project.id, revision: 1)
    assert original.config_json["agent_connections"] == []
  end

  defp role_params do
    ProjectOnboarding.default_roles()
    |> Enum.with_index()
    |> Map.new(fn {role, index} ->
      {Integer.to_string(index),
       %{
         "key" => role["key"],
         "name" => role["name"],
         "instructions" => role["instructions"],
         "agent_connection_key" => if(index == 0, do: "agent-1", else: "agent-2")
       }}
    end)
    |> Map.put("3", %{
      "key" => "custom-1",
      "name" => "Security",
      "instructions" => "Review trust boundaries and produce actionable findings.",
      "agent_connection_key" => "agent-1"
    })
  end

  defp git!(repo_path, args) do
    assert {_output, 0} =
             System.cmd("/usr/bin/git", args,
               cd: repo_path,
               stderr_to_stdout: true,
               env: [{"LC_ALL", "C"}]
             )
  end
end
