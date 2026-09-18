defmodule Cuckoding.Knowledge.Parser do
  @moduledoc "Parses and validates bounded Markdown knowledge documents without rewriting them."

  defmodule Document do
    @moduledoc false
    @enforce_keys [:raw, :body, :hash, :metadata]
    defstruct [:raw, :body, :hash, :metadata]
  end

  @maximum_bytes 1_048_576
  @maximum_front_matter_bytes 65_536
  @required_keys ~w(id kind title scope status version confidence valid_from invalid_at supersedes evidence produced_by triggers review)
  @kinds ~w(fact decision pattern recipe observation skill)
  @statuses ~w(candidate project global superseded revoked)

  def parse_file(path) when is_binary(path) do
    with {:ok, %{type: :regular, size: size} = before} when size <= @maximum_bytes <-
           File.lstat(path),
         {:ok, raw} <- File.read(path),
         {:ok, %{type: :regular} = after_stat} <- File.lstat(path),
         true <- stable_file?(before, after_stat, raw),
         {:ok, document} <- parse(raw) do
      {:ok, document}
    else
      {:ok, %{type: :symlink}} -> {:error, :knowledge_file_symlink}
      {:ok, %{size: size}} when size > @maximum_bytes -> {:error, :knowledge_file_too_large}
      {:ok, _stat} -> {:error, :knowledge_file_not_regular}
      false -> {:error, :knowledge_file_changed_during_read}
      {:error, reason} -> {:error, reason}
    end
  end

  def parse_file(_path), do: {:error, :invalid_knowledge_path}

  def parse(raw) when is_binary(raw) and byte_size(raw) <= @maximum_bytes do
    with {:ok, yaml, body} <- split(raw),
         true <- byte_size(yaml) <= @maximum_front_matter_bytes,
         :ok <- unique_mapping_keys(yaml),
         {:ok, front_matter} when is_map(front_matter) <- YamlElixir.read_from_string(yaml),
         {:ok, metadata} <- normalize(front_matter) do
      {:ok, %Document{raw: raw, body: body, hash: sha256(raw), metadata: metadata}}
    else
      false ->
        {:error, :knowledge_front_matter_too_large}

      {:ok, _other} ->
        {:error, :knowledge_front_matter_not_a_map}

      {:error, %YamlElixir.ParsingError{} = error} ->
        {:error, {:invalid_knowledge_yaml, Exception.message(error)}}

      {:error, _reason} = error ->
        error

      _other ->
        {:error, :invalid_knowledge_document}
    end
  end

  def parse(raw) when is_binary(raw), do: {:error, :knowledge_file_too_large}
  def parse(_raw), do: {:error, :invalid_knowledge_document}

  defp split(raw) do
    case Regex.run(~r/\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z/s, raw, capture: :all_but_first) do
      [yaml, body] -> {:ok, yaml, body}
      _other -> {:error, :invalid_knowledge_front_matter}
    end
  end

  defp stable_file?(before, after_stat, raw) do
    before.inode == after_stat.inode and before.size == after_stat.size and
      before.mtime == after_stat.mtime and after_stat.size == byte_size(raw)
  end

  defp normalize(front_matter) do
    with :ok <- required_keys(front_matter),
         {:ok, id} <- uuid(front_matter["id"]),
         {:ok, kind} <- member(front_matter["kind"], @kinds, :invalid_knowledge_kind),
         {:ok, title} <- title(front_matter["title"]),
         {:ok, scope} <-
           member(front_matter["scope"], ~w(project global), :invalid_knowledge_scope),
         {:ok, status} <- member(front_matter["status"], @statuses, :invalid_knowledge_status),
         :ok <- scope_status(scope, status),
         {:ok, version} <- positive_integer(front_matter["version"]),
         {:ok, confidence} <- confidence(front_matter["confidence"]),
         {:ok, valid_from} <- datetime(front_matter["valid_from"], false),
         {:ok, invalid_at} <- datetime(front_matter["invalid_at"], true),
         :ok <- validity(valid_from, invalid_at),
         {:ok, supersedes_id} <- optional_uuid(front_matter["supersedes"], id),
         {:ok, evidence} <- nonempty_map(front_matter["evidence"], :invalid_knowledge_evidence),
         {:ok, produced_by} <-
           nonempty_map(front_matter["produced_by"], :invalid_knowledge_producer),
         {:ok, triggers} <- triggers(front_matter["triggers"]),
         {:ok, review, reviewed_by, reviewed_at} <- review(front_matter["review"]),
         :ok <- global_review(scope, reviewed_by, reviewed_at) do
      {:ok,
       %{
         id: id,
         kind: kind,
         title: title,
         scope: scope,
         status: status,
         version: version,
         confidence: confidence,
         valid_from: valid_from,
         invalid_at: invalid_at,
         supersedes_id: supersedes_id,
         evidence_json: evidence,
         produced_by_json: produced_by,
         triggers_json: triggers,
         review_json: review,
         reviewed_by: reviewed_by,
         reviewed_at: reviewed_at
       }}
    end
  end

  defp required_keys(front_matter) do
    missing = Enum.reject(@required_keys, &Map.has_key?(front_matter, &1))
    unknown = Map.keys(front_matter) -- @required_keys

    case {missing, unknown} do
      {[], []} -> :ok
      {[_field | _rest] = fields, _unknown} -> {:error, {:missing_knowledge_fields, fields}}
      {[], fields} -> {:error, {:unknown_knowledge_fields, Enum.sort(fields)}}
    end
  end

  defp unique_mapping_keys(yaml) do
    case YamlElixir.read_from_string(yaml, maps_as_keywords: true) do
      {:ok, value} ->
        reject_duplicate_keys(value)

      {:error, %YamlElixir.ParsingError{} = error} ->
        {:error, {:invalid_knowledge_yaml, Exception.message(error)}}
    end
  end

  defp reject_duplicate_keys(values) when is_list(values) do
    if mapping_pairs?(values) do
      keys = Enum.map(values, &elem(&1, 0))

      if length(keys) == length(Enum.uniq(keys)),
        do: reject_nested_values(values),
        else: {:error, :duplicate_knowledge_field}
    else
      Enum.reduce_while(values, :ok, fn value, :ok -> continue(reject_duplicate_keys(value)) end)
    end
  end

  defp reject_duplicate_keys(_value), do: :ok

  defp reject_nested_values(values) do
    Enum.reduce_while(values, :ok, fn {_key, value}, :ok ->
      continue(reject_duplicate_keys(value))
    end)
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

  defp uuid(value) when is_binary(value) do
    case Ecto.UUID.cast(value) do
      {:ok, id} -> {:ok, id}
      :error -> {:error, :invalid_knowledge_id}
    end
  end

  defp uuid(_value), do: {:error, :invalid_knowledge_id}

  defp optional_uuid(nil, _id), do: {:ok, nil}

  defp optional_uuid(value, id) do
    with {:ok, supersedes_id} <- uuid(value),
         false <- supersedes_id == id do
      {:ok, supersedes_id}
    else
      true -> {:error, :knowledge_item_cannot_supersede_itself}
      {:error, _reason} = error -> error
    end
  end

  defp member(value, allowed, error) do
    if value in allowed, do: {:ok, value}, else: {:error, error}
  end

  defp title(value) when is_binary(value) do
    value = String.trim(value)

    if value != "" and String.length(value) <= 200,
      do: {:ok, value},
      else: {:error, :invalid_knowledge_title}
  end

  defp title(_value), do: {:error, :invalid_knowledge_title}

  defp scope_status("project", status) when status != "global", do: :ok
  defp scope_status("global", status) when status in ~w(global superseded revoked), do: :ok
  defp scope_status(_scope, _status), do: {:error, :knowledge_scope_status_mismatch}

  defp positive_integer(value) when is_integer(value) and value > 0, do: {:ok, value}
  defp positive_integer(_value), do: {:error, :invalid_knowledge_version}

  defp confidence(value) when is_number(value) and value >= 0 and value <= 1,
    do: {:ok, value / 1}

  defp confidence(_value), do: {:error, :invalid_knowledge_confidence}

  defp datetime(nil, true), do: {:ok, nil}
  defp datetime(%DateTime{} = value, _optional), do: {:ok, value}

  defp datetime(value, _optional) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, 0} -> {:ok, datetime}
      _other -> {:error, :invalid_knowledge_datetime}
    end
  end

  defp datetime(_value, _optional), do: {:error, :invalid_knowledge_datetime}

  defp validity(_from, nil), do: :ok

  defp validity(from, until) do
    if DateTime.compare(until, from) in [:eq, :gt],
      do: :ok,
      else: {:error, :invalid_knowledge_validity}
  end

  defp nonempty_map(value, _error) when is_map(value) and map_size(value) > 0,
    do: {:ok, value}

  defp nonempty_map(_value, error), do: {:error, error}

  defp triggers(values) when is_list(values) and values != [] do
    if Enum.all?(values, &(is_binary(&1) and String.trim(&1) != "")),
      do: {:ok, Enum.map(values, &String.trim/1)},
      else: {:error, :invalid_knowledge_triggers}
  end

  defp triggers(_values), do: {:error, :invalid_knowledge_triggers}

  defp review(nil), do: {:ok, nil, nil, nil}

  defp review(%{"approver" => approver, "date" => date} = review)
       when is_binary(approver) and approver != "" do
    case datetime(date, false) do
      {:ok, reviewed_at} -> {:ok, review, approver, reviewed_at}
      {:error, _reason} = error -> error
    end
  end

  defp review(_review), do: {:error, :invalid_knowledge_review}

  defp global_review("global", approver, %DateTime{}) when is_binary(approver), do: :ok

  defp global_review("global", _approver, _reviewed_at),
    do: {:error, :global_knowledge_review_required}

  defp global_review("project", _approver, _reviewed_at), do: :ok

  defp sha256(value), do: :crypto.hash(:sha256, value) |> Base.encode16(case: :lower)
end
