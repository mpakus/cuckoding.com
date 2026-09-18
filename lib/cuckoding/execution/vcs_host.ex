defmodule Cuckoding.Execution.VcsHost do
  @moduledoc "Host-side release boundary. Agent processes never receive VCS credentials."

  @callback handoff(struct(), struct(), String.t()) :: {:ok, struct()} | {:error, term()}
end

defmodule Cuckoding.Execution.LocalBareRemote do
  @moduledoc "Pushes one approved feature branch to an existing local bare Git remote."
  @behaviour Cuckoding.Execution.VcsHost

  alias Cuckoding.Execution.Commands
  alias Cuckoding.Execution.Environment
  alias Cuckoding.Execution.EventStore
  alias Cuckoding.Execution.GitService
  alias Cuckoding.Execution.Run
  alias Cuckoding.Repo
  alias Cuckoding.Workflows.Approval

  @git "/usr/bin/git"

  @impl true
  def handoff(%Environment{} = environment, %Approval{} = approval, idempotency_key)
      when is_binary(idempotency_key) do
    with %Approval{decision: "approved"} = approved <- Repo.get(Approval, approval.id),
         %Run{} = run <- Repo.get(Run, environment.run_id),
         true <- approved.run_id == run.id,
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
      %Approval{} -> {:error, :approval_required}
      nil -> {:error, :release_target_not_found}
      false -> {:error, :approval_run_mismatch}
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
