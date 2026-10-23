defmodule Cuckoding.BuildInfo do
  @moduledoc "Public package identity; never provider or workflow authority."
  @manifest Path.expand("../../priv/build-info.json", __DIR__)
  @external_resource @manifest
  @embedded if(Mix.env() == :prod, do: File.read!(@manifest), else: nil)

  def current do
    case validate(Application.get_env(:cuckoding, :build_info)) do
      {:ok, info} -> info
      _ -> nil
    end
  end

  def id, do: if(info = current(), do: info["build_id"])

  def validate(
        %{
          "format" => 1,
          "build_id" => id,
          "application" => "0.1.0",
          "channel" => "local-preview",
          "source_revision" => revision,
          "source_dirty" => dirty,
          "source_sha256" => sha,
          "built_at" => built_at,
          "target" => "aarch64-apple-darwin",
          "schema" => schema,
          "elixir" => _,
          "otp" => _,
          "rust" => _
        } = value
      )
      when map_size(value) == 13 and is_boolean(dirty) and is_integer(schema) and
             schema in 1..1000 do
    valid =
      match?({:ok, _}, Ecto.UUID.cast(id)) and
        hex?(revision, 40) and hex?(sha, 64) and utc?(built_at) and
        Enum.all?(~w(elixir otp rust), &version?(value[&1]))

    if valid, do: {:ok, value}, else: {:error, :invalid_build_info}
  end

  def validate(_), do: {:error, :invalid_build_info}

  def load!(expected_id, expected_sha), do: decode!(@embedded, expected_id, expected_sha)

  def decode!(bytes, expected_id, expected_sha) do
    with true <- is_binary(bytes) and byte_size(bytes) <= 4096,
         true <- is_binary(expected_sha) and digest(bytes) == expected_sha,
         {:ok, value} <- Jason.decode(bytes),
         {:ok, info} <- validate(value),
         true <- is_binary(expected_id) and info["build_id"] == expected_id do
      info
    else
      _ -> raise "packaged build identity is missing or mismatched; rebuild the complete app"
    end
  end

  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp hex?(value, length),
    do:
      is_binary(value) and byte_size(value) == length and
        Regex.match?(~r/\A[0-9a-f]+\z/, value)

  defp version?(value),
    do:
      is_binary(value) and byte_size(value) <= 32 and
        Regex.match?(~r/\A[0-9]+(?:\.[0-9]+){1,3}(?:-[a-z0-9.]+)?\z/, value)

  defp utc?(value),
    do:
      is_binary(value) and byte_size(value) == 20 and
        match?({:ok, _, 0}, DateTime.from_iso8601(value)) and String.ends_with?(value, "Z")
end
