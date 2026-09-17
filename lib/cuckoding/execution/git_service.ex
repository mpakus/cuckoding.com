defmodule Cuckoding.Execution.GitService do
  @moduledoc """
  Owns host-side Git worktree creation and read-only drift inspection.

  This service confines paths and constrains Git arguments. It does not sandbox host processes.
  """

  require Logger

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.Run
  alias Cuckoding.Projects.Project
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  @git "/usr/bin/git"
  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
  @sha ~r/\A[0-9a-f]{40}\z/

  @doc "Captures the clean default-branch revision used to create a run."
  def capture_base(%Project{} = project) do
    with {:ok, repo} <- canonical_directory(project.repo_path),
         :ok <- repository_root?(repo),
         :ok <- valid_branch?(project.default_branch),
         {:ok, true} <- clean?(repo),
         {:ok, sha} <-
           git(repo, ["rev-parse", "--verify", "refs/heads/#{project.default_branch}^{commit}"]) do
      {:ok, String.trim(sha)}
    else
      {:ok, false} -> {:error, :dirty_repository}
      error -> error
    end
  end

  @doc "Creates the run-owned branch/worktree and its durable environment row."
  def prepare(%Project{} = project, %Run{} = run) do
    with :ok <- valid_id?(project.id),
         :ok <- valid_id?(run.id),
         :ok <- valid_branch?(run.branch),
         :ok <- unprotected_branch?(run.branch, project.default_branch),
         :ok <- valid_sha?(run.base_sha),
         {:ok, repo} <- canonical_directory(project.repo_path),
         :ok <- repository_root?(repo),
         {:ok, true} <- clean?(repo),
         {:ok, base_sha} <- resolve_commit(repo, run.base_sha),
         {:ok, current_base} <-
           git(repo, ["rev-parse", "--verify", "refs/heads/#{project.default_branch}^{commit}"]),
         :ok <- base_matches?(base_sha, current_base),
         :ok <- branch_available?(repo, run.branch),
         {:ok, workspace_root} <- workspace_root(project.workspace_root),
         {:ok, run_dir, worktree} <- available_paths(workspace_root, project.id, run.id),
         {:ok, ownership} <- ownership(project, run, base_sha),
         :ok <- create_run_directory(run_dir, workspace_root),
         :ok <- write_marker(run_dir, ownership),
         {:ok, _output} <- git(repo, ["worktree", "add", "-b", run.branch, worktree, base_sha]),
         {:ok, ^base_sha} <- head(worktree),
         :ok <- confined_directory?(worktree, workspace_root),
         {:ok, environment} <- persist_environment(run, run_dir, worktree, base_sha) do
      Logger.info(
        "created run worktree project_id=#{project.id} run_id=#{run.id} " <>
          "branch=#{run.branch} base_sha=#{base_sha}"
      )

      {:ok, environment}
    else
      {:ok, false} -> {:error, :dirty_repository}
      error -> error
    end
  end

  @doc "Reports unrecorded branch or revision drift without changing the worktree."
  def inspect(%Environment{} = environment) do
    with %Run{} = run <- Repo.get(Run, environment.run_id),
         %Task{} = task <- Repo.get(Task, run.task_id),
         %Board{} = board <- Repo.get(Board, task.board_id),
         %Project{} = project <- Repo.get(Project, board.project_id),
         %ProjectConfigVersion{} = policy <-
           Repo.get(ProjectConfigVersion, run.policy_snapshot_id),
         {:ok, repo} <- canonical_directory(project.repo_path),
         :ok <- repository_root?(repo),
         {:ok, workspace_root} <- canonical_directory(project.workspace_root),
         :ok <- confined_directory?(environment.run_dir, workspace_root),
         :ok <- confined_directory?(environment.worktree_path, workspace_root),
         :ok <- marker_matches?(environment, project, task, run, policy),
         {:ok, current_base} <-
           git(repo, [
             "rev-parse",
             "--verify",
             "refs/heads/#{project.default_branch}^{commit}"
           ]),
         {:ok, branch} <-
           git(environment.worktree_path, ["symbolic-ref", "--quiet", "--short", "HEAD"]),
         {:ok, head_sha} <- head(environment.worktree_path),
         {:ok, clean} <- clean?(environment.worktree_path) do
      drift_status(
        String.trim(current_base),
        String.trim(branch),
        head_sha,
        clean,
        run,
        environment
      )
    else
      nil -> {:error, :ownership_source_not_found}
      {:error, :missing_directory} -> :missing
      {:drift, reason} -> {:drift, reason}
      {:error, reason} -> {:error, reason}
    end
  end

  defp drift_status(current_base, branch, head_sha, clean, run, environment) do
    cond do
      current_base != environment.base_sha -> {:drift, :base_changed}
      branch != run.branch -> {:drift, :branch_changed}
      head_sha != environment.head_sha -> {:drift, :head_changed}
      true -> {:ok, %{clean?: clean, head_sha: head_sha}}
    end
  end

  defp workspace_root(path) do
    expanded = Path.expand(path)

    with :ok <- File.mkdir_p(expanded), do: canonical_directory(expanded)
  end

  defp available_paths(root, project_id, run_id) do
    run_dir = Path.join([root, project_id, run_id])
    worktree = Path.join(run_dir, "worktree")

    with :ok <- lexical_confinement?(run_dir, root),
         :ok <- no_symlink_components?(run_dir, root),
         false <- File.exists?(run_dir) do
      {:ok, run_dir, worktree}
    else
      true -> {:error, :run_directory_exists}
      error -> error
    end
  end

  defp create_run_directory(run_dir, root) do
    with :ok <- File.mkdir_p(run_dir), do: confined_directory?(run_dir, root)
  end

  defp lexical_confinement?(path, root) do
    relative = Path.relative_to(Path.expand(path), Path.expand(root))

    if relative == ".." or String.starts_with?(relative, "../") or
         Path.type(relative) == :absolute do
      {:error, :path_escape}
    else
      :ok
    end
  end

  defp no_symlink_components?(path, root) do
    relative = Path.relative_to(path, root)

    relative
    |> Path.split()
    |> Enum.reduce_while(root, fn component, parent ->
      current = Path.join(parent, component)

      case File.lstat(current) do
        {:ok, %{type: :symlink}} -> {:halt, {:error, :symlink_component}}
        {:ok, _stat} -> {:cont, current}
        {:error, :enoent} -> {:cont, current}
        {:error, reason} -> {:halt, {:error, {:path_inspection_failed, reason}}}
      end
    end)
    |> case do
      {:error, _reason} = error -> error
      _path -> :ok
    end
  end

  defp confined_directory?(path, root) do
    with {:ok, resolved_root} <- canonical_directory(root),
         {:ok, resolved_path} <- canonical_directory(path),
         do: lexical_confinement?(resolved_path, resolved_root)
  end

  defp canonical_directory(path) do
    expanded = Path.expand(path)

    case File.stat(expanded) do
      {:ok, %{type: :directory}} ->
        case System.cmd("/bin/pwd", ["-P"], cd: expanded, stderr_to_stdout: true) do
          {resolved, 0} -> {:ok, String.trim(resolved)}
          {_output, _status} -> {:error, :path_resolution_failed}
        end

      {:ok, _stat} ->
        {:error, :not_a_directory}

      {:error, :enoent} ->
        {:error, :missing_directory}

      {:error, reason} ->
        {:error, {:path_inspection_failed, reason}}
    end
  end

  defp ownership(project, run, base_sha) do
    with %Task{} = task <- Repo.get(Task, run.task_id),
         %Board{} = board <- Repo.get(Board, task.board_id),
         %ProjectConfigVersion{} = policy <-
           Repo.get(ProjectConfigVersion, run.policy_snapshot_id),
         true <- board.project_id == project.id and policy.project_id == project.id do
      {:ok,
       %{
         version: 1,
         project_id: project.id,
         board_id: task.board_id,
         task_id: task.id,
         run_id: run.id,
         policy_hash: policy.source_hash,
         branch: run.branch,
         base_sha: base_sha,
         head_sha: base_sha
       }}
    else
      nil -> {:error, :ownership_source_not_found}
      false -> {:error, :project_mismatch}
    end
  end

  defp write_marker(run_dir, ownership) do
    marker = Path.join(run_dir, "run.json")
    temporary = marker <> ".tmp"

    with :ok <- File.write(temporary, Jason.encode_to_iodata!(ownership)),
         do: File.rename(temporary, marker)
  end

  defp marker_matches?(environment, project, task, run, policy) do
    expected = %{
      "project_id" => project.id,
      "board_id" => task.board_id,
      "task_id" => task.id,
      "run_id" => run.id,
      "policy_hash" => policy.source_hash,
      "branch" => run.branch,
      "base_sha" => environment.base_sha,
      "head_sha" => environment.head_sha
    }

    with {:ok, contents} <- File.read(Path.join(environment.run_dir, "run.json")),
         {:ok, marker} <- Jason.decode(contents) do
      if Map.take(marker, Map.keys(expected)) == expected,
        do: :ok,
        else: {:drift, :ownership_marker_changed}
    else
      _error -> {:drift, :ownership_marker_changed}
    end
  end

  defp persist_environment(run, run_dir, worktree, base_sha) do
    Execution.create_environment(%{
      run_id: run.id,
      runner_key: "local_process",
      kind: "local_process",
      worktree_path: worktree,
      run_dir: run_dir,
      base_sha: base_sha,
      head_sha: base_sha,
      ports_json: %{},
      isolation_claims_json: %{
        "filesystem" => "policy_confined",
        "process" => "host",
        "sandbox" => false
      }
    })
  end

  defp repository_root?(repo) do
    case git(repo, ["rev-parse", "--show-toplevel"]) do
      {:ok, root} ->
        if String.trim(root) == repo, do: :ok, else: {:error, :repository_root_mismatch}

      {:error, _reason} ->
        {:error, :not_a_git_repository}
    end
  end

  defp clean?(repo) do
    with {:ok, status} <- git(repo, ["status", "--porcelain", "--untracked-files=all"]) do
      {:ok, String.trim(status) == ""}
    end
  end

  defp head(worktree) do
    with {:ok, sha} <- git(worktree, ["rev-parse", "HEAD"]) do
      {:ok, String.trim(sha)}
    end
  end

  defp resolve_commit(repo, sha) do
    with {:ok, resolved} <- git(repo, ["rev-parse", "--verify", "#{sha}^{commit}"]) do
      {:ok, String.trim(resolved)}
    end
  end

  defp valid_id?(id) when is_binary(id) do
    if Regex.match?(@uuid, id), do: :ok, else: {:error, :invalid_identifier}
  end

  defp valid_id?(_id), do: {:error, :invalid_identifier}

  defp valid_sha?(sha) when is_binary(sha) do
    if Regex.match?(@sha, sha), do: :ok, else: {:error, :invalid_base_sha}
  end

  defp valid_sha?(_sha), do: {:error, :invalid_base_sha}

  defp valid_branch?(branch) when is_binary(branch) do
    case System.cmd(@git, ["check-ref-format", "--branch", branch], stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {_output, _status} -> {:error, :invalid_branch}
    end
  end

  defp valid_branch?(_branch), do: {:error, :invalid_branch}

  defp unprotected_branch?(branch, default_branch) do
    if branch in Enum.uniq([default_branch, "main", "master"]),
      do: {:error, :protected_branch},
      else: :ok
  end

  defp branch_available?(repo, branch) do
    case System.cmd(
           @git,
           ["-C", repo, "show-ref", "--verify", "--quiet", "refs/heads/#{branch}"],
           stderr_to_stdout: true
         ) do
      {_output, 1} -> :ok
      {_output, 0} -> {:error, :branch_exists}
      {output, status} -> {:error, {:git_failed, status, String.trim(output)}}
    end
  end

  defp base_matches?(base_sha, current_base) do
    if base_sha == String.trim(current_base), do: :ok, else: {:error, :base_changed}
  end

  defp git(repo, args) do
    case System.cmd(@git, ["-C", repo | args], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {:git_failed, status, String.trim(output)}}
    end
  end
end
