defmodule Boss.Repo.Migrations.HardenMultiAgentRetriesAndAnalyticRouting do
  use Ecto.Migration

  @old_profile "AND json_type(s.input,'$.model_profile.model')='text'"
  @new_profile "AND (json_type(s.input,'$.model_profile.model')='text' OR (COALESCE(d.implementer,'codex') IN ('claude','cursor','opencode') AND COALESCE(json_type(s.input,'$.model_profile'),'null')='null'))"

  @old_implementer_scope "(COALESCE(d.implementer,'codex') NOT IN ('claude','cursor','opencode') OR NEW.kind NOT IN ('plan','implement','resolve'))"
  @new_implementer_scope "(COALESCE(d.implementer,'codex') NOT IN ('claude','cursor','opencode') OR NEW.kind NOT IN ('plan','implement'))"

  @old_review_retry "AND NEW.admitted_version=d.task_version+1 AND NEW.reviewer=d.reviewer"
  @new_review_retry "AND NEW.admitted_version=d.task_version+1 AND NEW.reviewer=d.reviewer AND NEW.implementer=d.implementer AND NEW.analytic=d.analytic"

  @old_exec_retry "AND NEW.reviewer=p.reviewer AND NEW.autonomy_version=p.autonomy_version"
  @new_exec_retry "AND NEW.reviewer=p.reviewer AND NEW.implementer=p.implementer AND NEW.analytic=p.analytic AND NEW.autonomy_version=p.autonomy_version"

  def up do
    for view <- ~w(execution_retry_sources checkpoint_retry_sources provider_retry_sources) do
      rewrite("view", view, @old_profile, @new_profile)
    end

    for trigger <- ~w(delivery_catalog_model delivery_model_profile) do
      rewrite("trigger", trigger, @old_implementer_scope, @new_implementer_scope)
    end

    rewrite("trigger", "delivery_retry_source", @old_review_retry, @new_review_retry)

    for trigger <- ~w(execution_retry_source checkpoint_source provider_recovery_source) do
      rewrite("trigger", trigger, @old_exec_retry, @new_exec_retry)
    end
  end

  def down do
    flush()

    case repo().query!("""
         SELECT COUNT(*)
         FROM deliveries d
         JOIN delivery_steps s ON s.id=d.retry_implementation_id
         WHERE d.execution_recovery_version=1
           AND COALESCE(json_type(s.input,'$.model_profile'),'null')='null'
         """).rows do
      [[0]] -> :ok
      _ -> raise "Refusing to discard non-Codex execution recovery history"
    end

    for trigger <- ~w(provider_recovery_source checkpoint_source execution_retry_source) do
      rewrite("trigger", trigger, @new_exec_retry, @old_exec_retry)
    end

    rewrite("trigger", "delivery_retry_source", @new_review_retry, @old_review_retry)

    for trigger <- ~w(delivery_model_profile delivery_catalog_model) do
      rewrite("trigger", trigger, @new_implementer_scope, @old_implementer_scope)
    end

    for view <- ~w(provider_retry_sources checkpoint_retry_sources execution_retry_sources) do
      rewrite("view", view, @new_profile, @old_profile)
    end
  end

  defp rewrite(type, name, needle, replacement) do
    flush()

    [[sql]] =
      repo().query!("SELECT sql FROM sqlite_schema WHERE type=? AND name=?", [type, name]).rows

    unless String.contains?(sql, needle),
      do: raise("Missing #{name} #{type} boundary")

    execute("DROP #{String.upcase(type)} #{name}")
    execute(String.replace(sql, needle, replacement, global: false))
    flush()
  end
end
