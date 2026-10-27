defmodule Boss.Checks.Candidate do
  @moduledoc "Captures retained run changes without moving their branch, HEAD or index."
  alias Boss.Agents.Workspace
  @intent_keys ~w(check_id path ref run_workspace)
  @run_keys ~w(project_id run_id repo_path git_common_dir base_branch base_commit path branch)

  def plan(workspace, id, opts \\ []) do
    with {:ok, ^id} <- Ecto.UUID.cast(id),
         {:ok, _} <- Workspace.inspect(workspace, opts) do
      workspace = Map.new(workspace, fn {k, v} -> {to_string(k), v} end)
      directory = workspace["path"] |> Path.dirname() |> Path.dirname()

      {:ok,
       %{
         "run_workspace" => Map.take(workspace, @run_keys),
         "check_id" => id,
         "path" => Path.join([directory, "checks", id]),
         "ref" => "refs/boss/checks/#{id}"
       }}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_candidate}
    end
  end

  def prepare(intent, opts \\ []) do
    with :ok <- valid_intent(intent, opts),
         source = intent["run_workspace"]["path"],
         :ok <- supported(source, opts),
         :ok <- absent(intent["path"]),
         :ok <- unused_ref(source, intent["ref"], opts),
         :ok <- parents(Path.dirname(intent["path"])),
         {:ok, sha} <- snapshot(intent, opts),
         {:ok, _} <-
           git(source, ["update-ref", "--no-deref", intent["ref"], sha, zeros(sha)], opts),
         {:ok, _} <- git(source, ["worktree", "add", "--detach", "--", intent["path"], sha], opts),
         :ok <- verify(intent, sha, opts) do
      {:ok, %{candidate_commit: sha, path: intent["path"]}}
    else
      {:error, _} = error -> error
      _ -> {:error, :candidate_failed}
    end
  end

  def verify(intent, sha, opts \\ []) do
    with true <- sha?(sha),
         :ok <- valid_intent(intent, opts),
         :ok <- linked_workspace(intent, opts),
         path = intent["path"],
         {:ok, ^sha} <- git(path, ["rev-parse", "--verify", intent["ref"]], opts),
         {:error, {:git_exit, 1}} <- git(path, ["symbolic-ref", "-q", "HEAD"], opts),
         :ok <- verify_tree(path, sha, opts) do
      :ok
    else
      {:error, :cleanup_unknown} = error -> error
      {:error, :cancelled} = error -> error
      {:error, :unsupported_platform} = error -> error
      _ -> {:error, :candidate_changed}
    end
  end

  @doc "Verifies exact HEAD and a fresh tree, without trusting the worktree's index flags."
  def verify_tree(path, sha, opts \\ []) do
    with true <- is_binary(path) and Path.type(path) == :absolute and Path.expand(path) == path,
         true <- sha?(sha),
         :ok <- safe_directories(path),
         :ok <- supported(path, opts),
         {:ok, ^path} <- git(path, ["rev-parse", "--show-toplevel"], opts),
         {:ok, ^sha} <- git(path, ["rev-parse", "--verify", "HEAD"], opts),
         {:ok, ""} <- git(path, ["status", "--porcelain=v1", "-z", "--untracked-files=all"], opts),
         {:ok, tree} <- git(path, ["rev-parse", "#{sha}^{tree}"], opts),
         {:ok, ^tree} <-
           private_indexes(%{"path" => path}, fn indexes ->
             capture(path, sha, hd(indexes), opts)
           end),
         {:ok, ^sha} <- git(path, ["rev-parse", "--verify", "HEAD"], opts) do
      :ok
    else
      {:error, :cleanup_unknown} = error -> error
      {:error, :cancelled} = error -> error
      {:error, :unsupported_platform} = error -> error
      _ -> {:error, :candidate_changed}
    end
  end

  defp snapshot(intent, opts) do
    source = intent["run_workspace"]["path"]

    private_indexes(intent, fn [first, second] ->
      with {:ok, head} <- git(source, ["rev-parse", "--verify", "HEAD"], opts),
           {:ok, tree} <- capture(source, head, first, opts),
           {:ok, ^tree} <- capture(source, head, second, opts),
           {:ok, ^head} <- git(source, ["rev-parse", "--verify", "HEAD"], opts),
           {:ok, sha} <-
             git(
               source,
               [
                 "-c",
                 "user.name=BOSS",
                 "-c",
                 "user.email=boss@localhost",
                 "-c",
                 "commit.gpgSign=false",
                 "commit-tree",
                 tree,
                 "-p",
                 head,
                 "-m",
                 "BOSS check #{intent["check_id"]}"
               ],
               opts
             ),
           true <- sha?(sha) do
        {:ok, sha}
      else
        {:error, _} = error -> error
        _ -> {:error, :source_changed}
      end
    end)
  end

  defp capture(path, head, index, opts) do
    opts = Keyword.put(opts, :git_env, [{"GIT_INDEX_FILE", index}])

    with {:ok, _} <- git(path, ["read-tree", head], opts),
         {:ok, _} <- git(path, ["add", "--all", "--", "."], opts),
         {:ok, entries} <- git(path, ["ls-files", "--stage", "-z"], opts),
         false <-
           Enum.any?(
             :binary.split(entries, <<0>>, [:global]),
             &String.starts_with?(&1, "160000 ")
           ),
         {:ok, tree} <- git(path, ["write-tree"], opts) do
      {:ok, tree}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_submodule}
    end
  end

  defp valid_intent(intent, opts) when is_map(intent) do
    with true <- Enum.sort(Map.keys(intent)) == @intent_keys,
         {:ok, ^intent} <- plan(intent["run_workspace"], intent["check_id"], opts),
         :ok <- safe_directories(Path.dirname(intent["path"])) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_candidate}
    end
  end

  defp valid_intent(_, _), do: {:error, :invalid_candidate}

  defp linked_workspace(intent, opts) do
    path = intent["path"]
    common = intent["run_workspace"]["git_common_dir"]

    with :ok <- safe_directories(path),
         {:ok, %{type: :regular, size: size}} when size < 4096 <-
           File.lstat(Path.join(path, ".git")),
         {:ok, ^path} <- git(path, ["rev-parse", "--show-toplevel"], opts),
         {:ok, ^common} <-
           git(path, ["rev-parse", "--path-format=absolute", "--git-common-dir"], opts),
         {:ok, directory} <- git(path, ["rev-parse", "--absolute-git-dir"], opts),
         true <- Path.dirname(directory) == Path.join(common, "worktrees"),
         :ok <- safe_directories(directory),
         {:ok, %{type: :regular, size: size}} when size < 4096 <-
           File.lstat(Path.join(directory, "gitdir")),
         {:ok, backlink} <- File.read(Path.join(directory, "gitdir")),
         true <- String.trim_trailing(backlink, "\n") == Path.join(path, ".git") do
      :ok
    else
      {:error, :cleanup_unknown} = error -> error
      {:error, :cancelled} = error -> error
      {:error, :unsupported_platform} = error -> error
      _ -> {:error, :candidate_changed}
    end
  end

  defp supported(path, opts) do
    with :ok <- Workspace.safe_config(path, opts) do
      case git(path, ["config", "--bool", "--get", "core.sparseCheckout"], opts) do
        {:error, {:git_exit, 1}} -> :ok
        {:ok, "false"} -> :ok
        {:ok, _} -> {:error, :unsupported_sparse_checkout}
        {:error, _} = error -> error
      end
    end
  end

  defp private_indexes(intent, fun) do
    directory = intent["path"] <> ".snapshot-" <> Ecto.UUID.generate()

    with :ok <- File.mkdir(directory),
         :ok <- File.chmod(directory, 0o700) do
      indexes = Enum.map(["first", "second"], &Path.join(directory, &1))
      result = fun.(indexes)

      unless result == {:error, :cleanup_unknown} do
        Enum.each(indexes, fn index ->
          File.rm(index)
          File.rm(index <> ".lock")
        end)

        File.rmdir(directory)
      end

      result
    else
      _ -> {:error, :candidate_unwritable}
    end
  end

  defp unused_ref(path, ref, opts) do
    case git(path, ["show-ref", "--verify", "--quiet", ref], opts) do
      {:error, {:git_exit, 1}} -> :ok
      {:ok, _} -> {:error, :candidate_exists}
      error -> error
    end
  end

  defp absent(path) do
    case File.lstat(path) do
      {:error, :enoent} -> :ok
      _ -> {:error, :candidate_exists}
    end
  end

  defp safe_directories(path) do
    [anchor | parts] = Path.split(path)

    Enum.reduce_while(parts, anchor, fn part, parent ->
      next = Path.join(parent, part)

      case File.lstat(next) do
        {:ok, %{type: :directory}} -> {:cont, next}
        {:error, :enoent} -> {:halt, :ok}
        _ -> {:halt, {:error, :candidate_path}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      _ -> :ok
    end
  end

  defp parents(path) do
    [anchor | parts] = Path.split(path)

    Enum.reduce_while(parts, {:ok, anchor}, fn part, {:ok, parent} ->
      next = Path.join(parent, part)

      case File.lstat(next) do
        {:ok, %{type: :directory}} ->
          {:cont, {:ok, next}}

        {:error, :enoent} ->
          case File.mkdir(next) do
            :ok ->
              File.chmod(next, 0o700)
              {:cont, {:ok, next}}

            _ ->
              {:halt, {:error, :candidate_unwritable}}
          end

        _ ->
          {:halt, {:error, :candidate_path}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp git(path, args, opts),
    do:
      Workspace.git(
        path,
        ["-c", "core.filemode=true", "-c", "core.untrackedCache=false" | args],
        opts
      )

  defp sha?(value),
    do: is_binary(value) and Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/, value)

  defp zeros(sha), do: String.duplicate("0", byte_size(sha))
end
