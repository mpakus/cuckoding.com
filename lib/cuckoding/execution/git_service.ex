defmodule Cuckoding.Execution.GitService do
  @moduledoc """
  Owns host-side Git worktree creation and read-only drift inspection.

  This service confines paths and constrains Git arguments. It does not sandbox host processes.
  """

  require Logger

  import Kernel, except: [inspect: 1]
  import Ecto.Query, only: [from: 2]

  alias Cuckoding.Execution
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.ProcessRecord
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
    with {:ok, {_repo, sha}} <-
           validate_repository(project.repo_path, project.default_branch) do
      {:ok, sha}
    end
  end

  @doc "Validates and canonicalizes a clean repository and its default-branch revision."
  def validate_repository(path, default_branch)
      when is_binary(path) and is_binary(default_branch) do
    with {:ok, repo} <- canonical_directory(path),
         :ok <- repository_root?(repo),
         :ok <- valid_branch?(default_branch),
         {:ok, true} <- clean?(repo),
         {:ok, sha} <-
           git(repo, ["rev-parse", "--verify", "refs/heads/#{default_branch}^{commit}"]) do
      {:ok, {repo, String.trim(sha)}}
    else
      {:ok, false} -> {:error, :dirty_repository}
      error -> error
    end
  end

  def validate_repository(_path, _default_branch), do: {:error, :invalid_repository}

  @doc "Inspects a project folder without changing it and reports any required Git setup."
  def inspect_registration(path, default_branch)
      when is_binary(path) and is_binary(default_branch) do
    if Path.type(path) == :absolute and String.trim(path) != "" do
      with {:ok, repo} <- canonical_directory(path),
           :ok <- valid_branch?(default_branch) do
        inspect_registration_repo(repo, default_branch)
      end
    else
      {:error, :invalid_repository_path}
    end
  end

  def inspect_registration(_path, _default_branch), do: {:error, :invalid_repository}

  @doc "Makes a confirmed project folder a usable Git repository and returns its base revision."
  def ensure_registration(path, default_branch) do
    with {:ok, registration} <- inspect_registration(path, default_branch) do
      prepare_registration(registration)
    end
  end

  @doc "Returns the checked-out branch when the selected folder is already a Git repository."
  def suggested_registration_branch(path, fallback)
      when is_binary(path) and is_binary(fallback) do
    with true <- Path.type(path) == :absolute,
         {:ok, repo} <- canonical_directory(path),
         {:ok, branch} <- git(repo, ["symbolic-ref", "--quiet", "--short", "HEAD"]) do
      String.trim(branch)
    else
      _reason -> fallback
    end
  end

  def suggested_registration_branch(_path, fallback), do: fallback

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

  @doc "Commits an explicit set of regular files and records the resulting candidate revision."
  def commit_candidate(%Environment{} = environment, relative_paths, message)
      when is_list(relative_paths) and is_binary(message) do
    with {:ok, %{clean?: false}} <- inspect(environment),
         :ok <- valid_commit_message?(message),
         {:ok, paths} <- candidate_paths(environment, relative_paths),
         {:ok, _output} <- git(environment.worktree_path, ["add", "--" | paths]),
         {:ok, _output} <- git(environment.worktree_path, ["commit", "-m", message]) do
      record_candidate(environment)
    else
      {:ok, %{clean?: true}} -> {:error, :candidate_revision_unchanged}
      error -> error
    end
  end

  @doc "Accepts a clean agent-created commit as the immutable candidate revision."
  def record_candidate(%Environment{} = environment) do
    with %Run{} = run <- Repo.get(Run, environment.run_id),
         %Task{} = task <- Repo.get(Task, run.task_id),
         %Board{} = board <- Repo.get(Board, task.board_id),
         %Project{} = project <- Repo.get(Project, board.project_id),
         %ProjectConfigVersion{} = policy <-
           Repo.get(ProjectConfigVersion, run.policy_snapshot_id),
         {:ok, repo} <- canonical_directory(project.repo_path),
         {:ok, workspace_root} <- canonical_directory(project.workspace_root),
         :ok <- confined_directory?(environment.run_dir, workspace_root),
         :ok <- confined_directory?(environment.worktree_path, workspace_root),
         :ok <- marker_matches?(environment, project, task, run, policy),
         {:ok, current_base} <-
           git(repo, ["rev-parse", "--verify", "refs/heads/#{project.default_branch}^{commit}"]),
         :ok <- base_matches?(environment.base_sha, current_base),
         {:ok, branch} <-
           git(environment.worktree_path, ["symbolic-ref", "--quiet", "--short", "HEAD"]),
         true <- String.trim(branch) == run.branch,
         {:ok, true} <- clean?(environment.worktree_path),
         {:ok, candidate_sha} <- head(environment.worktree_path),
         true <- candidate_sha != environment.head_sha,
         {:ok, {_event, accepted}} <- accept_candidate(environment, candidate_sha),
         :ok <- update_marker_head(environment.run_dir, candidate_sha) do
      {:ok, accepted}
    else
      nil -> {:error, :ownership_source_not_found}
      false -> {:error, :candidate_revision_unchanged}
      {:ok, false} -> {:error, :dirty_worktree}
      {:drift, reason} -> {:error, {:ownership_drift, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Removes one clean, owned worktree while retaining the run directory and artifacts."
  def cleanup(%Environment{} = environment) do
    with {:ok, %{clean?: true}} <- inspect(environment),
         :ok <- no_running_processes?(environment),
         {:ok, artifacts} <- retained_artifacts(environment.run_dir),
         {:ok, _started} <- cleanup_started(environment, artifacts),
         %Run{} = run <- Repo.get(Run, environment.run_id),
         %Task{} = task <- Repo.get(Task, run.task_id),
         %Board{} = board <- Repo.get(Board, task.board_id),
         %Project{} = project <- Repo.get(Project, board.project_id),
         {:ok, repo} <- canonical_directory(project.repo_path),
         {:ok, _output} <- git(repo, ["worktree", "remove", environment.worktree_path]),
         {:ok, {_event, stopped}} <- cleanup_completed(environment, artifacts) do
      {:ok, %{environment: stopped, retained_artifacts: artifacts}}
    else
      {:ok, %{clean?: false}} -> {:error, :dirty_worktree}
      nil -> {:error, :ownership_source_not_found}
      {:drift, reason} -> {:error, {:ownership_drift, reason}}
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

  defp no_running_processes?(environment) do
    if Repo.exists?(
         from(process in ProcessRecord,
           where: process.environment_id == ^environment.id and process.state == "running"
         )
       ),
       do: {:error, :running_processes},
       else: :ok
  end

  defp retained_artifacts(run_dir) do
    root = Path.join(run_dir, "artifacts")

    case File.lstat(root) do
      {:ok, %{type: :directory}} -> artifact_entries(root, root)
      {:error, :enoent} -> {:ok, []}
      {:ok, _stat} -> {:error, :invalid_artifacts_directory}
      {:error, reason} -> {:error, {:artifact_inspection_failed, reason}}
    end
  end

  defp artifact_entries(directory, root) do
    case File.ls(directory) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.reduce_while(
          {:ok, []},
          &collect_artifact(&1, &2, directory, root)
        )

      {:error, reason} ->
        {:error, {:artifact_inspection_failed, reason}}
    end
  end

  defp collect_artifact(name, {:ok, entries}, directory, root) do
    case artifact_entry(Path.join(directory, name), root) do
      {:ok, found} -> {:cont, {:ok, entries ++ found}}
      {:error, reason} -> {:halt, {:error, reason}}
    end
  end

  defp artifact_entry(path, root) do
    case File.lstat(path) do
      {:ok, %{type: :directory}} ->
        artifact_entries(path, root)

      {:ok, %{type: type, size: size}} ->
        {:ok,
         [%{"path" => Path.relative_to(path, root), "type" => to_string(type), "bytes" => size}]}

      {:error, reason} ->
        {:error, {:artifact_inspection_failed, reason}}
    end
  end

  defp cleanup_started(environment, artifacts) do
    EventStore.append(environment.run_id, %{
      event_type: "environment.cleanup_started",
      public_summary: "Owned worktree cleanup started",
      payload: %{"environment_id" => environment.id, "retained_artifacts" => artifacts}
    })
  end

  defp accept_candidate(environment, candidate_sha) do
    projection = fn repo, _sequence ->
      repo.update(Environment.candidate_changeset(environment, %{head_sha: candidate_sha}))
    end

    EventStore.append(
      environment.run_id,
      %{
        event_type: "git.candidate_recorded",
        public_summary: "Candidate revision recorded after agent development",
        payload: %{"environment_id" => environment.id, "head_sha" => candidate_sha}
      },
      projection
    )
  end

  defp update_marker_head(run_dir, candidate_sha) do
    path = Path.join(run_dir, "run.json")
    temporary = path <> ".candidate.tmp"

    with {:ok, contents} <- File.read(path),
         {:ok, marker} <- Jason.decode(contents),
         :ok <-
           File.write(
             temporary,
             Jason.encode_to_iodata!(Map.put(marker, "head_sha", candidate_sha))
           ),
         :ok <- File.chmod(temporary, 0o600),
         do: File.rename(temporary, path)
  end

  defp candidate_paths(environment, paths) when paths != [] do
    paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, accepted} ->
      case candidate_path(environment.worktree_path, path) do
        {:ok, relative} -> {:cont, {:ok, accepted ++ [relative]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp candidate_paths(_environment, _paths), do: {:error, :candidate_paths_required}

  defp candidate_path(worktree, path) when is_binary(path) do
    expanded = Path.expand(path, worktree)
    relative = Path.relative_to(expanded, Path.expand(worktree))

    with :ok <- relative_candidate?(path, relative),
         {:ok, %{type: type}} <- File.lstat(expanded),
         :ok <- regular_candidate?(type) do
      {:ok, relative}
    else
      {:error, reason}
      when reason in [:candidate_path_must_be_relative, :candidate_path_escape] ->
        {:error, reason}

      {:error, reason} when reason in [:candidate_path_symlink, :candidate_path_not_regular] ->
        {:error, reason}

      {:error, reason} ->
        {:error, {:candidate_path_invalid, reason}}
    end
  end

  defp candidate_path(_worktree, _path), do: {:error, :invalid_candidate_path}

  defp relative_candidate?(path, relative) do
    cond do
      Path.type(path) == :absolute -> {:error, :candidate_path_must_be_relative}
      Path.type(relative) == :absolute -> {:error, :candidate_path_escape}
      relative == ".." or String.starts_with?(relative, "../") -> {:error, :candidate_path_escape}
      true -> :ok
    end
  end

  defp regular_candidate?(:regular), do: :ok
  defp regular_candidate?(:symlink), do: {:error, :candidate_path_symlink}
  defp regular_candidate?(_type), do: {:error, :candidate_path_not_regular}

  defp valid_commit_message?(message) do
    if String.trim(message) == "" or String.contains?(message, <<0>>),
      do: {:error, :invalid_commit_message},
      else: :ok
  end

  defp cleanup_completed(environment, artifacts) do
    projection = fn repo, _sequence ->
      environment
      |> Environment.preview_changeset(%{
        port: nil,
        preview_url: nil,
        ports_json: %{},
        state: "stopped"
      })
      |> repo.update()
    end

    EventStore.append(
      environment.run_id,
      %{
        event_type: "environment.cleanup_completed",
        public_summary: "Owned worktree removed; run artifacts retained",
        payload: %{"environment_id" => environment.id, "retained_artifacts" => artifacts}
      },
      projection
    )
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

  defp inspect_registration_repo(repo, default_branch) do
    case git(repo, ["rev-parse", "--show-toplevel"]) do
      {:ok, root} ->
        if String.trim(root) == repo,
          do: inspect_registration_branch(repo, default_branch),
          else: {:error, :repository_root_mismatch}

      {:error, _reason} ->
        if File.exists?(Path.join(repo, ".git")),
          do: {:error, :not_a_git_repository},
          else: {:ok, %{repo: repo, branch: default_branch, action: :initialize, base_sha: nil}}
    end
  end

  defp inspect_registration_branch(repo, default_branch) do
    case git(repo, ["rev-parse", "--verify", "refs/heads/#{default_branch}^{commit}"]) do
      {:ok, sha} ->
        {:ok,
         %{
           repo: repo,
           branch: default_branch,
           action: :use_existing,
           base_sha: String.trim(sha)
         }}

      {:error, _reason} ->
        if local_branch_exists?(repo),
          do: {:error, :branch_not_found},
          else:
            {:ok, %{repo: repo, branch: default_branch, action: :initial_commit, base_sha: nil}}
    end
  end

  defp local_branch_exists?(repo) do
    case System.cmd(@git, ["-C", repo, "show-ref", "--heads", "--quiet"], stderr_to_stdout: true) do
      {_output, 0} -> true
      {_output, _status} -> false
    end
  end

  defp prepare_registration(%{action: :use_existing, repo: repo, base_sha: sha}),
    do: {:ok, {repo, sha}}

  defp prepare_registration(%{action: :initialize, repo: repo, branch: branch}) do
    with {:ok, _output} <- git(repo, ["init", "-b", branch]),
         do: create_initial_commit(repo, branch)
  end

  defp prepare_registration(%{action: :initial_commit, repo: repo, branch: branch}) do
    with {:ok, _output} <- git(repo, ["symbolic-ref", "HEAD", "refs/heads/#{branch}"]),
         do: create_initial_commit(repo, branch)
  end

  defp create_initial_commit(repo, branch) do
    with {:ok, _output} <- git(repo, ["add", "--all"]),
         {:ok, _output} <-
           git(repo, [
             "-c",
             "user.name=Cuckoding",
             "-c",
             "user.email=cuckoding@localhost",
             "commit",
             "--allow-empty",
             "--no-gpg-sign",
             "--no-verify",
             "-m",
             "Initial commit"
           ]),
         {:ok, sha} <- git(repo, ["rev-parse", "--verify", "refs/heads/#{branch}^{commit}"]) do
      {:ok, {repo, String.trim(sha)}}
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
    with {:ok, ignore_args} <- host_ignore_args(repo) do
      case System.cmd(@git, ["-C", repo] ++ ignore_args ++ args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        {output, status} -> {:error, {:git_failed, status, String.trim(output)}}
      end
    end
  end

  defp host_ignore_args(repo) do
    host_ignore_args(repo, System.get_env("CUCKODING_RUNTIME_HOME"))
  end

  defp host_ignore_args(_repo, nil), do: {:ok, []}

  defp host_ignore_args(repo, home) do
    # Read only the effective ignore path; never import host hooks or credentials.
    case System.cmd(
           @git,
           ["-C", repo, "config", "--null", "--path", "--get", "core.excludesFile"],
           env: [{"HOME", home}],
           stderr_to_stdout: true
         ) do
      {path, 0} ->
        {:ok, ["-c", "core.excludesFile=" <> String.trim_trailing(path, "\0")]}

      {_output, 1} ->
        config_home = System.get_env("XDG_CONFIG_HOME")

        config_home =
          if config_home in [nil, ""], do: Path.join(home, ".config"), else: config_home

        {:ok, ["-c", "core.excludesFile=" <> Path.join(config_home, "git/ignore")]}

      {_output, status} ->
        {:error, {:git_ignore_config_failed, status}}
    end
  end
end
