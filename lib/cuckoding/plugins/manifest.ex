defmodule Cuckoding.Plugins.Manifest do
  @moduledoc "Strict parser for bounded, non-symlinked plugin manifests."

  @maximum_bytes 1_048_576
  @kinds ~w(knowledge_backend shell_filter instruction_skill mcp_server runner metric_source vcs_host secret_store notifier)
  @scopes ~w(project board role stage)
  @networks ~w(none loopback external)
  @top_fields ~w(schema_version key name version kind homepage license detect capabilities permissions config_schema scopes isolation_claims)
  @required_top_fields @top_fields
  @permission_fields ~w(host_process network read_paths write_paths secrets)
  @detect_fields ~w(binaries paths env)
  @binary_fields ~w(name version_command min_version)
  @key_pattern ~r/^[a-z][a-z0-9_-]{0,63}$/
  @name_pattern ~r/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/
  @version_arguments ~w(--version -V version)
  @path_roots ["${RUN_WORKTREE}", "${RUN_DIR}"]

  defstruct [:path, :source, :hash, :data]

  def kinds, do: @kinds

  def load(path, source) when source in ~w(bundled user) do
    with {:ok, %{type: :regular, size: size}} when size <= @maximum_bytes <- File.lstat(path),
         {:ok, raw} <- File.read(path),
         :ok <- unique_mapping_keys(raw),
         {:ok, data} when is_map(data) <- YamlElixir.read_from_string(raw),
         :ok <- validate(data) do
      {:ok,
       %__MODULE__{
         path: Path.expand(path),
         source: source,
         hash: sha256(raw),
         data: data
       }}
    else
      {:ok, %{size: size}} when size > @maximum_bytes ->
        {:error, :manifest_too_large}

      {:ok, _stat} ->
        {:error, :manifest_not_regular_file}

      {:error, %YamlElixir.ParsingError{} = error} ->
        {:error, {:invalid_manifest_yaml, Exception.message(error)}}

      {:error, reason} ->
        {:error, reason}

      _other ->
        {:error, :invalid_manifest}
    end
  end

  def load(_path, _source), do: {:error, :invalid_manifest_path}

  def validate(data) when is_map(data) do
    with :ok <- exact_fields(data, @required_top_fields, @top_fields, "manifest"),
         1 <- data["schema_version"],
         :ok <- matches(data["key"], @key_pattern, :invalid_plugin_key),
         :ok <- text(data["name"], :invalid_plugin_name),
         :ok <- semantic_version(data["version"], :invalid_plugin_version),
         true <- data["kind"] in @kinds,
         :ok <- http_url(data["homepage"]),
         :ok <- text(data["license"], :invalid_plugin_license),
         :ok <- detect(data["detect"]),
         :ok <- string_list(data["capabilities"], :invalid_capabilities),
         :ok <- permissions(data["permissions"]),
         true <- is_map(data["config_schema"]),
         :ok <- subset(data["scopes"], @scopes, :invalid_plugin_scopes),
         :ok <- isolation_claims(data["kind"], data["isolation_claims"]) do
      :ok
    else
      nil -> {:error, :missing_manifest_field}
      false -> {:error, :invalid_manifest}
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_manifest}
    end
  end

  def validate(_data), do: {:error, :invalid_manifest}

  defp detect(detect) when is_map(detect) do
    with :ok <- exact_fields(detect, @detect_fields, @detect_fields, "detect"),
         :ok <- binaries(detect["binaries"]),
         :ok <- string_list(detect["paths"], :invalid_detection_paths) do
      named_list(detect["env"], :invalid_detection_environment)
    end
  end

  defp detect(_detect), do: {:error, :invalid_detection}

  defp binaries(binaries) when is_list(binaries) do
    Enum.reduce_while(binaries, :ok, fn binary, :ok ->
      case binary(binary) do
        :ok -> {:cont, :ok}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp binaries(_binaries), do: {:error, :invalid_detection_binaries}

  defp binary(binary) when is_map(binary) do
    with :ok <- exact_fields(binary, @binary_fields, @binary_fields, "detect.binary"),
         :ok <- matches(binary["name"], @name_pattern, :invalid_binary_name),
         [name, argument] <- binary["version_command"],
         true <- name == binary["name"] and argument in @version_arguments,
         :ok <- semantic_version(binary["min_version"], :invalid_minimum_version) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :unsafe_version_command}
    end
  end

  defp binary(_binary), do: {:error, :invalid_detection_binary}

  defp permissions(permissions) when is_map(permissions) do
    with :ok <- exact_fields(permissions, @permission_fields, @permission_fields, "permissions"),
         true <- is_boolean(permissions["host_process"]),
         true <- permissions["network"] in @networks,
         :ok <- safe_paths(permissions["read_paths"]),
         :ok <- safe_paths(permissions["write_paths"]),
         :ok <- named_list(permissions["secrets"], :invalid_secret_references) do
      :ok
    else
      {:error, reason} -> {:error, reason}
      _other -> {:error, :invalid_plugin_permissions}
    end
  end

  defp permissions(_permissions), do: {:error, :invalid_plugin_permissions}

  defp safe_paths(paths) when is_list(paths) do
    if Enum.all?(paths, &safe_path?/1), do: :ok, else: {:error, :over_permissive_path}
  end

  defp safe_paths(_paths), do: {:error, :invalid_permission_paths}

  defp safe_path?(path) when is_binary(path) do
    Enum.any?(@path_roots, fn root ->
      path == root or
        (String.starts_with?(path, root <> "/") and ".." not in Path.split(path))
    end)
  end

  defp safe_path?(_path), do: false

  defp isolation_claims("runner", claims), do: string_list(claims, :invalid_isolation_claims)
  defp isolation_claims(_kind, []), do: :ok
  defp isolation_claims(_kind, _claims), do: {:error, :isolation_claims_require_runner}

  defp exact_fields(map, required, allowed, context) do
    missing = required -- Map.keys(map)
    unknown = Map.keys(map) -- allowed

    cond do
      missing != [] -> {:error, {:missing_manifest_fields, context, Enum.sort(missing)}}
      unknown != [] -> {:error, {:unknown_manifest_fields, context, Enum.sort(unknown)}}
      true -> :ok
    end
  end

  defp semantic_version(value, error) when is_binary(value) do
    case Version.parse(value) do
      {:ok, _version} -> :ok
      :error -> {:error, error}
    end
  end

  defp semantic_version(_value, error), do: {:error, error}

  defp http_url(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) -> :ok
      _uri -> {:error, :invalid_plugin_homepage}
    end
  end

  defp http_url(_value), do: {:error, :invalid_plugin_homepage}

  defp subset(values, allowed, error) when is_list(values) and values != [] do
    if Enum.uniq(values) == values and Enum.all?(values, &(&1 in allowed)),
      do: :ok,
      else: {:error, error}
  end

  defp subset(_values, _allowed, error), do: {:error, error}

  defp string_list(values, error) when is_list(values) do
    if Enum.uniq(values) == values and Enum.all?(values, &(is_binary(&1) and &1 != "")),
      do: :ok,
      else: {:error, error}
  end

  defp string_list(_values, error), do: {:error, error}

  defp named_list(values, error) when is_list(values) do
    if Enum.uniq(values) == values and Enum.all?(values, &valid_name?/1),
      do: :ok,
      else: {:error, error}
  end

  defp named_list(_values, error), do: {:error, error}

  defp text(value, _error) when is_binary(value) and value != "" and byte_size(value) <= 200,
    do: :ok

  defp text(_value, error), do: {:error, error}

  defp matches(value, pattern, error) when is_binary(value) do
    if Regex.match?(pattern, value), do: :ok, else: {:error, error}
  end

  defp matches(_value, _pattern, error), do: {:error, error}

  defp valid_name?(value) when is_binary(value), do: Regex.match?(@name_pattern, value)
  defp valid_name?(_value), do: false

  defp unique_mapping_keys(raw) do
    case YamlElixir.read_from_string(raw, maps_as_keywords: true) do
      {:ok, value} ->
        reject_duplicate_keys(value)

      {:error, %YamlElixir.ParsingError{} = error} ->
        {:error, {:invalid_manifest_yaml, Exception.message(error)}}
    end
  end

  defp reject_duplicate_keys(values) when is_list(values) do
    if mapping_pairs?(values) do
      keys = Enum.map(values, &elem(&1, 0))

      if length(keys) == length(Enum.uniq(keys)),
        do: reject_nested_values(values),
        else: {:error, :duplicate_manifest_field}
    else
      reduce_nested(values)
    end
  end

  defp reject_duplicate_keys(_value), do: :ok

  defp reject_nested_values(values) do
    Enum.reduce_while(values, :ok, fn {_key, value}, :ok ->
      continue(reject_duplicate_keys(value))
    end)
  end

  defp reduce_nested(values) do
    Enum.reduce_while(values, :ok, fn value, :ok -> continue(reject_duplicate_keys(value)) end)
  end

  defp mapping_pairs?([]), do: false

  defp mapping_pairs?(values) do
    Enum.all?(values, fn
      {key, _value} when is_binary(key) -> true
      _value -> false
    end)
  end

  defp continue(:ok), do: {:cont, :ok}
  defp continue({:error, _reason} = error), do: {:halt, error}

  defp sha256(contents), do: :crypto.hash(:sha256, contents) |> Base.encode16(case: :lower)
end
