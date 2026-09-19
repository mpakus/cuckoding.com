defmodule CuckodingWeb.ProjectSetupLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.Run
  alias Cuckoding.Projects
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  setup do
    repo_path =
      Path.join(
        System.tmp_dir!(),
        "cuckoding-project-setup-live-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(repo_path)
    git!(repo_path, ["init", "-b", "main"])
    git!(repo_path, ["config", "user.email", "tests@cuckoding.local"])
    git!(repo_path, ["config", "user.name", "Cuckoding Tests"])
    File.write!(Path.join(repo_path, "README.md"), "# Existing project\n")
    git!(repo_path, ["add", "README.md"])
    git!(repo_path, ["commit", "-m", "Initial commit"])

    on_exit(fn -> File.rm_rf!(repo_path) end)

    %{repo_path: repo_path}
  end

  test "walks through project setup and registers only the project", %{
    conn: conn,
    repo_path: repo_path
  } do
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    assert has_element?(view, "h1", "Add a project")

    assert has_element?(
             view,
             "nav[aria-label='Project setup progress'] [aria-current=step]",
             "Project"
           )

    assert has_element?(view, "#project-step-1 input[name='project[name]']")

    view
    |> form("#project-step-1", project: %{name: "My application", description: "Existing code"})
    |> render_submit()

    assert has_element?(view, "#project-step-2")
    assert has_element?(view, "[aria-current=step]", "Repository")
    assert has_element?(view, "#project-repo-path[readonly]")
    assert has_element?(view, "#choose-project-folder", "Choose folder")

    previous_picker = Application.get_env(:cuckoding, :folder_picker)
    Application.put_env(:cuckoding, :folder_picker, fn -> {:ok, repo_path} end)

    on_exit(fn ->
      if previous_picker,
        do: Application.put_env(:cuckoding, :folder_picker, previous_picker),
        else: Application.delete_env(:cuckoding, :folder_picker)
    end)

    render_click(view, "choose_folder")
    assert has_element?(view, "#project-repo-path[value='#{repo_path}']")

    view
    |> form("#project-step-2",
      project: %{default_branch: "main"}
    )
    |> render_submit()

    assert has_element?(view, "#project-step-3")
    assert has_element?(view, "#roles-heading", "Default roles")
    assert has_element?(view, "li", "Specifications")
    assert has_element?(view, "li", "Coding")
    assert has_element?(view, "li", "Review")
    assert has_element?(view, "option[value=cursor_agent]", "Cursor Agent")
    assert has_element?(view, "option[value=opencode]", "OpenCode")
    assert has_element?(view, "option[value=custom_agent]", "Custom Agent")
    refute has_element?(view, "input[name='project[api_key_helper]']")

    render_change(view, "runtime_changed", %{"project" => %{"runtime" => "claude_code"}})
    assert has_element?(view, "input[name='project[api_key_helper]']")

    render_change(view, "runtime_changed", %{"project" => %{"runtime" => "custom_agent"}})
    refute has_element?(view, "input[name='project[api_key_helper]']")
    assert has_element?(view, "#runtime-availability-warning", "runs remain blocked")

    render_change(view, "runtime_changed", %{"project" => %{"runtime" => "codex"}})
    refute has_element?(view, "#runtime-availability-warning")

    view
    |> form("#project-step-3",
      project: %{
        runtime: "codex",
        executable_path: "/usr/bin/true"
      }
    )
    |> render_submit()

    assert has_element?(view, "#project-step-4")
    assert has_element?(view, "#host-runner-notice", "not a sandbox")
    assert has_element?(view, "#project-step-4", "Use the existing repository")
    assert has_element?(view, "#project-step-4", "Do not start agents")

    before_counts = execution_counts()

    view
    |> form("#project-step-4", project: %{confirmed: "true"})
    |> render_submit()

    assert_redirect(view, ~p"/")
    assert Projects.list_projects() |> Enum.any?(&(&1.name == "My application"))
    assert execution_counts() == before_counts
  end

  test "requires server-side confirmation before registration", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/projects/new")

    render_submit(view, "create", %{"project" => %{"confirmed" => "false"}})

    assert has_element?(
             view,
             "#project-setup-error[role=alert]",
             "Confirm the repository and host-runner settings"
           )

    assert Projects.list_projects() == []
  end

  defp execution_counts do
    %{
      boards: Repo.aggregate(Board, :count),
      tasks: Repo.aggregate(Task, :count),
      runs: Repo.aggregate(Run, :count),
      environments: Repo.aggregate(Environment, :count)
    }
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
