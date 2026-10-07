defmodule Cuckoding.GitPreview do
  @moduledoc false

  def paths(text) when is_binary(text) and byte_size(text) <= 4_000 do
    selected = text |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
    if valid_paths?(selected), do: {:ok, selected}, else: {:error, "invalid_selection"}
  end

  def paths(_), do: {:error, "invalid_selection"}

  def valid_paths?(paths) when is_list(paths) and length(paths) <= 16,
    do: Enum.uniq(paths) == paths and Enum.all?(paths, &valid_path?/1)

  def valid_paths?(_), do: false

  defp valid_path?(path) when is_binary(path) and byte_size(path) in 1..240 do
    not String.starts_with?(path, "-") and not String.contains?(path, "\\") and
      not Regex.match?(~r/[\p{Cc}]/u, path) and
      Enum.all?(String.split(path, "/"), &allowed_part?/1)
  end

  defp valid_path?(_), do: false

  defp allowed_part?(part) do
    part = String.downcase(part)

    part not in ["", ".", "..", ".git", ".ssh", ".aws", ".azure", ".gnupg", "credentials"] and
      not String.starts_with?(part, [".env", "id_rsa", "id_ed25519"]) and
      not String.ends_with?(part, [".pem", ".key"])
  end

  def normalize(%{"branch" => branch, "repository" => repository, "files" => files})
      when is_binary(branch) and is_list(files) and length(files) <= 16 do
    with true <-
           byte_size(branch) <= 256 and Regex.match?(~r/\Arefs\/heads\/[^\s\p{Cc}]+\z/u, branch),
         true <- hash?(repository, 64),
         true <- Enum.all?(files, &valid_file?/1),
         true <- valid_paths?(Enum.map(files, & &1["path"])),
         true <- Enum.sum(Enum.map(files, & &1["bytes"])) <= 8_388_608 do
      snapshot = %{
        "branch" => branch,
        "repository" => repository,
        "files" => Enum.map(files, &Map.take(&1, ~w(path bytes mode sha256)))
      }

      if byte_size(Jason.encode!(snapshot)) <= 7_000, do: snapshot
    else
      _ -> nil
    end
  end

  def normalize(_), do: nil

  defp valid_file?(%{"path" => path, "bytes" => bytes, "mode" => mode, "sha256" => hash})
       when is_integer(bytes) and bytes in 0..1_048_576 and mode in ~w(100644 100755),
       do: valid_path?(path) and hash?(hash, 64)

  defp valid_file?(_), do: false

  def hash?(value, size) when is_binary(value),
    do: byte_size(value) == size and Regex.match?(~r/\A[0-9a-f]+\z/, value)

  def hash?(_, _), do: false
end
