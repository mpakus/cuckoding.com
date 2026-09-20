defmodule Cuckoding.Adapters.SharedProfile do
  @moduledoc "App-owned account directories. Never resolves a personal CLI profile."

  def prepare(id, runtime) when runtime in ["codex", "cursor_agent"] do
    root =
      Application.get_env(:cuckoding, :provider_account_root) ||
        Path.join([
          System.user_home!(),
          "Library",
          "Application Support",
          "Cuckoding",
          "provider-accounts"
        ])

    with {:ok, ^id} <- Ecto.UUID.cast(id),
         :ok <- directory(root),
         :ok <- directory(Path.join(root, id)),
         path = Path.join([root, id, name(runtime)]),
         :ok <- directory(path) do
      {:ok, path}
    else
      :error -> {:error, :invalid_provider_account}
      error -> error
    end
  end

  defp name("codex"), do: "codex-home"
  defp name("cursor_agent"), do: "cursor"

  # Check every component before creating anything below it. Existing ancestors
  # are not chmod'd: only the app-owned profile directories get private modes.
  defp directory(path) do
    with :ok <- ancestors(Path.expand(path)),
         :ok <- File.mkdir_p(path),
         do: File.chmod(path, 0o700)
  end

  defp ancestors("/"), do: :ok

  defp ancestors(path) do
    with :ok <- ancestors(Path.dirname(path)) do
      case File.lstat(path) do
        {:ok, %{type: :directory}} -> :ok
        {:error, :enoent} -> :ok
        _other -> {:error, :profile_path_unsafe}
      end
    end
  end
end
