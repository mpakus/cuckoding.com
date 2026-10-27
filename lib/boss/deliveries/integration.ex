defmodule Boss.Deliveries.Integration do
  @moduledoc "Publishes an exact reviewed commit into a reserved, retained target worktree."
  alias Boss.Agents.Workspace
  alias Boss.Checks.Candidate

  @keys ~w(base_branch base_commit candidate candidate_commit delivery_id git_common_dir path project_id repo_path)

  def plan(project, delivery_id, candidate, sha, expected_base, opts \\ []) do
    with true <- sha?(sha) and sha?(expected_base),
         {:ok, workspace} <- Workspace.plan(project, delivery_id, opts),
         :ok <- candidate_identity(candidate, workspace),
         :ok <- Candidate.verify(candidate, sha, opts),
         {:ok, _} <-
           git(workspace.repo_path, ["merge-base", "--is-ancestor", expected_base, sha], opts) do
      intent = %{
        "delivery_id" => delivery_id,
        "project_id" => workspace.project_id,
        "repo_path" => workspace.repo_path,
        "git_common_dir" => workspace.git_common_dir,
        "base_branch" => workspace.base_branch,
        "base_commit" => expected_base,
        "candidate_commit" => sha,
        "candidate" => candidate,
        "path" => integration_path(workspace)
      }

      with :ok <- paths(intent),
           :ok <- target(intent, expected_base, opts),
           do: {:ok, intent}
    else
      {:error, {:git_exit, _}} -> {:error, :invalid_integration}
      {:error, _} = error -> error
      _ -> {:error, :invalid_integration}
    end
  end

  def prepare(intent, opts \\ []) do
    with :ok <- valid_intent(intent, opts),
         :ok <- Candidate.verify(intent["candidate"], intent["candidate_commit"], opts),
         :ok <- target(intent, intent["base_commit"], opts),
         :ok <- absent(intent["path"]),
         :ok <- available_target(intent, nil, opts),
         :ok <- parents(Path.dirname(intent["path"])),
         {:ok, _} <-
           git(
             intent["repo_path"],
             ["worktree", "add", "--", intent["path"], intent["base_branch"]],
             opts
           ),
         :ok <- reserved(intent, intent["base_commit"], opts) do
      :ok
    else
      {:error, {:git_exit, _}} -> {:error, :integration_failed}
      {:error, _} = error -> error
      _ -> {:error, :invalid_integration}
    end
  end

  # The caller must persist publication intent before entering this function.
  # Once CAS begins, an unknown process outcome can already mean publication.
  def publish(intent, opts \\ []) do
    with :ok <- valid_intent(intent, opts),
         :ok <- Candidate.verify(intent["candidate"], intent["candidate_commit"], opts),
         :ok <- reserved(intent, intent["base_commit"], opts),
         :ok <- target(intent, intent["base_commit"], opts),
         :ok <- Keyword.get(opts, :authorize, fn -> :ok end).() do
      case git(
             intent["path"],
             [
               "update-ref",
               "--no-deref",
               target_ref(intent),
               intent["candidate_commit"],
               intent["base_commit"]
             ],
             opts
           ) do
        {:ok, _} -> populate(intent, opts)
        {:error, {:git_exit, _}} -> {:error, :target_changed}
        _ -> {:error, :publication_unknown}
      end
    end
  end

  def verify_published(intent, opts \\ []) do
    with :ok <- valid_intent(intent, opts),
         :ok <- Candidate.verify(intent["candidate"], intent["candidate_commit"], opts),
         :ok <- reserved(intent, intent["candidate_commit"], opts, :published),
         do: target(intent, intent["candidate_commit"], opts)
  end

  @doc "Releases the target branch while retaining the verified publication checkout and files."
  def release(intent, opts \\ []) do
    with :ok <- verify_published(intent, opts),
         {:ok, _} <-
           git(intent["path"], ["switch", "--detach", intent["candidate_commit"]], opts),
         {:error, {:git_exit, 1}} <-
           git(intent["path"], ["symbolic-ref", "--no-recurse", "-q", "HEAD"], opts),
         :ok <- verify_published(intent, opts) do
      :ok
    else
      {:error, {:git_exit, _}} -> {:error, :integration_changed}
      {:error, _} = error -> error
      _ -> {:error, :integration_changed}
    end
  end

  defp populate(intent, opts) do
    with :ok <- target(intent, intent["candidate_commit"], opts),
         {:ok, _} <-
           git(intent["path"], ["read-tree", "--reset", "-u", intent["candidate_commit"]], opts),
         :ok <- verify_published(intent, opts) do
      {:ok, intent["candidate_commit"]}
    else
      _ -> {:error, :publication_unknown}
    end
  end

  defp valid_intent(intent, opts) when is_map(intent) do
    with true <- Enum.sort(Map.keys(intent)) == @keys,
         id when is_binary(id) <- intent["project_id"],
         true <- Regex.match?(~r/\A[1-9][0-9]*\z/, id),
         true <- sha?(intent["base_commit"]) and sha?(intent["candidate_commit"]),
         {:ok, workspace} <-
           Workspace.plan(
             %{
               id: String.to_integer(id),
               root_path: intent["repo_path"],
               git_common_dir: intent["git_common_dir"],
               base_branch: intent["base_branch"]
             },
             intent["delivery_id"],
             opts
           ),
         true <- intent["path"] == integration_path(workspace),
         :ok <- paths(intent),
         :ok <- candidate_identity(intent["candidate"], workspace),
         {:ok, _} <-
           git(
             intent["repo_path"],
             ["merge-base", "--is-ancestor", intent["base_commit"], intent["candidate_commit"]],
             opts
           ) do
      :ok
    else
      {:error, :cleanup_unknown} = error -> error
      {:error, :cancelled} = error -> error
      {:error, :unsupported_platform} = error -> error
      _ -> {:error, :invalid_integration}
    end
  end

  defp valid_intent(_, _), do: {:error, :invalid_integration}

  defp integration_path(workspace),
    do:
      Path.join([
        workspace.path |> Path.dirname() |> Path.dirname(),
        "integrations",
        workspace.run_id
      ])

  defp candidate_identity(%{"run_workspace" => run}, workspace) when is_map(run) do
    if Enum.all?(~w(project_id repo_path git_common_dir base_branch)a, fn key ->
         run[Atom.to_string(key)] == Map.fetch!(workspace, key)
       end),
       do: :ok,
       else: {:error, :invalid_integration}
  end

  defp candidate_identity(_, _), do: {:error, :invalid_integration}

  defp paths(intent) do
    Enum.reduce_while(~w(repo_path git_common_dir path), :ok, fn key, :ok ->
      case safe_directories(intent[key]) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp target(intent, expected, opts) do
    path = Path.join(intent["git_common_dir"], target_ref(intent))

    with :ok <- safe_directories(Path.dirname(path)),
         :ok <- regular_or_absent(path),
         {:error, {:git_exit, 1}} <-
           git(
             intent["repo_path"],
             ["symbolic-ref", "--no-recurse", "-q", target_ref(intent)],
             opts
           ),
         {:ok, ^expected} <-
           git(intent["repo_path"], ["rev-parse", "--verify", target_ref(intent)], opts) do
      :ok
    else
      {:error, :cleanup_unknown} = error -> error
      {:error, :cancelled} = error -> error
      {:error, :unsupported_platform} = error -> error
      _ -> {:error, :target_changed}
    end
  end

  defp reserved(intent, expected, opts, mode \\ :attached) do
    path = intent["path"]
    common = intent["git_common_dir"]

    with :ok <- paths(intent),
         :ok <- regular(Path.join(path, ".git")),
         {:ok, ^path} <- git(path, ["rev-parse", "--show-toplevel"], opts),
         {:ok, ^common} <-
           git(path, ["rev-parse", "--path-format=absolute", "--git-common-dir"], opts),
         {:ok, directory} <- git(path, ["rev-parse", "--absolute-git-dir"], opts),
         true <- Path.dirname(directory) == Path.join(common, "worktrees"),
         :ok <- safe_directories(directory),
         :ok <- regular(Path.join(directory, "gitdir")),
         {:ok, backlink} <- File.read(Path.join(directory, "gitdir")),
         true <- String.trim_trailing(backlink, "\n") == Path.join(path, ".git"),
         :ok <- checkout_head(intent, mode, opts),
         :ok <- target(intent, expected, opts),
         :ok <- Candidate.verify_tree(path, expected, opts) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :integration_changed}
    end
  end

  defp checkout_head(intent, mode, opts) do
    ref = target_ref(intent)

    case git(intent["path"], ["symbolic-ref", "--no-recurse", "-q", "HEAD"], opts) do
      {:ok, ^ref} -> available_target(intent, intent["path"], opts)
      {:error, {:git_exit, 1}} when mode == :published -> :ok
      {:error, :cleanup_unknown} = error -> error
      {:error, :cancelled} = error -> error
      {:error, :unsupported_platform} = error -> error
      _ -> {:error, :integration_changed}
    end
  end

  defp available_target(intent, allowed, opts) do
    with {:ok, output} <-
           git(intent["repo_path"], ["worktree", "list", "--porcelain", "-z"], opts) do
      occupied =
        output
        |> String.split(<<0, 0>>, trim: true)
        |> Enum.filter(fn entry ->
          ("branch " <> target_ref(intent)) in String.split(entry, <<0>>)
        end)

      if Enum.all?(occupied, fn entry ->
           allowed != nil and ("worktree " <> allowed) in String.split(entry, <<0>>)
         end),
         do: :ok,
         else: {:error, :target_checked_out}
    end
  end

  defp target_ref(intent), do: "refs/heads/" <> intent["base_branch"]

  defp absent(path) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      _ -> {:error, :integration_exists}
    end
  end

  defp regular_or_absent(path) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      _ -> regular(path)
    end
  end

  defp regular(path) do
    case File.lstat(path) do
      {:ok, %{type: :regular, size: size}} when size < 4096 -> :ok
      _ -> {:error, :integration_path}
    end
  end

  defp safe_directories(path) when is_binary(path) do
    if Path.type(path) == :absolute and Path.expand(path) == path do
      [anchor | parts] = Path.split(path)

      Enum.reduce_while(parts, anchor, fn part, parent ->
        next = Path.join(parent, part)

        case File.lstat(next) do
          {:ok, %{type: :directory}} -> {:cont, next}
          {:error, :enoent} -> {:halt, :ok}
          _ -> {:halt, {:error, :integration_path}}
        end
      end)
      |> case do
        {:error, _} = error -> error
        _ -> :ok
      end
    else
      {:error, :integration_path}
    end
  end

  defp safe_directories(_), do: {:error, :integration_path}

  defp parents(path) do
    [anchor | parts] = Path.split(path)

    Enum.reduce_while(parts, {:ok, anchor}, fn part, {:ok, parent} ->
      next = Path.join(parent, part)

      result =
        case File.lstat(next) do
          {:ok, %{type: :directory}} -> :ok
          {:error, :enoent} -> with :ok <- File.mkdir(next), do: File.chmod(next, 0o700)
          _ -> {:error, :integration_path}
        end

      case result do
        :ok -> {:cont, {:ok, next}}
        _ -> {:halt, {:error, :integration_path}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp git(path, args, opts), do: Workspace.git(path, args, opts)

  defp sha?(value),
    do: is_binary(value) and Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/, value)
end
