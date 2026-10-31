defmodule Boss.Repo.Migrations.AddReviewRetries do
  use Ecto.Migration

  def up do
    execute(
      "ALTER TABLE deliveries ADD COLUMN retry_review_id TEXT REFERENCES delivery_steps(id) ON DELETE RESTRICT"
    )

    execute("""
    CREATE TRIGGER delivery_retry_immutable BEFORE UPDATE OF retry_review_id ON deliveries
    WHEN NEW.retry_review_id IS NOT OLD.retry_review_id
    BEGIN SELECT RAISE(ABORT, 'delivery retry source is immutable'); END
    """)

    execute("""
    CREATE TRIGGER delivery_retry_source BEFORE INSERT ON deliveries
    WHEN NEW.retry_review_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM delivery_steps r JOIN deliveries d ON d.id=r.delivery_id
      JOIN delivery_steps c ON c.id=json_extract(r.input,'$.check_step_id') AND c.delivery_id=d.id
      JOIN delivery_steps p ON p.id=json_extract(r.input,'$.plan_step_id') AND p.delivery_id=d.id
      WHERE r.id=NEW.retry_review_id AND d.status='blocked' AND d.cleanup='group_empty'
      AND d.integration_intent='{}' AND d.integration_command_id IS NULL
      AND NEW.project_id=d.project_id AND NEW.task_id=d.task_id AND NEW.spec_revision_id=d.spec_revision_id
      AND NEW.admitted_version=d.task_version+1 AND NEW.reviewer=d.reviewer
      AND EXISTS (SELECT 1 FROM task_events e WHERE e.task_id=d.task_id
        AND e.command_id=d.id||':complete:blocked' AND e.action='delivery_progress'
        AND e.to_state='blocked' AND e.spec_revision_id=d.spec_revision_id AND e.version=NEW.admitted_version)
      AND NEW.check_config=d.check_config AND NEW.config_hash=d.config_hash
      AND r.kind='review' AND c.kind='check' AND p.kind='plan'
      AND r.status='finished' AND c.status='finished' AND p.status='finished'
      AND r.cycle=d.cycle AND c.cycle=d.cycle
      AND r.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id)
      AND #{passed("r")} AND #{passed("c")} AND #{passed("p")}
      AND json_extract(c.receipt,'$.output_complete')=1
      AND json_extract(r.receipt,'$.report.verdict')='changes_requested'
      AND json_type(r.receipt,'$.report.issues')='array' AND json_array_length(r.receipt,'$.report.issues')>0
      AND json_extract(r.input,'$.candidate_commit')=json_extract(c.input,'$.candidate_commit')
      AND json_extract(r.input,'$.original_base')=json_extract(d.intent,'$.base_commit')
      AND json_extract(r.input,'$.config_hash')=d.config_hash
      AND json_extract(c.input,'$.config_hash')=d.config_hash
      AND json_extract(p.input,'$.config_hash')=d.config_hash
      AND json_extract(r.input,'$.spec_revision_id')=d.spec_revision_id
      AND json_extract(c.input,'$.spec_revision_id')=d.spec_revision_id
      AND json_extract(p.input,'$.spec_revision_id')=d.spec_revision_id)
    BEGIN SELECT RAISE(ABORT, 'invalid rejected review source'); END
    """)

    execute("""
    CREATE TRIGGER delivery_retry_base BEFORE UPDATE OF intent ON deliveries
    WHEN NEW.retry_review_id IS NOT NULL AND NEW.intent!='{}' AND NOT EXISTS (
      SELECT 1 FROM delivery_steps r JOIN deliveries p ON p.id=r.delivery_id
      WHERE r.id=NEW.retry_review_id
      AND json_extract(NEW.intent,'$.base_commit')=json_extract(p.intent,'$.base_commit')
      AND json_extract(NEW.intent,'$.repo_path')=json_extract(p.intent,'$.repo_path')
      AND json_extract(NEW.intent,'$.git_common_dir')=json_extract(p.intent,'$.git_common_dir')
      AND json_extract(NEW.intent,'$.base_branch')=json_extract(p.intent,'$.base_branch'))
    BEGIN SELECT RAISE(ABORT, 'retry must retain original base'); END
    """)

    execute("""
    CREATE TRIGGER delivery_retry_plan BEFORE UPDATE ON delivery_steps
    WHEN NEW.kind='plan' AND NEW.status='finished' AND EXISTS (
      SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND retry_review_id IS NOT NULL)
    AND NOT EXISTS (
      SELECT 1 FROM deliveries d JOIN delivery_steps r ON r.id=d.retry_review_id
      JOIN delivery_steps p ON p.id=json_extract(r.input,'$.plan_step_id')
      WHERE d.id=NEW.delivery_id AND json_type(NEW.receipt,'$.report.acceptance')='array'
      AND json_array_length(NEW.receipt,'$.report.acceptance')=json_array_length(p.receipt,'$.report.acceptance')
      AND NOT EXISTS (SELECT 1 FROM json_each(p.receipt,'$.report.acceptance') old
        WHERE NOT EXISTS (SELECT 1 FROM json_each(NEW.receipt,'$.report.acceptance') fresh
          WHERE fresh.type='text' AND fresh.value=old.value)))
    BEGIN SELECT RAISE(ABORT, 'retry cannot weaken acceptance criteria'); END
    """)

    receipt_guards(true)

    execute("""
    CREATE TRIGGER delivery_retry_stage BEFORE INSERT ON delivery_steps
    WHEN (NEW.kind IN ('retry_snapshot','retry_check') OR
      (NEW.kind='implement' AND NEW.cycle IN (0,1) AND EXISTS (
        SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND retry_review_id IS NOT NULL)))
    AND NOT EXISTS (
      SELECT 1 FROM deliveries d JOIN delivery_steps r ON r.id=d.retry_review_id
      JOIN delivery_steps p ON p.delivery_id=d.id AND p.kind='plan' AND p.status='finished'
      JOIN delivery_steps previous ON previous.delivery_id=d.id
        AND previous.number=(SELECT MAX(number) FROM delivery_steps WHERE delivery_id=d.id)
      WHERE d.id=NEW.delivery_id AND NEW.number=previous.number+1
      AND json_extract(NEW.input,'$.source_review_id')=d.retry_review_id
      AND json_extract(NEW.input,'$.plan_step_id')=p.id
      AND ((NEW.kind='retry_snapshot' AND NEW.cycle=0 AND NEW.number=2 AND previous.id=p.id
        AND json_extract(NEW.input,'$.source_candidate_commit')=json_extract(r.input,'$.candidate_commit')
        AND json_extract(NEW.input,'$.run_workspace.base_commit')=json_extract(r.input,'$.candidate_commit')
        AND json_extract(NEW.input,'$.run_workspace.project_id')=CAST(d.project_id AS TEXT)
        AND json_extract(NEW.input,'$.run_workspace.repo_path')=json_extract(d.intent,'$.repo_path')
        AND json_extract(NEW.input,'$.run_workspace.git_common_dir')=json_extract(d.intent,'$.git_common_dir')
        AND json_extract(NEW.input,'$.run_workspace.base_branch')=json_extract(d.intent,'$.base_branch')
        AND length(json_extract(NEW.input,'$.check_id'))=36)
      OR (NEW.kind='retry_check' AND NEW.cycle=0 AND NEW.number=3
        AND previous.kind='retry_snapshot' AND previous.status='finished'
        AND json_extract(NEW.input,'$.snapshot_step_id')=previous.id
        AND json_extract(NEW.input,'$.workspace')=json_extract(previous.receipt,'$.workspace')
        AND json_extract(NEW.input,'$.candidate_commit')=json_extract(previous.receipt,'$.candidate_commit')
        AND json_extract(NEW.input,'$.config_hash')=d.config_hash)
      OR (NEW.kind='implement' AND NEW.cycle=1 AND NEW.number=4
        AND previous.kind='retry_check' AND previous.cycle=0
        AND json_extract(NEW.input,'$.parent_step_id')=previous.id
        AND json_extract(NEW.input,'$.workspace.base_commit')=json_extract(previous.input,'$.candidate_commit')
        AND json_extract(previous.receipt,'$.candidate_commit')=json_extract(previous.input,'$.candidate_commit')
        AND json_extract(previous.receipt,'$.output_complete')=1
        AND json_extract(previous.receipt,'$.cleanup')='group_empty'
        AND json_extract(previous.receipt,'$.exit_kind')='exit'
        AND json_extract(previous.receipt,'$.eof.stdout')=1 AND json_extract(previous.receipt,'$.eof.stderr')=1
        AND ((previous.status='finished' AND json_extract(previous.receipt,'$.exit_code')=0)
          OR (previous.status='failed' AND json_extract(previous.receipt,'$.outcome')='checks_failed'
            AND json_type(previous.receipt,'$.exit_code')='integer' AND json_extract(previous.receipt,'$.exit_code')!=0)))))
    BEGIN SELECT RAISE(ABORT, 'retry stage lineage mismatch'); END
    """)

    execute("""
    CREATE TRIGGER delivery_retry_prefix BEFORE INSERT ON delivery_steps
    WHEN NEW.kind='implement' AND EXISTS (
      SELECT 1 FROM deliveries WHERE id=NEW.delivery_id AND retry_review_id IS NOT NULL)
    AND NOT EXISTS (SELECT 1 FROM delivery_steps c WHERE c.delivery_id=NEW.delivery_id
      AND c.kind='retry_check' AND c.number=3 AND c.cycle=0
      AND c.status IN ('finished','failed') AND json_extract(c.receipt,'$.output_complete')=1
      AND json_extract(c.receipt,'$.cleanup')='group_empty'
      AND json_extract(c.receipt,'$.exit_kind')='exit'
      AND json_extract(c.receipt,'$.candidate_commit')=json_extract(c.input,'$.candidate_commit')
      AND length(json_extract(c.receipt,'$.output_hash'))=64
      AND json_extract(c.receipt,'$.eof.stdout')=1 AND json_extract(c.receipt,'$.eof.stderr')=1
      AND ((c.status='finished' AND json_extract(c.receipt,'$.exit_code')=0)
        OR (c.status='failed' AND json_extract(c.receipt,'$.outcome')='checks_failed'
          AND json_type(c.receipt,'$.exit_code')='integer' AND json_extract(c.receipt,'$.exit_code')!=0)))
    BEGIN SELECT RAISE(ABORT, 'retry requires fresh check prefix'); END
    """)
  end

  def down do
    unless repo().query!("SELECT COUNT(*) FROM deliveries WHERE retry_review_id IS NOT NULL").rows ==
             [[0]],
           do: raise("Refusing to discard review retry history")

    for trigger <-
          ~w(delivery_retry_immutable delivery_retry_source delivery_retry_base delivery_retry_plan delivery_retry_stage delivery_retry_prefix),
        do: execute("DROP TRIGGER #{trigger}")

    receipt_guards(false)
    execute("ALTER TABLE deliveries DROP COLUMN retry_review_id")
  end

  defp passed(step),
    do: """
    json_extract(#{step}.receipt,'$.cleanup')='group_empty'
    AND json_extract(#{step}.receipt,'$.exit_kind')='exit' AND json_extract(#{step}.receipt,'$.exit_code')=0
    AND json_extract(#{step}.receipt,'$.eof.stdout')=1 AND json_extract(#{step}.receipt,'$.eof.stderr')=1
    """

  defp receipt_guards(retry?) do
    kinds =
      "'plan','implement','snapshot','check','review','publish','post_check','merge','merge_check','merge_review'" <>
        if(retry?, do: ",'retry_snapshot','retry_check'", else: "")

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
end
