defmodule AgentDesk.Paths do
  @moduledoc """
  Path canonicalization used before comparing or persisting filesystem locations.
  """

  @max_symlink_depth 32

  @spec canonicalize(Path.t()) ::
          {:ok, String.t()} | {:error, :not_found | :not_a_directory | :symlink_loop}
  def canonicalize(path) when is_binary(path) do
    expanded = Path.expand(path)

    with {:ok, resolved} <- resolve(expanded, 0),
         true <- File.dir?(resolved) || {:error, :not_a_directory} do
      {:ok, resolved}
    else
      false -> {:error, :not_a_directory}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve(_path, depth) when depth > @max_symlink_depth, do: {:error, :symlink_loop}

  defp resolve(path, depth) do
    case File.lstat(path) do
      {:ok, %{type: :symlink}} ->
        case File.read_link(path) do
          {:ok, target} ->
            target
            |> expand_target(path)
            |> resolve(depth + 1)

          {:error, :enoent} ->
            {:error, :not_found}

          {:error, _reason} ->
            {:error, :not_found}
        end

      {:ok, %{type: :directory}} ->
        {:ok, path}

      {:ok, _stat} ->
        {:error, :not_a_directory}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, _reason} ->
        {:error, :not_found}
    end
  end

  defp expand_target(target, from_path) do
    if Path.type(target) == :absolute do
      Path.expand(target)
    else
      Path.expand(target, Path.dirname(from_path))
    end
  end
end
