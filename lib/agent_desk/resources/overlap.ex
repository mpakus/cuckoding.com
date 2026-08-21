defmodule AgentDesk.Resources.Overlap do
  @moduledoc false

  @path_types ~w(file directory glob)

  @spec conflict?(map(), map()) :: boolean()
  def conflict?(requested, held) do
    requested.agent_session_id != held.agent_session_id and
      mode_conflict?(requested.mode, held.mode) and
      paths_overlap?(requested, held)
  end

  @spec paths_overlap?(map(), map()) :: boolean()
  def paths_overlap?(a, b) do
    ta = type(a)
    tb = type(b)
    ka = key(a)
    kb = key(b)

    cond do
      ta in @path_types and tb in @path_types ->
        pathish_overlap?(ta, ka, tb, kb)

      ta == tb ->
        ka == kb

      true ->
        false
    end
  end

  @spec overlaps?(String.t(), String.t(), String.t()) :: boolean()
  def overlaps?(type, a, b) when type in ["file", "directory"] do
    nested?(normalize(a), normalize(b))
  end

  def overlaps?("glob", a, b), do: glob_overlap?(normalize(a), normalize(b))
  def overlaps?(_type, a, b), do: a == b

  @spec previews([map() | struct()]) :: [{struct() | map(), [String.t()]}]
  def previews(leases) when is_list(leases) do
    Enum.map(leases, fn lease ->
      others =
        leases
        |> Enum.reject(&same_id?(&1, lease))
        |> Enum.filter(&paths_overlap?(lease, &1))
        |> Enum.map(&key/1)

      {lease, others}
    end)
  end

  defp pathish_overlap?("glob", a, "glob", b), do: glob_overlap?(normalize(a), normalize(b))
  defp pathish_overlap?("glob", glob, _type, path), do: glob_vs_path(glob, path)
  defp pathish_overlap?(_type, path, "glob", glob), do: glob_vs_path(glob, path)
  defp pathish_overlap?(_ta, a, _tb, b), do: nested?(normalize(a), normalize(b))

  defp nested?(a, b) do
    a == b or String.starts_with?(a, b <> "/") or String.starts_with?(b, a <> "/")
  end

  defp glob_overlap?(a, b) do
    prefix_a = glob_prefix(a)
    prefix_b = glob_prefix(b)

    a == b or glob_match?(a, b) or glob_match?(b, a) or prefix_a == "" or prefix_b == "" or
      nested?(prefix_a, prefix_b)
  end

  defp glob_vs_path(glob, path) do
    glob = normalize(glob)
    path = normalize(path)
    prefix = glob_prefix(glob)
    glob_match?(glob, path) or prefix == "" or nested?(prefix, path)
  end

  defp glob_prefix(pattern) do
    pattern
    |> String.split(["*", "?"], parts: 2)
    |> hd()
    |> String.trim("/")
  end

  defp glob_match?(pattern, path) do
    regex = glob_to_regex(pattern)
    Regex.match?(regex, path)
  end

  defp glob_to_regex(pattern) do
    escaped =
      pattern
      |> String.split("**")
      |> Enum.map_join(".*", fn part ->
        part
        |> Regex.escape()
        |> String.replace("\\*", "[^/]*")
        |> String.replace("\\?", "[^/]")
      end)

    Regex.compile!("^" <> escaped <> "$")
  end

  defp mode_conflict?("exclusive", _held), do: true
  defp mode_conflict?(_requested, "exclusive"), do: true
  defp mode_conflict?(_requested, _held), do: false

  defp normalize(path) do
    path
    |> String.replace("\\", "/")
    |> String.trim("/")
    |> String.downcase()
  end

  defp type(%{resource_type: type}), do: type
  defp type(%{"resource_type" => type}), do: type
  defp type(other) when is_map(other), do: other[:resource_type] || other["type"]

  defp key(%{resource_key: key}), do: key
  defp key(%{"resource_key" => key}), do: key
  defp key(other) when is_map(other), do: other[:resource_key] || other["key"]

  defp same_id?(%{id: a}, %{id: b}), do: a == b
  defp same_id?(_, _), do: false
end
