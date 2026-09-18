defmodule Cuckoding.Execution.VcsHost do
  @moduledoc "Host-side release boundary. Agent processes never receive VCS credentials."

  @callback handoff(struct(), struct(), String.t()) :: {:ok, struct()} | {:error, term()}
end

defmodule Cuckoding.Execution.ReleasePolicy do
  @moduledoc "Validates the human-approval and protected-branch release boundary."

  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.Run
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Approval
  alias Cuckoding.Workflows.Board
  alias Cuckoding.Workflows.Task

  def validate(%Environment{} = environment, %Approval{} = approval) do
    with %Approval{decision: "approved", kind: "release_handoff"} = approved <-
           Repo.get(Approval, approval.id),
         %Run{} = run <- Repo.get(Run, environment.run_id),
         true <- approved.run_id == run.id,
         %Task{} = task <- Repo.get(Task, run.task_id),
         %Board{} = board <- Repo.get(Board, task.board_id),
         %Project{} = project <- Repo.get(Project, board.project_id),
         false <- run.branch in Enum.uniq(["main", "master", project.default_branch]) do
      {:ok, %{approval: approved, run: run, task: task, project: project}}
    else
      %Approval{} -> {:error, :approval_required}
      nil -> {:error, :release_target_not_found}
      false -> {:error, :approval_run_mismatch}
      true -> {:error, :protected_branch}
    end
  end

  def validate(_environment, _approval), do: {:error, :invalid_handoff}
end

defmodule Cuckoding.Execution.LocalBareRemote do
  @moduledoc "Pushes one approved feature branch to an existing local bare Git remote."
  @behaviour Cuckoding.Execution.VcsHost

  alias Cuckoding.Execution.Commands
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.ReleasePolicy
  alias Cuckoding.Workflows.Approval

  @git "/usr/bin/git"

  @impl true
  def handoff(%Environment{} = environment, %Approval{} = approval, idempotency_key)
      when is_binary(idempotency_key) do
    with {:ok, %{approval: approved, run: run}} <- ReleasePolicy.validate(environment, approval),
         {:ok, %{clean?: true, head_sha: head_sha}} <- GitService.inspect(environment),
         {:ok, remote} <- local_origin(environment.worktree_path) do
      Commands.execute_once(
        %{
          idempotency_key: idempotency_key,
          kind: "release.handoff",
          target_type: "run",
          target_id: run.id,
          payload: %{
            "approval_id" => approved.id,
            "branch" => run.branch,
            "head_sha" => head_sha,
            "remote" => remote
          }
        },
        fn _command -> push(environment, run, approved, remote, head_sha) end
      )
    else
      {:ok, %{clean?: false}} -> {:error, :dirty_worktree}
      {:drift, reason} -> {:error, {:ownership_drift, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  def handoff(_environment, _approval, _idempotency_key), do: {:error, :invalid_handoff}

  defp push(environment, run, approval, remote, head_sha) do
    refspec = "refs/heads/#{run.branch}:refs/heads/#{run.branch}"

    case System.cmd(
           @git,
           ["-C", environment.worktree_path, "push", "--porcelain", remote, refspec],
           env: [{"GIT_TERMINAL_PROMPT", "0"}],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> release_event(run, approval, remote, head_sha)
      {output, status} -> {:error, {:git_push_failed, status, String.trim(output)}}
    end
  end

  defp release_event(run, approval, remote, head_sha) do
    case EventStore.append(run.id, %{
           event_type: "release.handoff_completed",
           public_summary: "Approved feature branch pushed to the local bare remote",
           payload: %{
             "approval_id" => approval.id,
             "branch" => run.branch,
             "head_sha" => head_sha,
             "remote" => remote
           }
         }) do
      {:ok, {event, _projection}} ->
        {:ok,
         %{
           "outcome" => "pushed",
           "branch" => run.branch,
           "head_sha" => head_sha,
           "remote" => remote,
           "event_id" => event.id,
           "event_sequence" => event.sequence
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp local_origin(worktree) do
    with {origin, 0} <-
           System.cmd(@git, ["-C", worktree, "remote", "get-url", "origin"],
             stderr_to_stdout: true
           ),
         path = String.trim(origin),
         true <- Path.type(path) == :absolute,
         {:ok, remote} <- canonical_directory(path),
         {"true\n", 0} <-
           System.cmd(@git, ["-C", remote, "rev-parse", "--is-bare-repository"],
             stderr_to_stdout: true
           ) do
      {:ok, remote}
    else
      false -> {:error, :remote_must_be_local}
      {:error, reason} -> {:error, reason}
      {_output, _status} -> {:error, :invalid_local_bare_remote}
    end
  end

  defp canonical_directory(path) do
    case File.stat(path) do
      {:ok, %{type: :directory}} ->
        case System.cmd("/bin/pwd", ["-P"], cd: path, stderr_to_stdout: true) do
          {resolved, 0} -> {:ok, String.trim(resolved)}
          {_output, _status} -> {:error, :remote_path_resolution_failed}
        end

      _other ->
        {:error, :invalid_local_bare_remote}
    end
  end
end

defmodule Cuckoding.Execution.GitHubVcsHost do
  @moduledoc "Pushes an approved candidate and opens a draft GitHub pull request."
  @behaviour Cuckoding.Execution.VcsHost

  alias Cuckoding.Execution.Commands
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.ReleasePolicy
  alias Cuckoding.Projects.ProjectConfigVersion
  alias Cuckoding.Repo
  alias Cuckoding.Security.Redactor
  alias Cuckoding.Security.SecretStore
  alias Cuckoding.Workflows.Approval
  alias Cuckoding.Workflows.GateEvaluator

  @git "/usr/bin/git"
  @api_url "https://api.github.com"
  @repository ~r/\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/

  @impl true
  def handoff(environment, approval, idempotency_key),
    do: handoff(environment, approval, idempotency_key, [])

  def handoff(
        %Environment{} = environment,
        %Approval{} = approval,
        idempotency_key,
        options
      )
      when is_binary(idempotency_key) and is_list(options) do
    with {:ok, context} <- ReleasePolicy.validate(environment, approval),
         {:ok, %{clean?: true, head_sha: head_sha}} <- GitService.inspect(environment),
         {:ok, config} <- config(context.run.policy_snapshot_id),
         {:ok, evidence} <- evidence(environment) do
      execute(environment, context, config, evidence, head_sha, idempotency_key, options)
    else
      {:ok, %{clean?: false}} -> {:error, :dirty_worktree}
      {:drift, reason} -> {:error, {:ownership_drift, reason}}
      {:error, reason} -> {:error, reason}
    end
  end

  def handoff(_environment, _approval, _idempotency_key, _options),
    do: {:error, :invalid_handoff}

  defp execute(environment, context, config, evidence, head_sha, idempotency_key, options) do
    Commands.execute_once(
      %{
        idempotency_key: idempotency_key,
        kind: "release.handoff",
        target_type: "run",
        target_id: context.run.id,
        payload: %{
          "approval_id" => context.approval.id,
          "branch" => context.run.branch,
          "head_sha" => head_sha,
          "repository" => config.repository
        }
      },
      fn _command ->
        release(environment, context, config, evidence, head_sha, options)
      end
    )
  end

  defp release(environment, context, config, evidence, head_sha, options) do
    with {:ok, token} <-
           SecretStore.fetch(config.credential_ref, "github.release_handoff",
             run_id: context.run.id
           ) do
      release_with_token(environment, context, config, evidence, head_sha, token, options)
    end
  end

  defp release_with_token(environment, context, config, evidence, head_sha, token, options) do
    push = Keyword.get(options, :push, &push/4)
    create_pr = Keyword.get(options, :create_pr, &create_pr/3)
    payload = pull_request_payload(context, evidence)

    with {:ok, _push} <- push.(environment, context.run, config.repository, token),
         {:ok, pr} <- create_pr.(config.repository, payload, token),
         {:ok, result} <- release_event(context, config.repository, head_sha, pr) do
      {:ok, result}
    else
      {:error, reason} -> {:error, Redactor.redact(reason, [token])}
    end
  end

  defp config(policy_snapshot_id) do
    with %ProjectConfigVersion{trusted_at: trusted_at, config_json: policy}
         when not is_nil(trusted_at) <-
           Repo.get(ProjectConfigVersion, policy_snapshot_id),
         %{
           "provider" => "github",
           "repository" => repository,
           "credential_ref" => credential_ref
         }
         when is_binary(repository) and is_binary(credential_ref) <-
           get_in(policy, ["vcs"]),
         true <- Regex.match?(@repository, repository),
         true <- String.starts_with?(credential_ref, "keychain:") do
      {:ok, %{repository: repository, credential_ref: credential_ref}}
    else
      nil -> {:error, :policy_snapshot_not_found}
      false -> {:error, :invalid_github_config}
      _other -> {:error, :invalid_github_config}
    end
  end

  defp evidence(environment) do
    path = Path.join([environment.run_dir, "artifacts", "evidence.json"])

    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} when size <= 1_048_576 ->
        with {:ok, contents} <- File.read(path),
             {:ok, bundle} <- Jason.decode(contents),
             do: GateEvaluator.verify(bundle, environment.run_dir)

      _other ->
        {:error, :invalid_evidence_file}
    end
  end

  defp pull_request_payload(context, evidence) do
    %{
      "title" => context.task.title,
      "head" => context.run.branch,
      "base" => context.project.default_branch,
      "draft" => true,
      "body" => pull_request_body(evidence)
    }
  end

  defp pull_request_body(evidence) do
    tests =
      Enum.map_join(evidence["tests"], "\n", fn result ->
        "- `#{result["command"]}`: #{result["status"]} (#{result["passed"]} passed, #{result["failed"]} failed)"
      end)

    artifacts =
      Enum.map_join(evidence["artifacts"], "\n", fn artifact ->
        "- `#{artifact["path"]}` (#{artifact["type"]}, `#{artifact["sha256"]}`)"
      end)

    citations =
      Enum.map_join(evidence["knowledge_citations"], "\n", fn citation ->
        "- `#{citation["path"]}` (`#{citation["sha256"]}`)"
      end)

    """
    ## Evidence

    Candidate: `#{evidence["head_sha"]}` from `#{evidence["base_sha"]}`

    ### Tests

    #{tests}

    ### Artifacts

    #{artifacts}

    ## Knowledge citations

    #{citations}
    """
  end

  defp push(environment, run, repository, token) do
    refspec = "refs/heads/#{run.branch}:refs/heads/#{run.branch}"
    authorization = "AUTHORIZATION: basic " <> Base.encode64("x-access-token:#{token}")

    case System.cmd(
           @git,
           [
             "-C",
             environment.worktree_path,
             "push",
             "--porcelain",
             "https://github.com/#{repository}.git",
             refspec
           ],
           env: [
             {"GIT_TERMINAL_PROMPT", "0"},
             {"GIT_CONFIG_COUNT", "1"},
             {"GIT_CONFIG_KEY_0", "http.https://github.com/.extraheader"},
             {"GIT_CONFIG_VALUE_0", authorization}
           ],
           stderr_to_stdout: true
         ) do
      {_output, 0} -> {:ok, %{"outcome" => "pushed"}}
      {output, status} -> {:error, {:git_push_failed, status, Redactor.redact(output, [token])}}
    end
  end

  defp create_pr(repository, payload, token) do
    url = "#{@api_url}/repos/#{repository}/pulls"

    headers = [
      {~c"accept", ~c"application/vnd.github+json"},
      {~c"authorization", String.to_charlist("Bearer #{token}")},
      {~c"user-agent", ~c"cuckoding"},
      {~c"x-github-api-version", ~c"2022-11-28"}
    ]

    request = {String.to_charlist(url), headers, ~c"application/json", Jason.encode!(payload)}

    case :httpc.request(:post, request, [timeout: 30_000], body_format: :binary) do
      {:ok, {{_version, 201, _reason}, _headers, body}} ->
        with {:ok, %{"html_url" => html_url}} <- Jason.decode(body),
             do: {:ok, %{"url" => html_url}}

      {:ok, {{_version, status, _reason}, _headers, body}} ->
        {:error, {:github_api_failed, status, Redactor.redact(body, [token])}}

      {:error, reason} ->
        {:error, {:github_api_failed, Redactor.redact(reason, [token])}}
    end
  end

  defp release_event(context, repository, head_sha, pr) do
    url = pr["url"]

    case EventStore.append(context.run.id, %{
           event_type: "release.handoff_completed",
           public_summary: "Approved feature branch pushed and draft pull request created",
           payload: %{
             "approval_id" => context.approval.id,
             "branch" => context.run.branch,
             "head_sha" => head_sha,
             "repository" => repository,
             "draft_pr_url" => url
           }
         }) do
      {:ok, {event, _projection}} ->
        {:ok,
         %{
           "outcome" => "draft_pr_created",
           "branch" => context.run.branch,
           "head_sha" => head_sha,
           "repository" => repository,
           "draft_pr_url" => url,
           "event_id" => event.id,
           "event_sequence" => event.sequence
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
