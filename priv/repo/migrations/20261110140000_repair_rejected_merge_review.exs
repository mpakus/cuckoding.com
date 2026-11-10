defmodule Boss.Repo.Migrations.RepairRejectedMergeReview do
  use Ecto.Migration

  @merge_or "OR (source.kind='merge' AND source.status='failed' AND json_extract(source.receipt,'$.outcome')='merge_conflict' AND json_extract(source.receipt,'$.cleanup')='group_empty') OR (source.kind='check' AND"
  @review_or "OR (source.kind='merge' AND source.status='failed' AND json_extract(source.receipt,'$.outcome')='merge_conflict' AND json_extract(source.receipt,'$.cleanup')='group_empty') OR (source.kind='merge_review' AND source.status='finished' AND json_extract(source.receipt,'$.report.verdict')='changes_requested') OR (source.kind='check' AND"
  @kind_list "source.kind='merge' OR source.kind IN ('check','review','timeout_check','checkpoint_check')"
  @kind_list_with_review "source.kind='merge' OR source.kind='merge_review' OR source.kind IN ('check','review','timeout_check','checkpoint_check')"

  def up do
    rewrite("delivery_resolution_lineage", [
      {@merge_or, @review_or},
      {@kind_list, @kind_list_with_review}
    ])

    extend_publication_evidence()
  end

  def down do
    rewrite("delivery_resolution_lineage", [
      {@review_or, @merge_or},
      {@kind_list_with_review, @kind_list}
    ])

    restore_publication_evidence()
  end

  defp extend_publication_evidence do
    flush()

    [[sql]] =
      repo().query!(
        "SELECT sql FROM sqlite_schema WHERE type='view' AND name='delivery_publication_evidence'"
      ).rows

    execute("DROP VIEW delivery_publication_evidence")

    execute("""
    #{sql}
    UNION ALL
    SELECT d.id, repair.id, repair.number, json_extract(repair.input,'$.candidate_commit'),
      json_extract(repair.input,'$.publication_base'), json_extract(chk.input,'$.workspace')
    FROM deliveries d
    JOIN delivery_steps m ON m.delivery_id=d.id AND m.kind='merge' AND m.status='finished'
    JOIN delivery_steps rejected ON rejected.delivery_id=d.id AND rejected.kind='merge_review'
      AND rejected.status='finished' AND json_extract(rejected.receipt,'$.report.verdict')='changes_requested'
    JOIN delivery_steps repair ON repair.delivery_id=d.id AND repair.kind='review' AND repair.status='finished'
      AND repair.number>rejected.number AND repair.cycle=d.cycle
      AND repair.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id AND kind='review')
      AND json_extract(repair.receipt,'$.report.verdict')='approved'
      AND json_array_length(repair.receipt,'$.report.issues')=0
      AND json_extract(repair.input,'$.publication_base')=json_extract(m.input,'$.target_commit')
      AND json_extract(repair.input,'$.candidate_commit')!=json_extract(m.receipt,'$.candidate_commit')
    JOIN delivery_steps chk ON chk.id=json_extract(repair.input,'$.check_step_id') AND chk.delivery_id=d.id
      AND chk.kind='check' AND chk.status='finished' AND chk.cycle=repair.cycle
      AND json_extract(chk.input,'$.candidate_commit')=json_extract(repair.input,'$.candidate_commit')
      AND json_extract(chk.receipt,'$.exit_code')=0
    WHERE (SELECT COUNT(*) FROM delivery_steps WHERE delivery_id=d.id AND kind='merge')=1
    """)

    flush()
  end

  defp restore_publication_evidence do
    flush()

    [[sql]] =
      repo().query!(
        "SELECT sql FROM sqlite_schema WHERE type='view' AND name='delivery_publication_evidence'"
      ).rows

    marker =
      "\nUNION ALL\nSELECT d.id, repair.id, repair.number, json_extract(repair.input,'$.candidate_commit'),\n      json_extract(repair.input,'$.publication_base'), json_extract(chk.input,'$.workspace')\n    FROM deliveries d\n    JOIN delivery_steps m ON m.delivery_id=d.id AND m.kind='merge' AND m.status='finished'"

    kept =
      case String.split(sql, marker, parts: 2) do
        [original, _] -> original
        _ -> raise "rejected merge review evidence is missing"
      end

    execute("DROP VIEW delivery_publication_evidence")
    execute(kept)
    flush()
  end

  defp rewrite(name, pairs) do
    flush()

    [[sql]] =
      repo().query!("SELECT sql FROM sqlite_schema WHERE type='trigger' AND name=?", [name]).rows

    revised =
      Enum.reduce(pairs, sql, fn {needle, replacement}, current ->
        if String.contains?(current, needle),
          do: String.replace(current, needle, replacement, global: false),
          else: raise("Missing #{name} boundary")
      end)

    execute("DROP TRIGGER #{name}")
    execute(revised)
    flush()
  end
end
