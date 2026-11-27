defmodule Boss.Deliveries.PeerReview do
  @moduledoc false
  import Ecto.Query
  alias Boss.Repo

  # Pin at the first authorization and copy that version into each derived request.
  # Historical schema fixtures omit the column and retain their original routing.
  def insert!(record, source \\ :new)

  def insert!(%{routing_version: 2} = record, source) do
    if installed?() do
      pinned = %{record | peer_review_version: version(source)}
      # Match ordinary reads, which omit this insert-only field on older schemas.
      %{Repo.insert!(pinned) | peer_review_version: nil}
    else
      Repo.insert!(record)
    end
  end

  def insert!(record, _source), do: Repo.insert!(record)

  def excluded_authors(
        %{reviewer: "codex", implementer: "codex", routing_version: 2} = d,
        kind,
        cycle,
        steps
      )
      when kind in ["review", "merge_review"] do
    if installed?() and version(d) == 1 do
      case Enum.find(
             steps,
             &(&1.kind == "implement" and &1.status == "finished" and &1.cycle == cycle)
           ) do
        %{input: %{"model_profile" => %{"model" => model}}} when is_binary(model) ->
          {:ok, [model]}

        _ ->
          {:error, :missing_evidence}
      end
    else
      {:ok, []}
    end
  end

  def excluded_authors(_, _, _, _), do: {:ok, []}

  defp version(:new), do: 1
  defp version(%schema{id: id}), do: version({schema, id})

  defp version({schema, id}) do
    Repo.one!(from r in schema, where: r.id == ^id, select: r.peer_review_version)
  end

  defp installed? do
    Repo.query!("SELECT 1 FROM pragma_table_info('deliveries') WHERE name='peer_review_version'").rows ==
      [[1]]
  end
end
