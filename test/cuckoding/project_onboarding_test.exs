defmodule Cuckoding.ProjectOnboardingTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.Run
  alias Cuckoding.ProjectOnboarding
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  setup do
    repo_path =
      Path.join(
        System.tmp_dir!(),
        "cuckoding-project-onboarding-#{System.unique_integer([:positive])}"
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

  test "registers a dirty existing repository without creating executable work", %{
    repo_path: repo_path
  } do
    File.write!(Path.join(repo_path, "README.md"), "# Existing dirty project\n")
    original_head = git!(repo_path, ["rev-parse", "HEAD"])

    before_counts = execution_counts()

    assert {:ok, %{project: project, config: config}} =
             ProjectOnboarding.create(%{
               "name" => "Existing application",
               "description" => "Already has code",
               "repo_path" => repo_path,
               "default_branch" => "main",
               "runtime" => "codex",
               "executable_path" => "/usr/bin/true",
               "api_key_helper" => ""
             })

    assert project.repo_path == canonical_path(repo_path)
    assert project.default_branch == "main"
    assert git!(repo_path, ["rev-parse", "HEAD"]) == original_head
    assert git!(repo_path, ["status", "--porcelain"]) != ""
    assert config.project_id == project.id
    assert config.revision == 1
    assert config.config_json["runner"] == "local_process"

    assert Enum.map(config.config_json["default_roles"], & &1["name"]) == [
             "Specifications",
             "Coding",
             "Review"
           ]

    assert Enum.all?(
             config.config_json["default_roles"],
             &(&1["agent_connection_key"] == "primary")
           )

    assert execution_counts() == before_counts
    assert Repo.aggregate(ProjectConfigVersion, :count) > 0
  end

  test "rejects a relative repository path before inspecting it" do
    assert {:error, :invalid_repository_path} =
             ProjectOnboarding.validate_repository(%{
               "repo_path" => "relative/repository",
               "default_branch" => "main"
             })
  end

  test "initializes a project folder and commits its existing files" do
    repo_path = temporary_directory("plain-folder")
    File.write!(Path.join(repo_path, "README.md"), "# Existing files\n")

    assert {:ok, {_path, %{action: :initialize}}} =
             ProjectOnboarding.validate_repository(%{
               "repo_path" => repo_path,
               "default_branch" => "main"
             })

    refute File.exists?(Path.join(repo_path, ".git"))

    assert {:ok, %{project: project, config: config}} =
             ProjectOnboarding.create(project_attrs(repo_path, "Plain folder"))

    assert project.repo_path == canonical_path(repo_path)

    assert config.config_json["base_sha_at_registration"] ==
             git!(repo_path, ["rev-parse", "HEAD"])

    assert git!(repo_path, ["status", "--porcelain"]) == ""
    assert git!(repo_path, ["ls-files"]) == "README.md"
  end

  test "creates the first commit in an unborn Git repository" do
    repo_path = temporary_directory("unborn-repository")
    git!(repo_path, ["init", "-b", "main"])

    assert {:ok, %{config: config}} =
             ProjectOnboarding.create(project_attrs(repo_path, "Unborn repository"))

    assert config.config_json["base_sha_at_registration"] ==
             git!(repo_path, ["rev-parse", "HEAD"])

    assert git!(repo_path, ["status", "--porcelain"]) == ""
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
    assert {output, 0} =
             System.cmd("/usr/bin/git", args,
               cd: repo_path,
               stderr_to_stdout: true,
               env: [{"LC_ALL", "C"}]
             )

    String.trim(output)
  end

  defp canonical_path(path) do
    {resolved, 0} = System.cmd("/bin/pwd", ["-P"], cd: path)
    String.trim(resolved)
  end

  defp temporary_directory(label) do
    path =
      Path.join(
        System.tmp_dir!(),
        "cuckoding-project-onboarding-#{label}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  defp project_attrs(repo_path, name) do
    %{
      "name" => name,
      "description" => "",
      "repo_path" => repo_path,
      "default_branch" => "main",
      "runtime" => "codex",
      "executable_path" => "/usr/bin/true",
      "api_key_helper" => ""
    }
  end
end
