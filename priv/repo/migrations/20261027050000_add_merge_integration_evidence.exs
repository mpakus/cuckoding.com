defmodule Boss.Repo.Migrations.AddMergeIntegrationEvidence do
  use Ecto.Migration

  def up do
    replace_receipt_guards(true)

    execute("""
    CREATE VIEW delivery_publication_evidence AS
    SELECT d.id AS delivery_id, r.id AS review_step_id, r.number AS review_number,
      json_extract(r.input,'$.candidate_commit') AS candidate_commit,
      json_extract(d.intent,'$.base_commit') AS base_commit,
      json_extract(c.input,'$.workspace') AS candidate
    FROM deliveries d JOIN delivery_steps r ON r.delivery_id=d.id AND r.kind='review'
      JOIN delivery_steps c ON c.id=json_extract(r.input,'$.check_step_id') AND c.delivery_id=d.id
      JOIN delivery_steps p ON p.id=json_extract(r.input,'$.plan_step_id') AND p.delivery_id=d.id
    WHERE #{original_approval()}
      AND NOT EXISTS (SELECT 1 FROM delivery_steps m WHERE m.delivery_id=d.id AND m.kind='merge')
    UNION ALL
    SELECT d.id, mr.id, mr.number, json_extract(mr.input,'$.candidate_commit'),
      json_extract(m.input,'$.target_commit'), json_extract(m.receipt,'$.workspace')
    FROM deliveries d JOIN delivery_steps r ON r.delivery_id=d.id AND r.kind='review'
      JOIN delivery_steps c ON c.id=json_extract(r.input,'$.check_step_id') AND c.delivery_id=d.id
      JOIN delivery_steps p ON p.id=json_extract(r.input,'$.plan_step_id') AND p.delivery_id=d.id
      JOIN delivery_steps m ON m.delivery_id=d.id AND m.kind='merge'
      JOIN delivery_steps mc ON mc.delivery_id=d.id AND mc.kind='merge_check'
      JOIN delivery_steps mr ON mr.delivery_id=d.id AND mr.kind='merge_review'
    WHERE #{original_approval()} AND #{merge_input("m")}
      AND #{check_input("mc")} AND #{review_input("mr")}
      AND m.number=r.number+1 AND mc.number=m.number+1 AND mr.number=mc.number+1
      AND m.cycle=d.cycle AND mc.cycle=d.cycle AND mr.cycle=d.cycle
      AND m.status='finished' AND mc.status='finished' AND mr.status='finished'
      AND #{merge_receipt("m")} AND #{check_receipt("mc")} AND #{review_receipt("mr")}
      AND json_extract(mr.receipt,'$.report.verdict')='approved' AND #{empty_issues("mr")} AND #{criteria("mr")}
    """)

    for {kind, joins, condition, previous} <- [
          {"merge",
           "JOIN delivery_steps r ON r.id=json_extract(NEW.input,'$.original_review_step_id') AND r.delivery_id=d.id JOIN delivery_steps c ON c.id=json_extract(r.input,'$.check_step_id') AND c.delivery_id=d.id JOIN delivery_steps p ON p.id=json_extract(r.input,'$.plan_step_id') AND p.delivery_id=d.id",
           "#{original_approval()} AND #{merge_input("NEW")}", "r"},
          {"merge_check",
           "JOIN delivery_steps m ON m.id=json_extract(NEW.input,'$.merge_step_id') AND m.delivery_id=d.id",
           "m.kind='merge' AND m.status='finished' AND #{merge_receipt("m")} AND #{check_input("NEW")}",
           "m"},
          {"merge_review",
           "JOIN delivery_steps mc ON mc.id=json_extract(NEW.input,'$.merge_check_step_id') AND mc.delivery_id=d.id JOIN delivery_steps m ON m.id=json_extract(mc.input,'$.merge_step_id') AND m.delivery_id=d.id",
           "m.kind='merge' AND m.status='finished' AND mc.kind='merge_check' AND mc.status='finished' AND #{check_receipt("mc")} AND #{review_input("NEW")}",
           "mc"}
        ] do
      execute("""
      CREATE TRIGGER #{kind}_input BEFORE INSERT ON delivery_steps
      WHEN NEW.kind='#{kind}' AND NOT EXISTS (SELECT 1 FROM deliveries d #{joins}
        WHERE d.id=NEW.delivery_id AND d.status='integrating' AND d.integration_command_id IS NOT NULL
        AND d.integration_intent='{}' AND NEW.cycle=d.cycle
        AND NEW.number=#{previous}.number+1
        AND #{previous}.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id)
        AND #{condition})
      BEGIN SELECT RAISE(ABORT, 'integration stage lineage mismatch'); END
      """)
    end

    for {kind, condition} <- [
          {"merge", merge_receipt("NEW")},
          {"merge_check", check_receipt("NEW")},
          {"merge_review", review_receipt("NEW")}
        ] do
      execute("""
      CREATE TRIGGER #{kind}_receipt BEFORE UPDATE ON delivery_steps
      WHEN NEW.kind='#{kind}' AND NEW.status='finished' AND NOT (COALESCE((#{condition}),0))
      BEGIN SELECT RAISE(ABORT, 'integration receipt mismatch'); END
      """)
    end

    execute("""
    CREATE TRIGGER delivery_integration_evidence BEFORE UPDATE OF integration_intent ON deliveries
    WHEN OLD.integration_intent='{}' AND NEW.integration_intent!='{}' AND NOT EXISTS (
      SELECT 1 FROM delivery_publication_evidence e WHERE e.delivery_id=NEW.id
      AND NEW.status='integrating' AND NEW.integration_command_id IS NOT NULL
      AND json_extract(NEW.integration_intent,'$.delivery_id')=NEW.id
      AND json_extract(NEW.integration_intent,'$.base_commit')=e.base_commit
      AND json_extract(NEW.integration_intent,'$.candidate_commit')=e.candidate_commit
      AND json_extract(NEW.integration_intent,'$.candidate')=e.candidate
      AND json_extract(NEW.integration_intent,'$.repo_path')=json_extract(NEW.intent,'$.repo_path')
      AND json_extract(NEW.integration_intent,'$.base_branch')=json_extract(NEW.intent,'$.base_branch'))
    BEGIN SELECT RAISE(ABORT, 'integration requires current approval'); END
    """)

    execute("""
    CREATE TRIGGER publication_review_pin BEFORE INSERT ON delivery_steps
    WHEN NEW.kind='publish' AND NOT EXISTS (
      SELECT 1 FROM deliveries d JOIN delivery_publication_evidence e ON e.delivery_id=d.id
      WHERE d.id=NEW.delivery_id AND d.status='integrating' AND d.integration_command_id IS NOT NULL
      AND NEW.cycle=d.cycle AND NEW.number=e.review_number+1
      AND json_extract(NEW.input,'$.review_step_id')=e.review_step_id
      AND json_extract(NEW.input,'$.intent')=d.integration_intent
      AND json_extract(d.integration_intent,'$.base_commit')=e.base_commit
      AND json_extract(d.integration_intent,'$.candidate_commit')=e.candidate_commit)
    BEGIN SELECT RAISE(ABORT, 'publication requires exact review'); END
    """)

    execute("""
    CREATE TRIGGER delivery_ready_report BEFORE UPDATE ON deliveries
    WHEN NEW.status='ready_to_merge' AND NOT EXISTS (
      SELECT 1 FROM delivery_publication_evidence e WHERE e.delivery_id=NEW.id)
    BEGIN SELECT RAISE(ABORT, 'ready requires valid approved report'); END
    """)

    execute("""
    CREATE TRIGGER delivery_done_lineage BEFORE UPDATE ON deliveries
    WHEN NEW.status='done' AND NOT EXISTS (
      SELECT 1 FROM delivery_publication_evidence e JOIN delivery_steps pub
        ON pub.delivery_id=e.delivery_id AND pub.kind='publish' AND pub.status='finished'
      JOIN delivery_steps post ON post.delivery_id=e.delivery_id AND post.kind='post_check' AND post.status='finished'
      WHERE e.delivery_id=NEW.id AND json_extract(pub.input,'$.review_step_id')=e.review_step_id
        AND json_extract(pub.input,'$.intent')=NEW.integration_intent
        AND json_extract(post.input,'$.intent')=NEW.integration_intent
        AND json_extract(post.input,'$.publish_step_id')=pub.id
        AND json_extract(NEW.integration_intent,'$.base_commit')=e.base_commit
        AND json_extract(NEW.integration_intent,'$.candidate_commit')=e.candidate_commit)
    BEGIN SELECT RAISE(ABORT, 'done requires exact integration lineage'); END
    """)
  end

  def down do
    if repo().query!(
         "SELECT COUNT(*) FROM delivery_steps WHERE kind IN ('merge','merge_check','merge_review')"
       ).rows != [[0]],
       do: raise("Refusing to discard merge integration evidence")

    for name <-
          ~w(merge_input merge_check_input merge_review_input merge_receipt merge_check_receipt merge_review_receipt delivery_integration_evidence publication_review_pin delivery_done_lineage delivery_ready_report),
        do: execute("DROP TRIGGER #{name}")

    execute("DROP VIEW delivery_publication_evidence")
    replace_receipt_guards(false)
  end

  defp replace_receipt_guards(merge?) do
    kinds =
      "'plan','implement','snapshot','check','review','publish','post_check'" <>
        if(merge?, do: ",'merge','merge_check','merge_review'", else: "")

    for operation <- ["INSERT", "UPDATE"] do
      name = "delivery_step_receipt_#{String.downcase(operation)}"
      execute("DROP TRIGGER #{name}")

      execute("""
      CREATE TRIGGER #{name} BEFORE #{operation} ON delivery_steps
      WHEN NEW.cycle NOT BETWEEN 0 AND 3 OR NEW.number NOT BETWEEN 1 AND 20
        OR NEW.kind NOT IN (#{kinds}) OR NEW.status NOT IN ('running','finished','failed','cancelled','interrupted')
        OR (NEW.status!='running' AND (json_extract(NEW.receipt,'$.status') IS NOT NEW.status
          OR COALESCE(json_extract(NEW.receipt,'$.cleanup'),'') NOT IN ('group_empty','not_started','unknown')))
      BEGIN SELECT RAISE(ABORT, 'invalid delivery step receipt'); END
      """)
    end
  end

  defp original_approval do
    """
    r.status='finished' AND c.kind='check' AND c.status='finished' AND p.kind='plan' AND p.status='finished'
    AND r.cycle=d.cycle AND c.cycle=d.cycle AND json_extract(r.receipt,'$.report.verdict')='approved'
    AND #{process_passed("r")} AND #{process_passed("c")} AND #{process_passed("p")} AND #{empty_issues("r")}
    AND json_extract(r.input,'$.candidate_commit')=json_extract(c.input,'$.candidate_commit')
    AND json_extract(r.input,'$.config_hash')=d.config_hash AND json_extract(c.input,'$.config_hash')=d.config_hash
    AND json_extract(r.input,'$.original_base')=json_extract(d.intent,'$.base_commit')
    AND json_extract(c.receipt,'$.output_complete')=1
    AND r.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id AND kind='review')
    AND #{criteria("r")}
    """
  end

  defp criteria(review) do
    """
    json_array_length(p.receipt,'$.report.acceptance') BETWEEN 1 AND 20
    AND json_array_length(#{review}.receipt,'$.report.acceptance')=json_array_length(p.receipt,'$.report.acceptance')
    AND NOT EXISTS (SELECT 1 FROM json_each(p.receipt,'$.report.acceptance') a
      WHERE NOT EXISTS (SELECT 1 FROM json_each(#{review}.receipt,'$.report.acceptance') b
        WHERE json_extract(b.value,'$.criterion')=a.value AND json_extract(b.value,'$.status')='passed'))
    """
  end

  defp merge_input(m) do
    """
    json_extract(#{m}.input,'$.original_review_step_id')=r.id
    AND json_extract(#{m}.input,'$.original_check_step_id')=c.id
    AND json_extract(#{m}.input,'$.plan_step_id')=p.id
    AND json_extract(#{m}.input,'$.original_candidate')=json_extract(r.input,'$.candidate_commit')
    AND json_extract(#{m}.input,'$.original_base')=json_extract(d.intent,'$.base_commit')
    AND json_extract(#{m}.input,'$.config_hash')=d.config_hash
    AND json_extract(#{m}.input,'$.spec_revision_id')=d.spec_revision_id
    AND #{sha("json_extract(#{m}.input,'$.target_commit')")}
    AND json_extract(#{m}.input,'$.target_commit')!=json_extract(#{m}.input,'$.original_base')
    AND json_extract(#{m}.input,'$.target_commit')!=json_extract(#{m}.input,'$.original_candidate')
    AND json_type(#{m}.input,'$.workspace.run_workspace')='object'
    AND json_extract(#{m}.input,'$.workspace.run_workspace')=json_extract(c.input,'$.workspace.run_workspace')
    AND json_extract(#{m}.input,'$.workspace.check_id')!=json_extract(c.input,'$.workspace.check_id')
    AND json_extract(#{m}.input,'$.workspace.path')!=json_extract(c.input,'$.workspace.path')
    AND json_extract(#{m}.input,'$.workspace.ref')!=json_extract(c.input,'$.workspace.ref')
    """
  end

  defp check_input(c) do
    """
    json_extract(#{c}.input,'$.merge_step_id')=m.id
    AND json_extract(#{c}.input,'$.candidate_commit')=json_extract(m.receipt,'$.candidate_commit')
    AND json_extract(#{c}.input,'$.workspace')=json_extract(m.receipt,'$.workspace')
    AND json_extract(#{c}.input,'$.target_commit')=json_extract(m.input,'$.target_commit')
    AND json_extract(#{c}.input,'$.config_hash')=d.config_hash
    AND json_extract(#{c}.input,'$.spec_revision_id')=d.spec_revision_id
    """
  end

  defp review_input(r) do
    """
    #{check_input("mc")}
    AND json_extract(#{r}.input,'$.merge_step_id')=m.id
    AND json_extract(#{r}.input,'$.merge_check_step_id')=mc.id
    AND json_extract(#{r}.input,'$.original_review_step_id')=json_extract(m.input,'$.original_review_step_id')
    AND json_extract(#{r}.input,'$.plan_step_id')=json_extract(m.input,'$.plan_step_id')
    AND json_extract(#{r}.input,'$.candidate_commit')=json_extract(mc.input,'$.candidate_commit')
    AND json_extract(#{r}.input,'$.target_commit')=json_extract(m.input,'$.target_commit')
    AND json_extract(#{r}.input,'$.original_base')=json_extract(d.intent,'$.base_commit')
    AND json_extract(#{r}.input,'$.config_hash')=d.config_hash
    AND json_extract(#{r}.input,'$.spec_revision_id')=d.spec_revision_id
    AND json_extract(#{r}.input,'$.output_hash')=json_extract(mc.receipt,'$.output_hash')
    AND length(json_extract(#{r}.input,'$.input_hash'))=64
    """
  end

  defp merge_receipt(m) do
    """
    json_extract(#{m}.receipt,'$.cleanup')='group_empty'
    AND #{sha("json_extract(#{m}.receipt,'$.candidate_commit')")}
    AND json_extract(#{m}.receipt,'$.candidate_commit')!=json_extract(#{m}.input,'$.target_commit')
    AND json_extract(#{m}.receipt,'$.candidate_commit')!=json_extract(#{m}.input,'$.original_candidate')
    AND json_extract(#{m}.receipt,'$.workspace')=json_extract(#{m}.input,'$.workspace')
    """
  end

  defp check_receipt(c) do
    """
    #{process_passed(c)} AND json_extract(#{c}.receipt,'$.candidate_commit')=json_extract(#{c}.input,'$.candidate_commit')
    AND json_extract(#{c}.receipt,'$.output_complete')=1 AND length(json_extract(#{c}.receipt,'$.output_hash'))=64
    """
  end

  defp review_receipt(r) do
    """
    #{process_passed(r)} AND json_extract(#{r}.receipt,'$.candidate_commit')=json_extract(#{r}.input,'$.candidate_commit')
    AND json_extract(#{r}.receipt,'$.report.verdict') IN ('approved','changes_requested','needs_spec_revision')
    AND (json_extract(#{r}.receipt,'$.report.verdict')!='approved' OR (#{empty_issues(r)}))
    """
  end

  defp empty_issues(r),
    do:
      "json_type(#{r}.receipt,'$.report.issues')='array' AND json_array_length(#{r}.receipt,'$.report.issues')=0"

  defp process_passed(s),
    do:
      "json_extract(#{s}.receipt,'$.cleanup')='group_empty' AND json_extract(#{s}.receipt,'$.exit_kind')='exit' AND json_extract(#{s}.receipt,'$.exit_code')=0 AND json_extract(#{s}.receipt,'$.eof.stdout')=1 AND json_extract(#{s}.receipt,'$.eof.stderr')=1"

  defp sha(expression),
    do: "length(#{expression}) IN (40,64) AND #{expression} NOT GLOB '*[^0-9a-f]*'"
end
