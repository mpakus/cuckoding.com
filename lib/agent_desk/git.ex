defmodule AgentDesk.Git do
  @moduledoc """
  Git probes and worktree operations. Commands use an executable plus argv.
  """

  @spec repository?(Path.t()) :: boolean()
  def repository?(path) when is_binary(path) do
    File.exists?(Path.join(path, ".git"))
  end

  @doc """
  Walks from a file or directory up to the nearest Git working tree.
  """
  @spec discover_repository(Path.t()) ::
          {:ok, String.t()} | {:error, :not_found | :not_a_git_repository}
  def discover_repository(path) when is_binary(path) do
    expanded = Path.expand(path)

    start =
      cond do
        File.dir?(expanded) -> expanded
        File.regular?(expanded) -> Path.dirname(expanded)
        true -> nil
      end

    case start do
      nil -> {:error, :not_found}
      dir -> climb_repository(dir)
    end
  end

  defp climb_repository(dir) do
    parent = Path.dirname(dir)

    cond do
      repository?(dir) -> {:ok, dir}
      parent == dir -> {:error, :not_a_git_repository}
      true -> climb_repository(parent)
    end
  end

  @spec default_branch(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def default_branch(path) do
    case git(path, ["symbolic-ref", "--short", "HEAD"]) do
      {:ok, name} when name != "" -> {:ok, name}
      _ -> git(path, ["rev-parse", "--abbrev-ref", "HEAD"])
    end
  end

  @spec rev_parse(Path.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def rev_parse(path, rev \\ "HEAD") do
    git(path, ["rev-parse", rev])
  end

  @spec remote_origin(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def remote_origin(path) do
    git(path, ["remote", "get-url", "origin"])
  end

  @spec dirty?(Path.t()) :: boolean()
  def dirty?(path) do
    case git(path, ["status", "--porcelain"]) do
      {:ok, ""} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @spec status_porcelain(Path.t()) :: {:ok, String.t()} | {:error, term()}
  def status_porcelain(path), do: git(path, ["status", "--porcelain"])

  @spec diff(Path.t(), String.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def diff(path, base \\ nil) do
    args = if is_binary(base), do: ["diff", base], else: ["diff"]
    git(path, args)
  end

  @spec changed_files(Path.t(), String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def changed_files(path, base) do
    case git(path, ["diff", "--name-only", base]) do
      {:ok, ""} -> {:ok, []}
      {:ok, out} -> {:ok, String.split(out, "\n", trim: true)}
      error -> error
    end
  end

  @spec commit_all(Path.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def commit_all(path, message) when is_binary(message) do
    with {:ok, _} <- git(path, ["add", "-A"]),
         {:ok, _} <- git(path, ["commit", "-m", message]) do
      rev_parse(path, "HEAD")
    end
  end

  @spec worktree_add(Path.t(), Path.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def worktree_add(repo, worktree_path, branch) do
    git(repo, ["worktree", "add", "-b", branch, worktree_path])
  end

  @spec worktree_list(Path.t()) :: {:ok, [String.t()]} | {:error, term()}
  def worktree_list(repo) do
    case git(repo, ["worktree", "list", "--porcelain"]) do
      {:ok, out} ->
        paths =
          out
          |> String.split("\n", trim: true)
          |> Enum.filter(&String.starts_with?(&1, "worktree "))
          |> Enum.map(&String.trim_leading(&1, "worktree "))

        {:ok, paths}

      error ->
        error
    end
  end

  @spec linked_worktree?(Path.t(), Path.t()) :: boolean()
  def linked_worktree?(repo, worktree_path) do
    canonical = Path.expand(worktree_path)

    case worktree_list(repo) do
      {:ok, paths} -> Enum.any?(paths, &(Path.expand(&1) == canonical))
      {:error, _} -> false
    end
  end

  @spec worktree_remove(Path.t(), Path.t()) :: :ok | {:error, term()}
  def worktree_remove(repo, worktree_path) do
    case git(repo, ["worktree", "remove", worktree_path]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @spec contains_commit?(Path.t(), String.t()) :: boolean()
  def contains_commit?(path, sha) do
    case git(path, ["merge-base", "--is-ancestor", sha, "HEAD"]) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @spec prepare_cherry_pick(Path.t(), String.t()) :: :ok | {:error, :conflict | term()}
  def prepare_cherry_pick(path, sha) do
    case git(path, ["cherry-pick", "--no-commit", sha]) do
      {:ok, _} -> :ok
      {:error, {_code, out}} -> cherry_pick_result(out)
    end
  end

  @spec prepare_merge(Path.t(), String.t()) :: :ok | {:error, :conflict | term()}
  def prepare_merge(path, ref) do
    case git(path, ["merge", "--no-commit", "--no-ff", ref]) do
      {:ok, _} -> :ok
      {:error, {_code, out}} -> cherry_pick_result(out)
    end
  end

  @spec conflicted?(Path.t()) :: boolean()
  def conflicted?(path) do
    case git(path, ["diff", "--name-only", "--diff-filter=U"]) do
      {:ok, ""} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp cherry_pick_result(out) do
    if String.contains?(out, "conflict") or String.contains?(out, "CONFLICT") do
      {:error, :conflict}
    else
      {:error, out}
    end
  end

  @spec merge_conflict?(Path.t(), String.t(), String.t()) :: boolean()
  def merge_conflict?(path, ours, theirs) do
    case git(path, ["merge-tree", "--write-tree", ours, theirs]) do
      {:ok, _} ->
        false

      {:error, {_code, out}} ->
        classic_conflict?(path, ours, theirs, out)
    end
  end

  @spec merge_commit(Path.t(), String.t(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def merge_commit(path, ref, message) when is_binary(ref) and is_binary(message) do
    case git(path, ["merge", "--no-ff", "--no-edit", "-m", message, ref]) do
      {:ok, _} ->
        rev_parse(path, "HEAD")

      error ->
        _ = git(path, ["merge", "--abort"])
        merge_fail(error)
    end
  end

  defp classic_conflict?(path, ours, theirs, out) do
    if String.contains?(out, "unknown option") do
      classic_merge_tree_conflict?(path, ours, theirs)
    else
      true
    end
  end

  defp classic_merge_tree_conflict?(path, ours, theirs) do
    case git(path, ["merge-base", ours, theirs]) do
      {:ok, base} ->
        case git(path, ["merge-tree", base, ours, theirs]) do
          {:ok, tree} ->
            String.contains?(tree, "CHANGED in both") or String.contains?(tree, "<<<<<<")

          {:error, _} ->
            true
        end

      {:error, _} ->
        true
    end
  end

  defp merge_fail({:error, {_code, out}}) do
    if String.contains?(out, "conflict") or String.contains?(out, "CONFLICT") do
      {:error, :conflict}
    else
      {:error, out}
    end
  end

  defp git(path, args) do
    case System.find_executable("git") do
      nil ->
        {:error, :git_not_found}

      git ->
        case System.cmd(git, ["-c", "commit.gpgsign=false" | args],
               cd: path,
               stderr_to_stdout: true
             ) do
          {out, 0} -> {:ok, String.trim(out)}
          {out, code} -> {:error, {code, String.trim(out)}}
        end
    end
  end
end
