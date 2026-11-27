defmodule Boss.Repo.Migrations.PinPeerReviewPolicy do
  use Ecto.Migration

  @tables ~w(project_intakes autopilots delivery_requests deliveries)
  @order "ORDER BY priority LIMIT 1"
  # Selecting a route also verifies that this review names the writer of the checked
  # snapshot. Merge review follows the original candidate's approved review.
  @filter """
  AND (NEW.kind NOT IN ('review','merge_review') OR d.peer_review_version=0
    OR d.implementer!='codex' OR d.reviewer!='codex' OR EXISTS (
      SELECT 1 FROM delivery_steps chk
      JOIN delivery_steps snap ON snap.id=json_extract(chk.input,'$.snapshot_step_id')
      JOIN delivery_steps author ON author.id=json_extract(snap.input,'$.implementation_step_id')
      WHERE chk.id=CASE WHEN NEW.kind='review' THEN json_extract(NEW.input,'$.check_step_id')
        ELSE (SELECT json_extract(original.input,'$.check_step_id') FROM delivery_steps original
          WHERE original.id=json_extract(NEW.input,'$.original_review_step_id') AND original.delivery_id=d.id
            AND original.kind='review' AND original.status='finished'
            AND json_extract(original.receipt,'$.report.verdict')='approved') END
        AND chk.delivery_id=d.id AND snap.delivery_id=d.id AND author.delivery_id=d.id
        AND chk.kind='check' AND snap.kind='snapshot' AND author.kind='implement'
        AND chk.status='finished' AND snap.status='finished' AND author.status='finished'
        AND json_extract(chk.input,'$.candidate_commit')=json_extract(snap.receipt,'$.candidate_commit')
        AND (NEW.kind='merge_review' OR json_extract(NEW.input,'$.candidate_commit')=json_extract(chk.input,'$.candidate_commit'))
        AND chk.cycle=NEW.cycle AND snap.cycle=NEW.cycle AND author.cycle=NEW.cycle AND NEW.cycle=d.cycle
        AND json_extract(author.input,'$.model_profile.model')!=json_extract(routes.profile,'$.model')))
  """

  def up do
    for table <- @tables do
      execute("""
      ALTER TABLE #{table} ADD COLUMN peer_review_version INTEGER NOT NULL DEFAULT 0
        CHECK (peer_review_version=0 OR (peer_review_version=1 AND routing_version=2))
      """)

      execute("""
      CREATE TRIGGER #{table}_peer_review_immutable BEFORE UPDATE OF peer_review_version ON #{table}
      WHEN NEW.peer_review_version IS NOT OLD.peer_review_version
      BEGIN SELECT RAISE(ABORT, 'peer review policy is immutable'); END
      """)
    end

    guard("peer_review_intake_batch", "INSERT ON autopilots", """
    EXISTS (SELECT 1 FROM project_intakes i WHERE i.project_id=NEW.project_id
      AND i.command_id=NEW.command_id AND i.peer_review_version!=NEW.peer_review_version)
    """)

    guard("peer_review_batch_item", "INSERT ON autopilot_items", """
    EXISTS (SELECT 1 FROM autopilots b JOIN delivery_requests r ON r.id=NEW.request_id
      WHERE b.id=NEW.autopilot_id AND b.peer_review_version!=r.peer_review_version)
    """)

    for {trigger, event} <- [
          {"peer_review_loop_pass", "INSERT"},
          {"peer_review_loop_link",
           "UPDATE OF autopilot_id, parent_autopilot_id, next_autopilot_id"}
        ] do
      guard(trigger, event <> " ON autopilot_loop_configs", """
      EXISTS (SELECT 1 FROM autopilots b JOIN autopilots relative
        ON relative.id IN (NEW.parent_autopilot_id, NEW.next_autopilot_id)
        WHERE b.id=NEW.autopilot_id AND b.peer_review_version!=relative.peer_review_version)
      """)
    end

    guard("peer_review_delivery_source", "INSERT ON deliveries", """
    EXISTS (SELECT 1 FROM delivery_requests r WHERE r.task_id=NEW.task_id
      AND r.command_id=NEW.command_id AND r.peer_review_version!=NEW.peer_review_version)
    OR EXISTS (SELECT 1 FROM delivery_steps source JOIN deliveries parent ON parent.id=source.delivery_id
      WHERE source.id=coalesce(NEW.retry_source_check_id, NEW.retry_implementation_id, NEW.retry_review_id)
        AND parent.peer_review_version!=NEW.peer_review_version)
    """)

    rewrite_catalog_guard(@order, @filter <> @order)
  end

  def down do
    for table <- @tables do
      if repo().query!("SELECT 1 FROM #{table} WHERE peer_review_version=1 LIMIT 1").rows != [],
        do: raise("Refusing to discard the saved peer review policy")
    end

    rewrite_catalog_guard(@filter <> @order, @order)

    for name <-
          ~w(peer_review_delivery_source peer_review_loop_link peer_review_loop_pass peer_review_batch_item peer_review_intake_batch),
        do: execute("DROP TRIGGER #{name}")

    for table <- @tables do
      execute("DROP TRIGGER #{table}_peer_review_immutable")
      execute("ALTER TABLE #{table} DROP COLUMN peer_review_version")
    end
  end

  defp guard(name, event, mismatch) do
    execute("""
    CREATE TRIGGER #{name} BEFORE #{event}
    WHEN #{mismatch}
    BEGIN SELECT RAISE(ABORT, 'child must inherit peer review policy'); END
    """)
  end

  defp rewrite_catalog_guard(from, to) do
    flush()

    [[sql]] =
      repo().query!(
        "SELECT sql FROM sqlite_schema WHERE type='trigger' AND name='delivery_catalog_model'"
      ).rows

    unless length(:binary.matches(sql, from)) == 1,
      do: raise("Missing catalog model priority boundary")

    execute("DROP TRIGGER delivery_catalog_model")
    execute(String.replace(sql, from, to))
  end
end
