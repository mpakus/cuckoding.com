defmodule CuckodingWeb.ProjectEditLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Cuckoding.Adapters
  alias Cuckoding.ProjectOnboarding
  alias Cuckoding.Projects
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo
  alias Cuckoding.Workflows
  alias Cuckoding.Workflows.RoleAssignment

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

    view
    |> form("#create-board-form",
      board: %{name: "Product", description: "Default delivery flow", concurrency_limit: "2"}
    )
    |> render_submit()

    assert [board] = Workflows.list_boards(project.id)
    assert_redirect(view, ~p"/boards/#{board.id}")
    assert board.concurrency_limit == 2

    assert Repo.aggregate(
             from(role in RoleAssignment, where: role.board_id == ^board.id),
             :count
           ) == 6

    assert Repo.get_by!(RoleAssignment, board_id: board.id, role_key: "spec_writer").adapter_key ==
             "claude_code"

    assert Repo.get_by!(RoleAssignment, board_id: board.id, role_key: "implementer").adapter_key ==
             "codex"
  end

  test "saves and updates an agent before roles are assigned", %{conn: conn, project: project} do
    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/edit")

    render_click(view, "add_connection")
    assert has_element?(view, "#agent-connection-0 button", "Save agent")

    config = %{
      "agent_connections" => %{
        "0" => %{
          "key" => "agent-1",
          "label" => "Primary Codex",
          "adapter_key" => "codex",
          "executable_path" => "/usr/bin/true"
        }
      },
      "default_roles" => role_params_without_agents()
    }

    render_change(view, "sync", %{"config" => config})
    view |> element("#agent-connection-0 button", "Save agent") |> render_click()

    assert has_element?(view, "#project-edit-status", "Primary Codex saved")
    assert has_element?(view, "#agent-connection-0 button", "Update agent")
    assert has_element?(view, "#saved-agents-heading", "Saved agents")
    assert has_element?(view, "[id^='saved-agent-command-'] input[data-copy-source][readonly]")
    assert Projects.latest_config_version(project.id).revision == 2

    updated = put_in(config, ["agent_connections", "0", "label"], "Updated Codex")

    render_change(view, "sync", %{"config" => updated})
    view |> element("#agent-connection-0 button", "Update agent") |> render_click()

    assert has_element?(view, "#project-edit-status", "Updated Codex saved")
    latest = Projects.latest_config_version(project.id)
    assert latest.revision == 3
    assert [%{"label" => "Updated Codex"}] = latest.config_json["agent_connections"]
    assert Enum.all?(latest.config_json["default_roles"], &is_nil(&1["agent_connection_key"]))
  end

  test "attaches a saved agent without re-entering runtime settings", %{
    conn: conn,
    project: project
  } do
    assert {:ok, account} =
             Adapters.save_provider_account(%{
               adapter_key: "codex",
               label: "Shared Codex",
               auth_mode: "os_keyring",
               capabilities_json: %{
                 "settings" => %{"executable_path" => "/usr/bin/true"}
               }
             })

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/edit")

    assert has_element?(view, "#saved-agent-#{account.id}", "Use in this project")
    render_click(view, "use-saved-agent", %{"id" => account.id})

    assert has_element?(
             view,
             "input[name='config[agent_connections][0][provider_account_id]'][value='#{account.id}']"
           )

    assert has_element?(view, "#agent-connection-0 input[value='Shared Codex']")
    assert has_element?(view, "#saved-agent-#{account.id} button[disabled]", "Attached")
  end

  test "checks one saved Codex authorization and records its status", %{
    conn: conn,
    project: project
  } do
    executable = Path.join(project.repo_path, "codex-test")

    File.write!(
      executable,
      "#!/bin/sh\nif [ \"$1\" = \"--version\" ]; then echo 'codex-cli 0.146.0'; else echo 'Logged in using ChatGPT'; fi\n"
    )

    File.chmod!(executable, 0o700)

    assert {:ok, account} =
             Adapters.save_provider_account(%{
               adapter_key: "codex",
               label: "Authorized Codex",
               auth_mode: "os_keyring",
               capabilities_json: %{"settings" => %{"executable_path" => executable}}
             })

    {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/edit")
    render_click(view, "check-agent-authorization", %{"id" => account.id})

    assert has_element?(view, "#project-edit-status", "authorized and ready for every project")
    assert has_element?(view, "#saved-agent-#{account.id}", "Authorized")
    assert Adapters.get_provider_account(account.id).status == "authenticated"
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

  defp role_params_without_agents do
    ProjectOnboarding.default_roles()
    |> Enum.with_index()
    |> Map.new(fn {role, index} ->
      {Integer.to_string(index),
       %{
         "key" => role["key"],
         "name" => role["name"],
         "instructions" => role["instructions"],
         "agent_connection_key" => ""
       }}
    end)
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
