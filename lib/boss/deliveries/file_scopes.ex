defmodule Boss.Deliveries.FileScopes do
  @moduledoc false

  def validate(nil), do: {:ok, nil}

  def validate(scopes) when is_list(scopes) and length(scopes) in 1..64 do
    scopes = Enum.map(scopes, &object/1)

    if Enum.all?(scopes, &valid?/1) and
         Enum.uniq_by(scopes, & &1["path"]) == scopes,
       do: {:ok, scopes},
       else: {:error, :invalid_file_scopes}
  end

  def validate(_), do: {:error, :invalid_file_scopes}

  def overlap?(nil, _), do: false
  def overlap?(_, nil), do: false

  def overlap?(left, right) do
    paths = Enum.map(left ++ right, & &1["path"])

    # SQLite only folds ASCII; serialize Unicode predictions conservatively too.
    Enum.any?(paths, &(not String.match?(&1, ~r/\A[\x00-\x7f]*\z/))) or
      Enum.any?(left, fn a ->
        Enum.any?(right, fn b ->
          a = String.downcase(a["path"])
          b = String.downcase(b["path"])
          a == b or String.starts_with?(a, b <> "/") or String.starts_with?(b, a <> "/")
        end)
      end)
  end

  defp object(%Jason.OrderedObject{values: pairs}) do
    if Enum.sort(Enum.map(pairs, &elem(&1, 0))) == ~w(kind path), do: Map.new(pairs)
  end

  defp object(value), do: value

  defp valid?(%{"kind" => kind, "path" => path} = scope)
       when map_size(scope) == 2 and kind in ["file", "directory"] and is_binary(path) do
    byte_size(path) in 1..1024 and String.valid?(path) and String.trim(path) == path and
      not String.match?(path, ~r/[\x00-\x1f\x7f\\:*?\[\]{}]/) and
      Enum.all?(String.split(path, "/"), &(String.downcase(&1) not in ["", ".", "..", ".git"]))
  end

  defp valid?(_), do: false
end
