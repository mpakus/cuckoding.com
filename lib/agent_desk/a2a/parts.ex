defmodule AgentDesk.A2A.Parts do
  @moduledoc """
  Validates bounded A2A message parts. Remote URLs and binary blobs are rejected.
  """

  alias AgentDesk.A2A.Artifact
  alias AgentDesk.A2A.Policy
  alias AgentDesk.Repo
  alias AgentDesk.Scope

  @spec validate(Scope.t(), [map()]) :: {:ok, [map()]} | {:error, atom()}
  def validate(%Scope{} = scope, parts) when is_list(parts) do
    Enum.reduce_while(parts, {:ok, []}, fn part, {:ok, acc} ->
      case normalize(scope, part) do
        {:ok, normalized} -> {:cont, {:ok, acc ++ [normalized]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  def validate(_scope, _parts), do: {:error, :invalid_parts}

  defp normalize(scope, part) when is_map(part) do
    dispatch_part(part_type(part), scope, part)
  end

  defp normalize(_scope, _part), do: {:error, :unknown_part}

  defp part_type(part), do: to_string(part["type"] || part[:type] || "")

  defp dispatch_part("text", _scope, part), do: text_part(part["text"] || part[:text])
  defp dispatch_part("data", _scope, part), do: data_part(part["data"] || part[:data] || part)

  defp dispatch_part("artifact_ref", scope, part) do
    artifact_part(scope, part["artifact_id"] || part[:artifact_id])
  end

  defp dispatch_part("file_ref", _scope, part), do: file_part(part["path"] || part[:path])
  defp dispatch_part(_other, _scope, part), do: fallback_text(part)

  defp fallback_text(part) do
    text = part["text"] || part[:text]
    if is_binary(text), do: text_part(text), else: {:error, :unknown_part}
  end

  defp text_part(text) when is_binary(text) and byte_size(text) <= 10_000 do
    {:ok, %{"type" => "text", "text" => text}}
  end

  defp text_part(_), do: {:error, :oversized_part}

  defp data_part(%{"schema" => schema} = data) when is_binary(schema) do
    encoded = Jason.encode!(data)

    cond do
      byte_size(encoded) > Policy.max_part_bytes() -> {:error, :oversized_part}
      String.contains?(encoded, "://") -> {:error, :remote_url}
      true -> {:ok, %{"type" => "data", "schema" => schema, "data" => Map.delete(data, "schema")}}
    end
  end

  defp data_part(_), do: {:error, :unknown_schema}

  defp artifact_part(%Scope{project: project}, id) when is_binary(id) do
    case Repo.get_by(Artifact, id: id, project_id: project.id) do
      %Artifact{state: "available"} = artifact ->
        {:ok,
         %{
           "type" => "artifact_ref",
           "artifact_id" => artifact.id,
           "sha256" => artifact.sha256
         }}

      %Artifact{} ->
        {:error, :artifact_integrity}

      nil ->
        {:error, :foreign_artifact}
    end
  end

  defp artifact_part(_scope, _), do: {:error, :foreign_artifact}

  defp file_part(path) when is_binary(path) do
    cond do
      String.contains?(path, "://") -> {:error, :remote_url}
      String.contains?(path, "..") -> {:error, :path_traversal}
      Path.type(path) == :absolute -> {:error, :path_traversal}
      true -> {:ok, %{"type" => "file_ref", "path" => path}}
    end
  end

  defp file_part(_), do: {:error, :path_traversal}
end
