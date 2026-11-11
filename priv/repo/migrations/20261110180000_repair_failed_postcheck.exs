defmodule Boss.Repo.Migrations.RepairFailedPostcheck do
  use Ecto.Migration

  @review_or "OR (source.kind='merge_review' AND source.status='finished' AND json_extract(source.receipt,'$.report.verdict')='changes_requested') OR (source.kind='check' AND"
  @post_or "OR (source.kind='merge_review' AND source.status='finished' AND json_extract(source.receipt,'$.report.verdict')='changes_requested') OR (source.kind='post_check' AND source.status='failed' AND json_extract(source.receipt,'$.outcome')='checks_failed' AND json_extract(source.receipt,'$.cleanup')='group_empty' AND json_extract(source.receipt,'$.output_complete')=1) OR (source.kind='check' AND"
  @kind_list "source.kind='merge' OR source.kind='merge_review' OR source.kind IN ('check','review','timeout_check','checkpoint_check')"
  @kind_list_with_post "source.kind='merge' OR source.kind='merge_review' OR source.kind='post_check' OR source.kind IN ('check','review','timeout_check','checkpoint_check')"
  @immutable "OR (OLD.integration_intent!='{}' AND OLD.integration_intent!=NEW.integration_intent)"
  @immutable_successor """
  OR (OLD.integration_intent!='{}' AND OLD.integration_intent!=NEW.integration_intent AND NOT (
    NEW.status='integrating'
    AND json_extract(NEW.integration_intent,'$.base_commit')=json_extract(OLD.integration_intent,'$.candidate_commit')
    AND json_extract(NEW.integration_intent,'$.candidate_commit')!=json_extract(OLD.integration_intent,'$.candidate_commit')
    AND EXISTS (SELECT 1 FROM delivery_steps post WHERE post.delivery_id=NEW.id AND post.kind='post_check' AND post.status='failed'
      AND json_extract(post.receipt,'$.outcome')='checks_failed' AND json_extract(post.receipt,'$.cleanup')='group_empty'
      AND json_extract(post.receipt,'$.candidate_commit')=json_extract(OLD.integration_intent,'$.candidate_commit'))
    AND EXISTS (SELECT 1 FROM delivery_steps repair WHERE repair.delivery_id=NEW.id AND repair.kind='review' AND repair.status='finished'
      AND json_extract(repair.receipt,'$.report.verdict')='approved'
      AND json_extract(repair.input,'$.publication_base')=json_extract(OLD.integration_intent,'$.candidate_commit')
      AND json_extract(repair.input,'$.candidate_commit')=json_extract(NEW.integration_intent,'$.candidate_commit'))
  ))
  """

  def up do
    rewrite("delivery_resolution_lineage", [
      {@review_or, @post_or},
      {@kind_list, @kind_list_with_post}
    ])

    rewrite("delivery_immutable", [{@immutable, String.trim(@immutable_successor)}])
    extend_publication_evidence()
  end

  def down do
    rewrite("delivery_immutable", [{String.trim(@immutable_successor), @immutable}])

    rewrite("delivery_resolution_lineage", [
      {@post_or, @review_or},
      {@kind_list_with_post, @kind_list}
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
    JOIN delivery_steps post ON post.delivery_id=d.id AND post.kind='post_check' AND post.status='failed'
      AND json_extract(post.receipt,'$.outcome')='checks_failed'
    JOIN delivery_steps repair ON repair.delivery_id=d.id AND repair.kind='review' AND repair.status='finished'
      AND repair.number>post.number AND repair.cycle=d.cycle
      AND json_extract(repair.input,'$.publication_base')=json_extract(post.receipt,'$.candidate_commit')
      AND repair.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id AND kind='review')
      AND json_extract(repair.receipt,'$.report.verdict')='approved'
      AND json_array_length(repair.receipt,'$.report.issues')=0
    JOIN delivery_steps chk ON chk.id=json_extract(repair.input,'$.check_step_id') AND chk.delivery_id=d.id
      AND chk.status='finished' AND json_extract(chk.receipt,'$.exit_code')=0
      AND json_extract(chk.input,'$.candidate_commit')=json_extract(repair.input,'$.candidate_commit')
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
      "\nUNION ALL\nSELECT d.id, repair.id, repair.number, json_extract(repair.input,'$.candidate_commit'),\n      json_extract(repair.input,'$.publication_base'), json_extract(chk.input,'$.workspace')\n    FROM deliveries d\n    JOIN delivery_steps post ON post.delivery_id=d.id AND post.kind='post_check'"

    kept =
      case String.split(sql, marker, parts: 2) do
        [original, _] -> original
        _ -> raise "postcheck publication evidence is missing"
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
