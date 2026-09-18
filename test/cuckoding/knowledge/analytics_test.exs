defmodule Cuckoding.Knowledge.AnalyticsTest do
  use Cuckoding.DataCase, async: false

  alias Cuckoding.Knowledge.Analytics
  alias Cuckoding.Knowledge.Item
  alias Cuckoding.Projects

  test "growth and lineage projections stay bounded with 5,000 items" do
    suffix = System.unique_integer([:positive])
    root = Path.join(System.tmp_dir!(), "cuckoding-analytics-#{suffix}")
    repo = Path.join(root, "repo")
    workspace = Path.join(root, "workspace")
    File.mkdir_p!(repo)
    File.mkdir_p!(workspace)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, project} =
      Projects.register(%{
        name: "Analytics #{suffix}",
        repo_path: repo,
        default_branch: "main",
        workspace_root: workspace,
        port_range_start: 54_000,
        port_range_end: 54_100
      })

    now = Cuckoding.Clock.wall_now()

    1..5_000
    |> Enum.chunk_every(200)
    |> Enum.each(fn batch ->
      rows = Enum.map(batch, &item(&1, project.id, now))
      {count, nil} = Repo.insert_all(Item, rows)
      assert count == length(batch)
    end)

    growth = Analytics.growth()
    lineage = Analytics.lineage()

    assert growth.coverage.total == 5_000
    assert growth.coverage.used == 0
    assert Enum.sum(Enum.map(growth.item_counts, & &1.count)) == 5_000
    assert length(growth.timeline) <= 180
    assert lineage.total_lineages == 0
    assert length(lineage.unused) == 100
    assert lineage.rows == []
    assert lineage.usages == []
  end

  defp item(number, project_id, now) do
    id = Cuckoding.Identifier.generate()
    kind = Enum.at(~w(fact decision pattern recipe observation), rem(number, 5))
    hash = :crypto.hash(:sha256, "item-#{number}") |> Base.encode16(case: :lower)

    %{
      id: id,
      scope: "project",
      project_id: project_id,
      kind: kind,
      title: "Knowledge item #{number}",
      file_path: "#{plural(kind)}/item-#{number}.md",
      content_hash: hash,
      observed_hash: hash,
      sync_state: "synced",
      revision_source: "user",
      status: "project",
      version: 1,
      confidence: 1.0,
      valid_from: now,
      invalid_at: nil,
      supersedes_id: nil,
      triggers_json: [],
      evidence_json: %{"source" => "load-test"},
      produced_by_json: %{"runtime" => "fixture"},
      review_json: %{},
      reviewed_by: nil,
      reviewed_at: nil,
      inserted_at: now,
      updated_at: now
    }
  end

  defp plural("decision"), do: "decisions"
  defp plural("observation"), do: "observations"
  defp plural(kind), do: kind <> "s"
end
