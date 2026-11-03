unless Code.ensure_loaded?(Boss.Repo.Migrations.AddReviewRetries) do
  Code.require_file("20261031220000_add_review_retries.exs", __DIR__)
end

defmodule Boss.Repo.Migrations.AddCandidateRetries do
  use Ecto.Migration
  alias Boss.Repo.Migrations.AddReviewRetries

  def up do
    execute("""
    ALTER TABLE deliveries ADD COLUMN retry_candidate_commit TEXT CHECK (
      retry_candidate_commit IS NULL OR (
        retry_review_id IS NOT NULL AND length(retry_candidate_commit) IN (40,64)
        AND retry_candidate_commit NOT GLOB '*[^0-9a-f]*'))
    """)

    execute("""
    CREATE TRIGGER delivery_retry_candidate_immutable
    BEFORE UPDATE OF retry_candidate_commit ON deliveries
    WHEN NEW.retry_candidate_commit IS NOT OLD.retry_candidate_commit
    BEGIN SELECT RAISE(ABORT, 'delivery retry candidate is immutable'); END
    """)

    replace_guards(true)
  end

  def down do
    unless repo().query!(
             "SELECT COUNT(*) FROM deliveries WHERE retry_candidate_commit IS NOT NULL"
           ).rows ==
             [[0]],
           do: raise("Refusing to discard candidate retry history")

    replace_guards(false)
    execute("DROP TRIGGER delivery_retry_candidate_immutable")
    execute("ALTER TABLE deliveries DROP COLUMN retry_candidate_commit")
  end

  defp replace_guards(external?) do
    execute("DROP TRIGGER delivery_retry_source")
    execute("DROP TRIGGER delivery_retry_stage")
    execute(AddReviewRetries.source_guard(external?))
    execute(AddReviewRetries.stage_guard(external?))
  end
end
