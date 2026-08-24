defmodule AgentDesk.Attachments do
  @moduledoc """
  Prompt attachments stored under the session data directory.

  Copies into a session worktree inbox only when the session already has an
  isolated worktree, never into the user's primary tree.
  """

  alias AgentDesk.Agents.Session
  alias AgentDesk.Projects.Project
  alias AgentDesk.Storage
  alias AgentDesk.Worktrees
  alias AgentDesk.Worktrees.Worktree

  @type t :: %{
          String.t() => String.t()
        }

  @spec store!(Project.t(), Session.t(), Path.t(), String.t(), String.t() | nil) :: t()
  def store!(%Project{} = project, %Session{} = session, source, filename, mime) do
    filename = sanitize(filename)
    dest_dir = Path.join(Storage.session_dir(project.id, session.id), "attachments")
    File.mkdir_p!(dest_dir)
    dest = Path.join(dest_dir, unique_name(filename))
    File.cp!(source, dest)

    path =
      case copy_to_inbox(project, session, dest, Path.basename(dest)) do
        {:ok, inbox} -> inbox
        :error -> dest
      end

    %{
      "path" => Path.expand(path),
      "canonical" => Path.expand(dest),
      "name" => filename,
      "mime" => mime_or_guess(mime, filename)
    }
  end

  defp copy_to_inbox(project, session, source, filename) do
    case Worktrees.get_for_session(session.id) do
      %Worktree{path: worktree} when is_binary(worktree) ->
        if Path.expand(worktree) == Path.expand(project.canonical_path) do
          :error
        else
          inbox = Path.join(worktree, ".cuckoding-inbox")

          with :ok <- File.mkdir_p(inbox) do
            dest = Path.join(inbox, filename)

            case File.cp(source, dest) do
              :ok -> {:ok, dest}
              {:error, _} -> :error
            end
          end
        end

      _ ->
        :error
    end
  end

  defp unique_name(filename) do
    Integer.to_string(System.unique_integer([:positive])) <> "-" <> filename
  end

  defp sanitize(name) when is_binary(name) do
    name
    |> Path.basename()
    |> String.replace(~r/[^A-Za-z0-9._-]+/, "_")
    |> case do
      "" -> "attachment"
      name -> name
    end
  end

  defp mime_or_guess(mime, _name) when is_binary(mime) and mime != "", do: mime
  defp mime_or_guess(_, name), do: guess_mime(name)

  defp guess_mime(name) do
    case String.downcase(Path.extname(name)) do
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      ".svg" -> "image/svg+xml"
      ".pdf" -> "application/pdf"
      ".json" -> "application/json"
      ".md" -> "text/markdown"
      ".txt" -> "text/plain"
      _ -> "application/octet-stream"
    end
  end
end
