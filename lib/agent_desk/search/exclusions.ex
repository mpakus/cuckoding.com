defmodule AgentDesk.Search.Exclusions do
  @moduledoc false

  @dir_names ~w(_build deps node_modules target .git .svn .hg tmp log logs)
  @secret_names ~w(.env .env.local .env.production credentials.json secrets.json id_rsa)

  @spec skip_dir?(String.t()) :: boolean()
  def skip_dir?(name) when is_binary(name), do: name in @dir_names

  @spec skip_file?(String.t()) :: boolean()
  def skip_file?(name) when is_binary(name) do
    name in @secret_names or String.ends_with?(name, ".pem") or String.ends_with?(name, ".key")
  end

  @spec text_file?(String.t()) :: boolean()
  def text_file?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in ~w(.ex .exs .md .txt .json .yml .yaml .toml .css .js .ts .heex .eex .html)
  end
end
