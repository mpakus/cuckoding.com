defmodule Boss.Projects.SpecDocument do
  @moduledoc "Parses Markdown metadata without changing the stored source."

  @max_document_bytes 1_048_576
  @max_header_bytes 16_384
  @parser_timeout 500

  def parse(relative_path, original_text)
      when is_binary(relative_path) and is_binary(original_text) do
    with :ok <- validate_source(original_text),
         {:ok, metadata, body} <- split_document(strip_bom(original_text)),
         {:ok, title} <- title(metadata, body, relative_path) do
      {:ok,
       metadata
       |> Map.put(:title, title)
       |> Map.put(:relative_path, relative_path)
       |> Map.put(:original_text, original_text)}
    end
  end

  def parse(_, _), do: {:error, "The document must contain UTF-8 Markdown text."}

  defp validate_source(text) do
    cond do
      byte_size(text) > @max_document_bytes -> {:error, "The document exceeds 1 MiB."}
      not String.valid?(text) -> {:error, "The document must contain valid UTF-8 text."}
      String.contains?(text, <<0>>) -> {:error, "The document contains a NUL character."}
      true -> :ok
    end
  end

  defp strip_bom(<<0xEF, 0xBB, 0xBF, rest::binary>>), do: rest
  defp strip_bom(text), do: text

  defp split_document(text) do
    case Regex.run(~r/\A---[ \t]*(?:\r?\n|\z)/, text, return: :index) do
      [{0, opening_size}] ->
        rest = binary_part(text, opening_size, byte_size(text) - opening_size)

        case Regex.run(~r/^---[ \t]*(?:\r?\n|\z)/m, rest, return: :index) do
          [{header_size, closing_size}] when header_size <= @max_header_bytes ->
            header = binary_part(rest, 0, header_size)
            body_offset = header_size + closing_size
            body = binary_part(rest, body_offset, byte_size(rest) - body_offset)

            with {:ok, metadata} <- parse_header(header), do: {:ok, metadata, body}

          _ when byte_size(rest) > @max_header_bytes ->
            {:error, "Frontmatter exceeds 16 KiB."}

          _ ->
            {:error, "Frontmatter needs a closing --- line."}
        end

      nil ->
        {:ok, %{}, text}
    end
  end

  defp parse_header(header) do
    caller = self()
    ref = make_ref()

    {pid, monitor} =
      :erlang.spawn_opt(
        fn ->
          # Scheduling inside the worker covers a caller dying just after spawn.
          {:ok, timer} = :timer.kill_after(@parser_timeout)

          try do
            send(caller, {ref, decode_header(header)})
          after
            :timer.cancel(timer)
          end
        end,
        [:monitor, {:max_heap_size, %{size: 2_000_000, kill: true, error_logger: false}}]
      )

    receive do
      {^ref, result} ->
        Process.demonitor(monitor, [:flush])
        result

      {:DOWN, ^monitor, :process, ^pid, _reason} ->
        {:error, "Frontmatter exceeds parser resource limits."}
    end
  end

  defp decode_header(header) do
    # yamerl 0.10 resolves some flow-collection aliases to the first child.
    # Reject aliases as tokens, so quoted '*' text remains an ordinary string.
    :yamerl_parser.string(header, token_fun: &check_token/1)

    case YamlElixir.read_all_from_string(header,
           maps_as_keywords: true,
           atoms: false,
           merge_anchors: false,
           schema: :core,
           ignore_unrecognized_tags: false,
           erlang_atom_only_if_exist: true,
           erlang_atom_autodetection: false
         ) do
      {:ok, [[{_, _} | _] = pairs]} ->
        with :ok <- validate_metadata(pairs), do: extract_metadata(pairs)

      {:ok, _} ->
        {:error, "Frontmatter must be one nonempty YAML mapping."}

      {:error, _} ->
        {:error, "Frontmatter contains invalid YAML or an unsupported tag."}
    end
  catch
    :unsupported_alias -> {:error, "Frontmatter aliases are not supported."}
    :unsupported_binary -> {:error, "Frontmatter binary values are not supported."}
    _, _ -> {:error, "Frontmatter contains invalid YAML or an unsupported tag."}
  end

  defp check_token({:yamerl_alias, _, _, _}), do: throw(:unsupported_alias)

  defp check_token(
         {:yamerl_scalar, _, _, {:yamerl_tag, _, _, ~c"tag:yaml.org,2002:binary"}, _, _, _}
       ),
       do: throw(:unsupported_binary)

  defp check_token(_), do: :ok

  defp validate_metadata([{_, _} | _] = pairs) do
    Enum.reduce_while(pairs, MapSet.new(), fn {key, value}, seen ->
      cond do
        not is_binary(key) ->
          {:halt, {:error, "Frontmatter keys must be strings."}}

        String.starts_with?(key, "<<") ->
          {:halt, {:error, "Frontmatter merge keys are not supported."}}

        MapSet.member?(seen, key) ->
          {:halt, {:error, "Frontmatter contains a duplicate key."}}

        true ->
          case validate_metadata(value) do
            :ok -> {:cont, MapSet.put(seen, key)}
            error -> {:halt, error}
          end
      end
    end)
    |> case do
      %MapSet{} -> :ok
      error -> error
    end
  end

  defp validate_metadata(values) when is_list(values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case validate_metadata(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_metadata(_), do: :ok

  defp extract_metadata(pairs) do
    Enum.reduce_while(pairs, {:ok, %{}}, fn
      {key, value}, {:ok, attrs} when key in ["id", "title"] ->
        if valid_field?(key, value) do
          field = if key == "id", do: :explicit_id, else: :title
          {:cont, {:ok, Map.put(attrs, field, value)}}
        else
          {:halt,
           {:error,
            "Frontmatter #{key} must be a nonempty string of at most 200 #{if key == "id", do: "bytes", else: "characters"}."}}
        end

      _, result ->
        {:cont, result}
    end)
  end

  defp valid_field?(key, value) when is_binary(value) do
    length = if key == "id", do: byte_size(value), else: String.length(value)

    String.valid?(value) and length in 1..200 and String.trim(value) == value and
      not String.contains?(value, [<<0>>, "\n", "\r"])
  end

  defp valid_field?(_, _), do: false

  defp title(metadata, body, path) do
    title = metadata[:title] || first_heading(body) || Path.rootname(Path.basename(path))

    if valid_field?("title", title),
      do: {:ok, title},
      else: {:error, "The title must contain 1 to 200 characters on one line."}
  end

  defp first_heading(body) do
    body
    |> String.split(~r/\r?\n/)
    |> Enum.reduce_while(nil, fn line, fence ->
      cond do
        fence && closes_fence?(line, fence) ->
          {:cont, nil}

        fence ->
          {:cont, fence}

        opening = Regex.run(~r/^ {0,3}(`{3,}|~{3,})/, line) ->
          {:cont, List.last(opening)}

        heading = Regex.run(~r/^ {0,3}#([ \t]+.*|$)/, line) ->
          title =
            heading |> List.last() |> String.replace(~r/[ \t]+#+[ \t]*$/, "") |> String.trim()

          if title == "", do: {:cont, nil}, else: {:halt, {:title, title}}

        true ->
          {:cont, nil}
      end
    end)
    |> case do
      {:title, title} -> title
      _ -> nil
    end
  end

  defp closes_fence?(line, fence) do
    case Regex.run(~r/^ {0,3}(`{3,}|~{3,})[ \t]*$/, line) do
      [_, closing] ->
        String.first(closing) == String.first(fence) and byte_size(closing) >= byte_size(fence)

      _ ->
        false
    end
  end
end
