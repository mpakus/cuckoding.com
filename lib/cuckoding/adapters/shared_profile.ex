defmodule Cuckoding.Adapters.SharedProfile do
  @moduledoc "App-owned account directories. Never resolves a personal CLI profile."

  def prepare(id, runtime) when runtime in ["codex", "cursor_agent"] do
    root = provider_root()

    with {:ok, ^id} <- Ecto.UUID.cast(id),
         :ok <- directory(root),
         :ok <- directory(Path.join(root, id)),
         path = Path.join([root, id, name(runtime)]),
         :ok <- directory(path),
         :ok <- credential_file(path, runtime) do
      {:ok, path}
    else
      :error -> {:error, :invalid_provider_account}
      error -> error
    end
  end

  defp name("codex"), do: "codex-home"
  defp name("cursor_agent"), do: "cursor"

  def credential_file?(id, "codex") when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, ^id} ->
        home = Path.join([provider_root(), id, "codex-home"])
        ancestors(Path.expand(home)) == :ok and credential_file?(home)

      :error ->
        false
    end
  end

  def credential_file?(home) when is_binary(home) do
    case File.lstat(Path.join(home, "auth.json")) do
      {:ok, %{type: :regular, mode: mode}} -> Bitwise.band(mode, 0o077) == 0
      _other -> false
    end
  end

  def credential_file?(_home), do: false

  defp provider_root do
    Application.get_env(:cuckoding, :provider_account_root) ||
      Path.join([
        System.user_home!(),
        "Library",
        "Application Support",
        "Cuckoding",
        "provider-accounts"
      ])
  end

  defp credential_file(path, "codex") do
    case File.lstat(Path.join(path, "auth.json")) do
      {:error, :enoent} -> :ok
      {:ok, %{type: :regular, mode: mode}} when Bitwise.band(mode, 0o077) == 0 -> :ok
      _other -> {:error, :profile_path_unsafe}
    end
  end

  defp credential_file(_path, _runtime), do: :ok

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
