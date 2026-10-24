defmodule Cuckoding.CheckImage do
  @moduledoc "Compiled isolated image identity and audited admission artifacts."
  import Ecto.Query
  alias Cuckoding.Battles.Attempt
  alias Cuckoding.{NativeHelper, Repo}

  @root Path.expand("../../desktop/src-tauri/src", __DIR__)
  @sources ~w(check_image/inputs.json check_image/init check_image/launch check_image/control.mjs check_image/worker.mjs check_image/protocol.mjs check_image/archive.rs check_image/store.rs check_image.rs arena_git/guest_check.rs arena_git.rs probe.rs ../keeper/main.swift ../keeper/entitlements.plist ../build.rs)
  for source <- @sources, do: @external_resource(Path.join(@root, source))

  @image_spec :crypto.hash(:sha256, Enum.map(@sources, &File.read!(Path.join(@root, &1))))
              |> Base.encode16(case: :lower)
  @fields ~w(status contract key spec_sha256 intent_sha256 cleanup_verified kernel_sha256 kernel_bytes ramdisk_sha256 ramdisk_bytes manifest_sha256 toolchains)
  @versions %{"node" => "24.22.1", "npm" => "11.12.1", "elixir" => "1.20.3", "otp" => "28.5.0.8"}
  def spec, do: @image_spec

  def valid?(image, expected_spec) when is_map(image) do
    Enum.sort(Map.keys(image)) == Enum.sort(@fields) and
      header?(image) and
      uuid?(image["key"]) and image["spec_sha256"] == expected_spec and
      image["toolchains"] == @versions and image["cleanup_verified"] == true and
      Enum.all?(
        ~w(spec_sha256 intent_sha256 kernel_sha256 ramdisk_sha256 manifest_sha256),
        &Cuckoding.GitPreview.hash?(image[&1], 64)
      ) and
      Enum.all?(
        ~w(kernel_bytes ramdisk_bytes),
        &(is_integer(image[&1]) and image[&1] in 1..134_217_728)
      )
  end

  def valid?(_, _), do: false

  defp header?(image),
    do:
      image["status"] == "check_image_prepared" and image["contract"] == "isolated-check-image-v1"

  def ensure(attempt, active?) do
    if attempt.request["snapshot"]["check_execution"]["image_spec_sha256"] == @image_spec do
      prepare(attempt, cached(), active?)
    else
      {:error, %{"status" => "check_image_changed", "cleanup_verified" => true}}
    end
  end

  def cached do
    Repo.one(
      from a in Attempt,
        where:
          a.stage == "admission" and a.state == "completed" and
            fragment("json_extract(?, '$.status')", a.result) == "admitted" and
            fragment("json_extract(?, '$.check_image.spec_sha256')", a.result) == ^@image_spec,
        order_by: [desc: a.inserted_at, desc: a.id],
        limit: 1,
        select: a.result
    )
    |> case do
      %{"cleanup_verified" => true, "check_image" => image} ->
        if valid?(image, @image_spec), do: image

      _ ->
        nil
    end
  end

  def scope?(attempt, image) do
    expected = attempt.request["snapshot"]["check_execution"]["image_spec_sha256"]
    valid?(image, expected) and (image["key"] == attempt.id or retained?(image))
  end

  defp retained?(image) do
    key = image["key"]
    expected_spec = image["spec_sha256"]

    Repo.one(
      from a in Attempt,
        where:
          a.stage == "admission" and a.state == "completed" and
            fragment("json_extract(?, '$.status')", a.result) == "admitted" and
            fragment("json_extract(?, '$.check_image.spec_sha256')", a.result) == ^expected_spec and
            fragment("json_extract(?, '$.check_image.key')", a.result) == ^key,
        limit: 1,
        select: a.result
    )
    |> case do
      %{"cleanup_verified" => true, "check_image" => ^image} -> true
      _ -> false
    end
  end

  defp prepare(attempt, previous, active?) do
    {flag, key, request} =
      if previous,
        do:
          {"--verify-check-image", previous["key"],
           %{"key" => previous["key"], "image" => previous}},
        else:
          {"--prepare-check-image", attempt.id,
           %{"key" => attempt.id, "contract" => "isolated-check-image-v1"}}

    result =
      NativeHelper.request(attempt, [flag], 305_000, &decode(&1, key), 8192,
        active?: active?,
        input: Jason.encode!(request)
      )
      |> Map.delete("elapsed_ms")

    expected = if previous, do: Map.put(previous, "status", "check_image_verified")

    cond do
      previous && result == expected ->
        {:ok, previous}

      is_nil(previous) and valid?(Map.drop(result, ["elapsed_ms"]), @image_spec) ->
        {:ok, Map.drop(result, ["elapsed_ms"])}

      true ->
        {:error,
         %{
           "status" => "check_image_unavailable",
           "cleanup_verified" => result["cleanup_verified"] == true
         }}
    end
  end

  @errors ~w(cancelled cleanup_uncertain download_failed image_changed image_exists image_incomplete image_limit invalid_request timeout unsafe_image unsupported_input)

  def decode(bytes, key) when is_binary(bytes) and byte_size(bytes) <= 8192 do
    with {:ok, row} <- Jason.decode(bytes),
         true <- is_map(row),
         true <- row["key"] == key,
         "isolated-check-image-v1" <- row["contract"],
         true <- is_boolean(row["cleanup_verified"]) do
      prepared = Map.put(row, "status", "check_image_prepared")

      cond do
        row["status"] in ~w(check_image_prepared check_image_verified) and
            valid?(prepared, @image_spec) ->
          row

        row["status"] in ~w(check_image_prepared check_image_verified) and
            valid?(prepared, row["spec_sha256"]) ->
          %{"status" => "check_image_changed", "cleanup_verified" => true}

        row["status"] in ~w(check_image_prepared check_image_verified) ->
          %{"status" => "invalid_output", "cleanup_verified" => false}

        true ->
          image_error(row)
      end
    else
      _ -> %{"status" => "invalid_output", "cleanup_verified" => false}
    end
  end

  def decode(_, _), do: %{"status" => "invalid_output", "cleanup_verified" => false}

  defp image_error(row) do
    if row["status"] in @errors and
         Map.keys(row) -- ~w(status contract key cleanup_verified) == [],
       do: %{"status" => "check_image_unavailable", "cleanup_verified" => row["cleanup_verified"]},
       else: %{"status" => "invalid_output", "cleanup_verified" => false}
  end

  defp uuid?(id), do: match?({:ok, ^id}, Ecto.UUID.cast(id))
end
