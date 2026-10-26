defmodule Boss.Agents.Workspace do
  @moduledoc "Plans and retains isolated run worktrees; never merges, resets or removes them."
  import Kernel, except: [inspect: 1, inspect: 2]

  @fields ~w(project_id run_id repo_path git_common_dir base_branch base_commit path branch)a
  @git_config [
    "--no-pager",
    "-c",
    "core.hooksPath=/dev/null",
    "-c",
    "core.fsmonitor=false",
    "-c",
    "submodule.recurse=false",
    "-c",
    "protocol.allow=never"
  ]
  @output_limit 1_048_576

  def plan(project, run_id, opts \\ []) do
    with true <- is_map(project) and safe_id?(run_id),
         id when is_integer(id) and id > 0 <- Map.get(project, :id),
         repo when is_binary(repo) <- Map.get(project, :root_path),
         common when is_binary(common) <- Map.get(project, :git_common_dir),
         branch when is_binary(branch) <- Map.get(project, :base_branch),
         true <- valid_path?(repo) and valid_path?(common) and valid_text?(branch),
         :ok <- repository(repo, common, opts),
         :ok <- safe_config(repo, opts),
         {:ok, _} <- git(repo, ["check-ref-format", "refs/heads/#{branch}"], opts),
         {:ok, base} <-
           git(
             repo,
             ["rev-parse", "--verify", "--end-of-options", "refs/heads/#{branch}^{commit}"],
             opts
           ),
         true <- full_sha?(base) do
      intent = %{
        project_id: Integer.to_string(id),
        run_id: run_id,
        repo_path: repo,
        git_common_dir: common,
        base_branch: branch,
        base_commit: base,
        path: workspace_path(Integer.to_string(id), run_id, opts),
        branch: "codex/boss-run-#{run_id}"
      }

      with :ok <- location(intent, opts), do: {:ok, intent}
    else
      {:error, {:git_exit, _}} -> {:error, :invalid_repository}
      {:error, _} = error -> error
      _ -> {:error, :invalid_project}
    end
  end

  def prepare(value, opts \\ []) do
    with {:ok, intent} <- validate(value, opts),
         :ok <- safe_config(intent.repo_path, opts) do
      case File.lstat(intent.path) do
        {:ok, %{type: :directory}} -> inspect_valid(intent, opts)
        {:error, :enoent} -> create(intent, opts)
        _ -> {:error, :workspace_conflict}
      end
    end
  end

  def inspect(value, opts \\ []) do
    with {:ok, intent} <- validate(value, opts) do
      case File.lstat(intent.path) do
        {:ok, %{type: :directory}} -> inspect_valid(intent, opts)
        {:error, :enoent} -> {:error, :workspace_missing}
        _ -> {:error, :workspace_conflict}
      end
    end
  end

  defp validate(value, opts) do
    with {:ok, intent} <- normalize(value),
         true <- safe_id?(intent.run_id) and Regex.match?(~r/\A[1-9][0-9]*\z/, intent.project_id),
         true <- valid_path?(intent.repo_path) and valid_path?(intent.git_common_dir),
         true <- valid_text?(intent.base_branch) and full_sha?(intent.base_commit),
         :ok <- location(intent, opts),
         :ok <- repository(intent.repo_path, intent.git_common_dir, opts),
         {:ok, commit} <-
           git(
             intent.repo_path,
             ["rev-parse", "--verify", "#{intent.base_commit}^{commit}"],
             opts
           ),
         true <- commit == intent.base_commit do
      {:ok, intent}
    else
      {:error, {:git_exit, _}} -> {:error, :invalid_intent}
      {:error, _} = error -> error
      _ -> {:error, :invalid_intent}
    end
  end

  defp normalize(value) when is_map(value) and map_size(value) == length(@fields) do
    intent =
      Map.new(@fields, fn key ->
        {key, Map.get(value, key, Map.get(value, Atom.to_string(key)))}
      end)

    if Enum.all?(intent, fn {_, val} -> is_binary(val) end),
      do: {:ok, intent},
      else: {:error, :invalid_intent}
  end

  defp normalize(_), do: {:error, :invalid_intent}

  defp location(intent, opts) do
    path = workspace_path(intent.project_id, intent.run_id, opts)

    if intent.path == path and intent.branch == "codex/boss-run-#{intent.run_id}" and
         valid_path?(path) and not inside?(path, intent.repo_path) and safe_components?(path),
       do: :ok,
       else: {:error, :invalid_workspace_path}
  end

  defp workspace_path(project_id, run_id, opts) do
    data = Keyword.get_lazy(opts, :data_dir, fn -> Application.fetch_env!(:boss, :data_dir) end)

    case physical_root(Path.expand(data), 40) do
      {:ok, physical} -> Path.join([physical, "projects", project_id, "worktrees", run_id])
      _ -> nil
    end
  end

  # Resolve the trusted data-root alias; generated descendants must remain symlink-free.
  defp physical_root(path, budget) when budget >= 0 do
    [anchor | parts] = Path.split(path)
    physical_parts(anchor, parts, budget)
  end

  defp physical_root(_, _), do: {:error, :invalid_workspace_path}
  defp physical_parts(parent, [], _), do: {:ok, parent}

  defp physical_parts(parent, [part | rest], budget) do
    next = Path.join(parent, part)

    case File.lstat(next) do
      {:ok, %{type: :directory}} ->
        physical_parts(next, rest, budget)

      {:ok, %{type: :symlink}} ->
        with {:ok, target} <- File.read_link(next) do
          physical_root(Path.join([Path.expand(target, parent) | rest]), budget - 1)
        end

      {:error, :enoent} ->
        {:ok, Path.join([next | rest])}

      _ ->
        {:error, :invalid_workspace_path}
    end
  end

  defp repository(repo, common, opts) do
    with {:ok, ^repo} <- git(repo, ["rev-parse", "--show-toplevel"], opts),
         {:ok, ^common} <-
           git(repo, ["rev-parse", "--path-format=absolute", "--git-common-dir"], opts) do
      :ok
    else
      {:error, {:git_exit, _}} -> {:error, :repository_mismatch}
      {:error, _} = error -> error
      _ -> {:error, :repository_mismatch}
    end
  end

  @doc false
  def safe_config(repo, opts \\ []) do
    with :ok <- conditional_config(repo, opts) do
      filter_drivers(repo, opts)
    end
  end

  # A conditional include can activate a filter only after the new branch is checked out.
  defp conditional_config(repo, opts) do
    case git(repo, ["config", "--get-regexp", "^includeif\\..*\\.path$"], opts) do
      {:error, {:git_exit, 1}} -> :ok
      {:ok, _} -> {:error, :unsupported_git_config}
      {:error, {:git_exit, _}} -> {:error, :git_failed}
      error -> error
    end
  end

  defp filter_drivers(repo, opts) do
    case git(repo, ["config", "--get-regexp", "^filter\\..*\\.(clean|smudge|process)$"], opts) do
      {:error, {:git_exit, 1}} -> :ok
      {:ok, _} -> {:error, :unsupported_git_filter}
      {:error, {:git_exit, _}} -> {:error, :git_failed}
      error -> error
    end
  end

  defp create(intent, opts) do
    case git(
           intent.repo_path,
           ["show-ref", "--verify", "--quiet", "refs/heads/#{intent.branch}"],
           opts
         ) do
      {:error, {:git_exit, 1}} ->
        with :ok <- make_parents(Path.dirname(intent.path)),
             {:ok, _} <-
               git(
                 intent.repo_path,
                 ["worktree", "add", "-b", intent.branch, "--", intent.path, intent.base_commit],
                 opts
               ) do
          inspect_valid(intent, opts)
        else
          {:error, {:git_exit, _}} -> {:error, :workspace_conflict}
          {:error, _} = error -> error
        end

      {:ok, _} ->
        {:error, :workspace_conflict}

      {:error, {:git_exit, _}} ->
        {:error, :git_failed}

      error ->
        error
    end
  end

  defp inspect_valid(intent, opts) do
    with :ok <- repository(intent.path, intent.git_common_dir, opts),
         {:ok, branch} <- git(intent.path, ["symbolic-ref", "HEAD"], opts),
         true <- branch == "refs/heads/#{intent.branch}",
         {:ok, head} <- git(intent.path, ["rev-parse", "--verify", "HEAD"], opts),
         true <- full_sha?(head),
         {:ok, _} <-
           git(intent.path, ["merge-base", "--is-ancestor", intent.base_commit, head], opts) do
      {:ok,
       %{
         path: intent.path,
         branch: intent.branch,
         base_commit: intent.base_commit,
         head_commit: head
       }}
    else
      {:error, {:git_exit, _}} -> {:error, :workspace_mismatch}
      {:error, _} = error -> error
      _ -> {:error, :workspace_mismatch}
    end
  end

  defp safe_components?(path) do
    [anchor | parts] = Path.split(path)

    Enum.reduce_while(parts, anchor, fn part, parent ->
      next = Path.join(parent, part)

      case File.lstat(next) do
        {:ok, %{type: :directory}} -> {:cont, next}
        {:error, :enoent} -> {:halt, true}
        _ -> {:halt, false}
      end
    end) != false
  end

  defp make_parents(path) do
    [anchor | parts] = Path.split(path)

    Enum.reduce_while(parts, {:ok, anchor}, fn part, {:ok, parent} ->
      next = Path.join(parent, part)

      result =
        case File.lstat(next) do
          {:ok, %{type: :directory}} ->
            :ok

          {:error, :enoent} ->
            case File.mkdir(next) do
              :ok -> File.chmod(next, 0o700)
              _ -> {:error, :workspace_unwritable}
            end

          _ ->
            {:error, :invalid_workspace_path}
        end

      case result do
        :ok -> {:cont, {:ok, next}}
        _ -> {:halt, {:error, :workspace_unwritable}}
      end
    end)
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp inside?(path, root), do: path == root or String.starts_with?(path, root <> "/")

  defp valid_path?(path),
    do: valid_text?(path) and Path.type(path) == :absolute and Path.expand(path) == path

  defp valid_text?(text),
    do:
      is_binary(text) and byte_size(text) in 1..4096 and String.valid?(text) and
        not String.contains?(text, [<<0>>, "\n", "\r"])

  defp safe_id?(id), do: is_binary(id) and Regex.match?(~r/\A[A-Za-z0-9_-]{1,80}\z/, id)

  defp full_sha?(sha),
    do: is_binary(sha) and Regex.match?(~r/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/, sha)

  @doc false
  def git(directory, args, opts \\ []) do
    case System.find_executable("git") do
      nil -> {:error, :git_unavailable}
      executable -> command(executable, directory, args, opts)
    end
  end

  defp command(executable, directory, args, opts) do
    capture = :ets.new(:workspace_output, [:set, :public])
    :ets.insert(capture, [{:bytes, 0}, {:chunks, []}])
    runner = Keyword.get(opts, :runner, &Boss.Agents.Process.run/3)

    callback = fn
      {:stdout, bytes} ->
        if :ets.update_counter(capture, :bytes, byte_size(bytes)) > @output_limit,
          do: throw(:output_limit)

        [{:chunks, chunks}] = :ets.lookup(capture, :chunks)
        :ets.insert(capture, {:chunks, [bytes | chunks]})
        :ok

      _ ->
        :ok
    end

    try do
      result =
        runner.(executable, @git_config ++ ["-C", directory | args],
          cd: directory,
          input: "",
          timeout_ms: 15_000,
          output_limit: @output_limit,
          env: git_env() ++ Keyword.get(opts, :git_env, []),
          on_event: callback
        )

      case result do
        %{outcome: :unsupported} ->
          {:error, :unsupported_platform}

        %{cleanup: cleanup} when cleanup != :group_empty ->
          {:error, :cleanup_unknown}

        %{
          outcome: :exited,
          exit_kind: :exit,
          exit_code: code,
          eof: %{stdout: true, stderr: true},
          cleanup: :group_empty
        } ->
          if code == 0 do
            [{:chunks, chunks}] = :ets.lookup(capture, :chunks)
            {:ok, chunks |> Enum.reverse() |> IO.iodata_to_binary() |> String.trim_trailing("\n")}
          else
            {:error, {:git_exit, code}}
          end

        %{outcome: :cancelled, cleanup: :group_empty} ->
          {:error, :cancelled}

        %{cleanup: :group_empty} ->
          {:error, :git_failed}

        _ ->
          {:error, :cleanup_unknown}
      end
    catch
      _, _ -> {:error, :cleanup_unknown}
    after
      :ets.delete(capture)
    end
  end

  defp git_env do
    cleared = for {key, _} <- System.get_env(), String.starts_with?(key, "GIT_"), do: {key, nil}

    cleared ++
      [
        {"GIT_CONFIG_GLOBAL", "/dev/null"},
        {"GIT_CONFIG_NOSYSTEM", "1"},
        {"GIT_TERMINAL_PROMPT", "0"},
        {"GIT_NO_LAZY_FETCH", "1"},
        {"GIT_OPTIONAL_LOCKS", "0"},
        {"GIT_NO_REPLACE_OBJECTS", "1"}
      ]
  end
end
