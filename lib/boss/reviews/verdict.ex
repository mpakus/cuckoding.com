defmodule Boss.Reviews.Verdict do
  @moduledoc "Validates one bounded reviewer proposal; it does not approve task delivery."
  @limit 32_768

  def decode(text) when is_binary(text) and byte_size(text) in 1..@limit do
    with true <- String.valid?(text),
         {:ok, decoded} <- Jason.decode(text, objects: :ordered_objects),
         {:ok, report} <- object(decoded, ~w(acceptance issues summary verdict)),
         true <- text?(report["summary"], 2000),
         {:ok, acceptance} <- objects(report["acceptance"], 1..20, &acceptance/1),
         {:ok, issues} <- objects(report["issues"], 0..20, &issue/1),
         true <- consistent?(report["verdict"], acceptance, issues) do
      {:ok, %{report | "acceptance" => acceptance, "issues" => issues}}
    else
      _ -> {:error, :invalid_review}
    end
  end

  def decode(_), do: {:error, :invalid_review}

  # Keep pairs until exact-key validation so duplicate keys cannot erase findings.
  defp object(%Jason.OrderedObject{values: pairs}, keys) do
    if Enum.sort(Enum.map(pairs, &elem(&1, 0))) == keys,
      do: {:ok, Map.new(pairs)},
      else: :error
  end

  defp object(_, _), do: :error

  defp objects(values, range, validate) when is_list(values) do
    if length(values) in range do
      Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
        case validate.(value) do
          {:ok, valid} -> {:cont, {:ok, [valid | acc]}}
          _ -> {:halt, :error}
        end
      end)
      |> case do
        {:ok, values} -> {:ok, Enum.reverse(values)}
        _ -> :error
      end
    else
      :error
    end
  end

  defp objects(_, _, _), do: :error

  defp acceptance(value) do
    with {:ok, item} <- object(value, ~w(criterion evidence status)),
         true <- text?(item["criterion"], 1000) and text?(item["evidence"], 2000),
         true <- item["status"] in ~w(passed failed unclear) do
      {:ok, item}
    end
  end

  defp issue(value) do
    with {:ok, item} <- object(value, ~w(criterion message)),
         true <- text?(item["criterion"], 1000) and text?(item["message"], 2000) do
      {:ok, item}
    end
  end

  defp text?(value, limit),
    do: is_binary(value) and byte_size(value) in 1..limit and String.trim(value) != ""

  defp consistent?("approved", acceptance, []),
    do: Enum.all?(acceptance, &(&1["status"] == "passed"))

  defp consistent?("changes_requested", acceptance, [_ | _]),
    do: Enum.any?(acceptance, &(&1["status"] == "failed"))

  defp consistent?("needs_spec_revision", acceptance, [_ | _]),
    do: Enum.any?(acceptance, &(&1["status"] == "unclear"))

  defp consistent?(_, _, _), do: false
end
