defmodule Boss.Projects.Repository do
  @moduledoc "Validates a local Git repository and a specs directory without changing either."

  def inspect(directory, specs_path, base_branch \\ nil) do
    with true <- valid_path?(directory),
         {:ok, root} <- git(directory, ["rev-parse", "--show-toplevel"]),
         {:ok, common} <- git(root, ["rev-parse", "--path-format=absolute", "--git-common-dir"]) do
      with {:ok, branch, commit} <- base(root, base_branch),
           {:ok, specs} <- specs_directory(root, specs_path) do
        {:ok,
         %{
           root_path: root,
           git_common_dir: common,
           specs_path: specs,
           base_branch: branch,
           base_commit: commit
         }}
      end
    else
      _ -> {:error, :invalid_repository}
    end
  end

  def specs_directory(root, path) do
    if valid_path?(path) do
      absolute = Path.expand(path, root)
      relative = Path.relative_to(absolute, root)

      if relative == "." or Path.type(relative) == :absolute or ".." in Path.split(relative) do
        {:error, :specs_outside_project}
      else
        Enum.reduce_while(Path.split(relative), {:ok, root}, fn part, {:ok, parent} ->
          next = Path.join(parent, part)

          case File.lstat(next) do
            {:ok, %{type: :directory}} -> {:cont, {:ok, next}}
            {:ok, %{type: :symlink}} -> {:halt, {:error, :specs_symlink}}
            {:error, :enoent} -> {:halt, {:error, :specs_missing}}
            _ -> {:halt, {:error, :invalid_specs_directory}}
          end
        end)
      end
    else
      {:error, :invalid_specs_directory}
    end
  end

  defp base(root, nil) do
    case git(root, ["symbolic-ref", "--quiet", "--short", "HEAD"]) do
      {:ok, branch} -> base(root, branch)
      _ -> {:error, :invalid_base_branch}
    end
  end

  defp base(root, branch) do
    with true <- valid_path?(branch),
         {:ok, _} <- git(root, ["check-ref-format", "--branch", branch]),
         {:ok, commit} <-
           git(root, [
             "rev-parse",
             "--verify",
             "--end-of-options",
             "refs/heads/#{branch}^{commit}"
           ]) do
      {:ok, branch, commit}
    else
      _ -> {:error, :invalid_base_branch}
    end
  end

  defp valid_path?(path) do
    is_binary(path) and path != "" and byte_size(path) <= 4096 and
      not String.contains?(path, [<<0>>, "\n", "\r"])
  end

  defp git(directory, args) do
    env =
      System.get_env()
      |> Map.keys()
      |> Enum.filter(&String.starts_with?(&1, "GIT_"))
      |> Enum.map(&{&1, nil})

    env = env ++ [{"GIT_CONFIG_GLOBAL", "/dev/null"}, {"GIT_CONFIG_NOSYSTEM", "1"}]

    case System.cmd("git", ["-C", directory | args], stderr_to_stdout: true, env: env) do
      {output, 0} -> {:ok, String.trim_trailing(output, "\n")}
      _ -> {:error, :git_failed}
    end
  rescue
    _ in ErlangError -> {:error, :git_unavailable}
  end
end
