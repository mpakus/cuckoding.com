defmodule Boss.Repo.Migrations.RetargetMergeAfterDrift do
  use Ecto.Migration

  @old "AND NEW.number=r.number+1\n  AND r.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id)"
  @new """
  AND ((NEW.number=r.number+1 AND r.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id))
          OR EXISTS (SELECT 1 FROM delivery_steps failed WHERE failed.delivery_id=d.id AND failed.kind='merge_review' AND failed.status='failed' AND json_extract(failed.receipt,'$.outcome') IN ('target_changed','target_drift') AND json_extract(failed.receipt,'$.cleanup')='group_empty' AND failed.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id) AND NEW.number=failed.number+1))
  """

  def up do
    rewrite("merge_input", @old, String.trim(@new))
    extend_publication_evidence()
  end

  def down do
    rewrite("merge_input", String.trim(@new), @old)
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
    SELECT d.id, mr.id, mr.number, json_extract(mr.input,'$.candidate_commit'),
      json_extract(mr.input,'$.target_commit'), json_extract(m.receipt,'$.workspace')
    FROM deliveries d
    JOIN delivery_steps failed ON failed.delivery_id=d.id AND failed.kind='merge_review' AND failed.status='failed'
      AND json_extract(failed.receipt,'$.outcome') IN ('target_changed','target_drift')
    JOIN delivery_steps mr ON mr.delivery_id=d.id AND mr.kind='merge_review' AND mr.status='finished'
      AND mr.number>failed.number
      AND mr.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id AND kind='merge_review')
      AND json_extract(mr.receipt,'$.report.verdict')='approved'
      AND json_array_length(mr.receipt,'$.report.issues')=0
    JOIN delivery_steps m ON m.id=json_extract(mr.input,'$.merge_step_id') AND m.delivery_id=d.id AND m.status='finished'
    JOIN delivery_steps mc ON mc.id=json_extract(mr.input,'$.merge_check_step_id') AND mc.delivery_id=d.id AND mc.status='finished'
      AND json_extract(mc.receipt,'$.exit_code')=0
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
      "\nUNION ALL\nSELECT d.id, mr.id, mr.number, json_extract(mr.input,'$.candidate_commit'),"

    kept =
      case String.split(sql, marker, parts: 2) do
        [original, _] -> original
        _ -> raise "retarget publication evidence is missing"
      end

    execute("DROP VIEW delivery_publication_evidence")
    execute(kept)
    flush()
  end

  defp rewrite(name, needle, replacement) do
    flush()

    [[sql]] =
      repo().query!("SELECT sql FROM sqlite_schema WHERE type='trigger' AND name=?", [name]).rows

    unless String.contains?(sql, needle), do: raise("Missing #{name} boundary")

    execute("DROP TRIGGER #{name}")
    execute(String.replace(sql, needle, replacement, global: false))
    flush()
  end
end
