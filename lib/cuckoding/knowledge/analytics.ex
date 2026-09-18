defmodule Cuckoding.Knowledge.Analytics do
  @moduledoc "Bounded, server-side projections for knowledge growth and lineage views."

  import Ecto.Query

  alias Cuckoding.Knowledge.Candidate
  alias Cuckoding.Knowledge.ConsolidationJob
  alias Cuckoding.Knowledge.IndexRevision
  alias Cuckoding.Knowledge.Item
  alias Cuckoding.Knowledge.Job
  alias Cuckoding.Knowledge.SkillPackage
  alias Cuckoding.Knowledge.Usage
  alias Cuckoding.Projects.Project
  alias Cuckoding.Repo

  @maximum_rows 100
  @maximum_usage_rows 200
  @maximum_timeline_groups 180
  @maximum_run_links 500

  def growth do
    %{
      item_counts: item_counts(),
      timeline: timeline(),
      coverage: coverage(),
      review_counts: review_counts(),
      consolidations: consolidations()
    }
  end

  def lineage do
    rows = lineage_rows()
    item_ids = Enum.map(rows, & &1.item.id)
    counts = usage_counts(item_ids)
    runs = usage_runs(item_ids)

    %{
      total_lineages: Repo.aggregate(accepted_candidates(), :count),
      rows: Enum.map(rows, &decorate(&1, counts, runs)),
      usages: usage_summaries(),
      unused: unused_items(),
      contradicted: contradicted_items(),
      skills: skills()
    }
  end

  defp item_counts do
    Repo.all(
      from(item in Item,
        group_by: [item.kind, item.status],
        order_by: [asc: item.kind, asc: item.status],
        select: %{kind: item.kind, status: item.status, count: count(item.id)}
      )
    )
  end

  defp timeline do
    Repo.all(
      from(item in Item,
        group_by: [fragment("date(?)", item.inserted_at), item.kind, item.status],
        order_by: [desc: fragment("date(?)", item.inserted_at), asc: item.kind],
        limit: @maximum_timeline_groups,
        select: %{
          day: fragment("date(?)", item.inserted_at),
          kind: item.kind,
          status: item.status,
          count: count(item.id)
        }
      )
    )
    |> Enum.reverse()
  end

  defp coverage do
    used = from(usage in Usage, distinct: true, select: usage.knowledge_item_id)

    Repo.one(
      from(item in Item,
        left_join: used in subquery(used),
        on: used.knowledge_item_id == item.id,
        select: %{
          total: count(item.id),
          used: count(used.knowledge_item_id),
          project: filter(count(item.id), item.scope == "project"),
          global: filter(count(item.id), item.scope == "global")
        }
      )
    )
  end

  defp review_counts do
    Repo.all(
      from(candidate in Candidate,
        group_by: [candidate.kind, candidate.decision],
        order_by: [asc: candidate.kind, asc: candidate.decision],
        select: %{kind: candidate.kind, decision: candidate.decision, count: count(candidate.id)}
      )
    )
  end

  defp consolidations do
    Repo.all(
      from(job in ConsolidationJob,
        join: project in Project,
        on: project.id == job.project_id,
        left_join: revision in IndexRevision,
        on: revision.consolidation_job_id == job.id and revision.job_revision == job.revision,
        order_by: [desc: job.started_at, desc: job.id],
        limit: @maximum_rows,
        select: %{
          job: job,
          project_name: project.name,
          content_hash: revision.content_hash,
          recorded_at: revision.recorded_at
        }
      )
    )
  end

  defp accepted_candidates do
    from(candidate in Candidate, where: not is_nil(candidate.accepted_item_id))
  end

  defp lineage_rows do
    Repo.all(
      from(candidate in Candidate,
        join: job in Job,
        on: job.id == candidate.extraction_job_id,
        join: item in Item,
        on: item.id == candidate.accepted_item_id,
        join: project in Project,
        on: project.id == candidate.project_id,
        where: not is_nil(candidate.accepted_item_id),
        order_by: [desc: candidate.reviewed_at, desc: candidate.id],
        limit: @maximum_rows,
        select: %{
          candidate: candidate,
          item: item,
          project_name: project.name,
          source_run_id: job.scope_id
        }
      )
    )
  end

  defp usage_counts([]), do: %{}

  defp usage_counts(item_ids) do
    Repo.all(
      from(usage in Usage,
        where: usage.knowledge_item_id in ^item_ids,
        group_by: [usage.knowledge_item_id, usage.kind],
        select: %{item_id: usage.knowledge_item_id, kind: usage.kind, count: count(usage.id)}
      )
    )
    |> Enum.group_by(& &1.item_id, &{&1.kind, &1.count})
    |> Map.new(fn {item_id, values} -> {item_id, Map.new(values)} end)
  end

  defp usage_runs([]), do: %{}

  defp usage_runs(item_ids) do
    Repo.all(
      from(usage in Usage,
        where: usage.knowledge_item_id in ^item_ids,
        group_by: [usage.knowledge_item_id, usage.run_id],
        order_by: [desc: max(usage.occurred_at)],
        limit: @maximum_run_links,
        select: %{
          item_id: usage.knowledge_item_id,
          run_id: usage.run_id,
          occurred_at: max(usage.occurred_at)
        }
      )
    )
    |> Enum.group_by(& &1.item_id)
  end

  defp decorate(row, counts, runs) do
    Map.merge(row, %{
      usage_counts: Map.get(counts, row.item.id, %{}),
      runs: Map.get(runs, row.item.id, [])
    })
  end

  defp usage_summaries do
    rows =
      Repo.all(
        from(usage in Usage,
          join: item in Item,
          on: item.id == usage.knowledge_item_id,
          group_by: item.id,
          order_by: [desc: max(usage.occurred_at)],
          limit: @maximum_usage_rows,
          select: %{
            item: item,
            injected: filter(count(usage.id), usage.kind == "injected"),
            retrieved: filter(count(usage.id), usage.kind == "retrieved"),
            cited: filter(count(usage.id), usage.kind == "cited"),
            accepted: filter(count(usage.id), usage.kind == "accepted"),
            contradicted: filter(count(usage.id), usage.kind == "contradicted"),
            last_used_at: max(usage.occurred_at)
          }
        )
      )

    ranks = latest_ranks(Enum.map(rows, & &1.item.id))
    Enum.map(rows, &Map.put(&1, :current_rank, ranks[&1.item.id]))
  end

  defp latest_ranks([]), do: %{}

  defp latest_ranks(item_ids) do
    Repo.all(
      from(usage in Usage,
        where: usage.knowledge_item_id in ^item_ids and usage.kind == "retrieved",
        order_by: [desc: usage.occurred_at, desc: usage.id],
        limit: 1_000,
        select: %{item_id: usage.knowledge_item_id, evidence: usage.evidence_json}
      )
    )
    |> Enum.reduce(%{}, fn row, ranks ->
      Map.put_new(ranks, row.item_id, row.evidence["rank"])
    end)
  end

  defp unused_items do
    used = from(usage in Usage, select: usage.knowledge_item_id)

    Repo.all(
      from(item in Item,
        where: item.id not in subquery(used),
        order_by: [desc: item.inserted_at, desc: item.id],
        limit: @maximum_rows
      )
    )
  end

  defp contradicted_items do
    Repo.all(
      from(usage in Usage,
        join: item in Item,
        on: item.id == usage.knowledge_item_id,
        where: usage.kind == "contradicted",
        group_by: item.id,
        order_by: [desc: max(usage.occurred_at)],
        limit: @maximum_rows,
        select: %{item: item, count: count(usage.id), last_at: max(usage.occurred_at)}
      )
    )
  end

  defp skills do
    Repo.all(
      from(skill in SkillPackage,
        join: item in Item,
        on: item.id == skill.knowledge_item_id,
        order_by: [desc: skill.published_at, desc: skill.id],
        limit: @maximum_rows,
        select: %{skill: skill, item: item}
      )
    )
  end
end
