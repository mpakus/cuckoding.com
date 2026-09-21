defmodule Cuckoding.ProjectOnboardingTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Adapters
  alias Cuckoding.Adapters.ProviderAccount
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.Run
  alias Cuckoding.ProjectOnboarding
  alias Cuckoding.Projects
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

    assert config.config_json["agent_connections"] == []
    assert Enum.all?(config.config_json["default_roles"], &is_nil(&1["agent_connection_key"]))

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

  test "versions multiple agent connections and role assignments without starting work", %{
    repo_path: repo_path
  } do
    assert {:ok, %{project: project, config: original}} =
             ProjectOnboarding.create(project_attrs(repo_path, "Multiple agents"))

    roles =
      ProjectOnboarding.default_roles()
      |> Enum.with_index()
      |> Enum.map(fn {role, index} ->
        Map.put(role, "agent_connection_key", if(index == 2, do: "reviewer", else: "coder"))
      end)

    attrs = %{
      "agent_connections" => [
        %{
          "key" => "coder",
          "label" => "Primary Codex",
          "adapter_key" => "codex",
          "executable_path" => "/usr/bin/true",
          "api_key_helper" => ""
        },
        %{
          "key" => "reviewer",
          "label" => "Independent reviewer",
          "adapter_key" => "custom_agent",
          "executable_path" => "/usr/bin/true",
          "api_key_helper" => "ignored"
        }
      ],
      "default_roles" => roles
    }

    assert {:ok, config} = ProjectOnboarding.update_configuration(project.id, 1, attrs)
    assert config.revision == 2
    assert original.config_json["agent_connections"] == []

    assert [coder, reviewer] = config.config_json["agent_connections"]
    assert coder["key"] == "coder"
    assert coder["adapter_key"] == "codex"
    assert is_binary(coder["provider_account_id"])
    assert reviewer["key"] == "reviewer"
    assert is_binary(reviewer["provider_account_id"])
    assert reviewer["settings"] == %{"executable_path" => "/usr/bin/true"}
    assert Enum.at(config.config_json["default_roles"], 2)["agent_connection_key"] == "reviewer"

    assert Projects.latest_config_version(project.id).id == config.id

    assert {:error, :stale_configuration} =
             ProjectOnboarding.update_configuration(project.id, 1, attrs)

    assert execution_counts() == %{boards: 0, tasks: 0, runs: 0, environments: 0}
  end

  test "refuses an unassigned role without creating a configuration revision", %{
    repo_path: repo_path
  } do
    assert {:ok, %{project: project}} =
             ProjectOnboarding.create(project_attrs(repo_path, "Invalid role mapping"))

    roles =
      Enum.map(ProjectOnboarding.default_roles(), &Map.put(&1, "agent_connection_key", ""))

    assert {:error, :role_agent_required} =
             ProjectOnboarding.update_configuration(project.id, 1, %{
               "agent_connections" => [
                 %{
                   "key" => "agent-1",
                   "label" => "Codex",
                   "adapter_key" => "codex",
                   "executable_path" => "/usr/bin/true"
                 }
               ],
               "default_roles" => roles
             })

    assert Projects.latest_config_version(project.id).revision == 1
  end

  test "saves and updates one agent without requiring or rewriting role assignments", %{
    repo_path: repo_path
  } do
    assert {:ok, %{project: project}} =
             ProjectOnboarding.create(project_attrs(repo_path, "Independent agent save"))

    agent = %{
      "key" => "agent-1",
      "label" => "Primary Codex",
      "adapter_key" => "codex",
      "executable_path" => "/usr/bin/true"
    }

    assert {:ok, created} = ProjectOnboarding.save_connection(project.id, 1, agent)
    assert created.revision == 2

    assert [%{"label" => "Primary Codex", "provider_account_id" => account_id}] =
             created.config_json["agent_connections"]

    assert %ProviderAccount{label: "Primary Codex", auth_mode: "shared_profile"} =
             Adapters.get_provider_account(account_id)

    assert Enum.all?(
             created.config_json["default_roles"],
             &is_nil(&1["agent_connection_key"])
           )

    assert {:ok, updated} =
             ProjectOnboarding.save_connection(
               project.id,
               2,
               Map.put(agent, "label", "Updated Codex")
             )

    assert updated.revision == 3

    assert [%{"label" => "Updated Codex", "provider_account_id" => ^account_id}] =
             updated.config_json["agent_connections"]

    assert [%ProviderAccount{id: ^account_id, label: "Updated Codex"}] =
             Adapters.list_provider_accounts()

    assert updated.config_json["default_roles"] == created.config_json["default_roles"]

    assert {:error, :stale_configuration} =
             ProjectOnboarding.save_connection(project.id, 2, agent)

    assert {:error, :invalid_runtime_executable} =
             ProjectOnboarding.save_connection(
               project.id,
               3,
               Map.put(agent, "executable_path", "relative")
             )

    assert Projects.latest_config_version(project.id).revision == 3
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
      "default_branch" => "main"
    }
  end
end
