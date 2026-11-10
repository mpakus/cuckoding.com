defmodule Boss.Repo.Migrations.RepairMergeConflicts do
  use Ecto.Migration

  def up do
    rewrite("delivery_resolution_lineage", [
      {"AND ((json_extract(source.receipt,'$.cleanup')='group_empty'",
       "AND ((source.kind='merge' AND source.status='failed' AND json_extract(source.receipt,'$.outcome')='merge_conflict' AND json_extract(source.receipt,'$.cleanup')='group_empty') OR (json_extract(source.receipt,'$.cleanup')='group_empty'"},
      {"OR (source.kind='check' AND",
       "OR (source.kind='merge' AND source.status='failed' AND json_extract(source.receipt,'$.outcome')='merge_conflict' AND json_extract(source.receipt,'$.cleanup')='group_empty') OR (source.kind='check' AND"},
      {"source.kind IN ('check','review','timeout_check','checkpoint_check')",
       "source.kind='merge' OR source.kind IN ('check','review','timeout_check','checkpoint_check')"}
    ])

    extend_publication_evidence()
  end

  def down do
    rewrite("delivery_resolution_lineage", [
      {"source.kind='merge' OR source.kind IN ('check','review','timeout_check','checkpoint_check')",
       "source.kind IN ('check','review','timeout_check','checkpoint_check')"},
      {"OR (source.kind='merge' AND source.status='failed' AND json_extract(source.receipt,'$.outcome')='merge_conflict' AND json_extract(source.receipt,'$.cleanup')='group_empty') OR (source.kind='check' AND",
       "OR (source.kind='check' AND"},
      {"AND ((source.kind='merge' AND source.status='failed' AND json_extract(source.receipt,'$.outcome')='merge_conflict' AND json_extract(source.receipt,'$.cleanup')='group_empty') OR (json_extract(source.receipt,'$.cleanup')='group_empty'",
       "AND ((json_extract(source.receipt,'$.cleanup')='group_empty'"}
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
    JOIN delivery_steps m ON m.delivery_id=d.id AND m.kind='merge' AND m.status='failed'
      AND json_extract(m.receipt,'$.outcome')='merge_conflict'
      AND json_extract(m.receipt,'$.cleanup')='group_empty'
    JOIN delivery_steps original ON original.id=json_extract(m.input,'$.original_review_step_id')
      AND original.delivery_id=d.id AND original.kind='review' AND original.status='finished'
      AND json_extract(original.receipt,'$.report.verdict')='approved'
      AND json_extract(original.input,'$.candidate_commit')=json_extract(m.input,'$.original_candidate')
    JOIN delivery_steps repair ON repair.delivery_id=d.id AND repair.kind='review' AND repair.status='finished'
      AND repair.number>m.number AND repair.cycle=d.cycle
      AND repair.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id AND kind='review')
      AND json_extract(repair.receipt,'$.report.verdict')='approved'
      AND json_array_length(repair.receipt,'$.report.issues')=0
      AND json_extract(repair.input,'$.publication_base')=json_extract(m.input,'$.target_commit')
      AND json_extract(repair.input,'$.original_base')=json_extract(d.intent,'$.base_commit')
      AND json_extract(repair.input,'$.candidate_commit')!=json_extract(m.input,'$.original_candidate')
      AND json_extract(repair.input,'$.candidate_commit')!=json_extract(m.input,'$.target_commit')
    JOIN delivery_steps chk ON chk.id=json_extract(repair.input,'$.check_step_id') AND chk.delivery_id=d.id
      AND chk.kind='check' AND chk.status='finished' AND chk.cycle=repair.cycle AND chk.number>m.number
      AND json_extract(chk.input,'$.candidate_commit')=json_extract(repair.input,'$.candidate_commit')
      AND json_extract(chk.receipt,'$.exit_code')=0
      AND json_extract(chk.receipt,'$.output_complete')=1
    JOIN delivery_steps plan ON plan.id=json_extract(repair.input,'$.plan_step_id') AND plan.delivery_id=d.id
      AND plan.kind='plan' AND plan.status='finished'
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
      "\nUNION ALL\nSELECT d.id, repair.id, repair.number, json_extract(repair.input,'$.candidate_commit'),"

    kept =
      case String.split(sql, marker, parts: 2) do
        [original, _] -> original
        _ -> raise "conflict repair publication evidence is missing"
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
        if String.contains?(current, needle) do
          String.replace(current, needle, replacement, global: false)
        else
          raise "Missing #{name} boundary #{needle}"
        end
      end)

    execute("DROP TRIGGER #{name}")
    execute(revised)
    flush()
  end
end
