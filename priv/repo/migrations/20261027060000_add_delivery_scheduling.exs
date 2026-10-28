defmodule Boss.Repo.Migrations.AddDeliveryScheduling do
  use Ecto.Migration
  @active "status IN ('planning','implementing','testing','reviewing','integrating')"
  @manual "status IN ('preparing','launching','running','stopping') OR cleanup='unknown'"

  def up do
    execute("""
    CREATE TABLE delivery_settings (
      id INTEGER PRIMARY KEY CHECK(id=1),
      max_parallel_tasks INTEGER NOT NULL CHECK(typeof(max_parallel_tasks)='integer' AND max_parallel_tasks BETWEEN 1 AND 3),
      version INTEGER NOT NULL CHECK(typeof(version)='integer' AND version>=0))
    """)

    execute("INSERT INTO delivery_settings VALUES(1,2,0)")
    # REPLACE may bypass DELETE triggers; these rows retain scheduling ownership.

    execute(
      "CREATE TRIGGER delivery_settings_insert BEFORE INSERT ON delivery_settings WHEN EXISTS(SELECT 1 FROM delivery_settings) BEGIN SELECT RAISE(ABORT, 'worker capacity cannot be replaced'); END"
    )

    execute("""
    CREATE TRIGGER delivery_steps_no_replace BEFORE INSERT ON delivery_steps
    WHEN EXISTS(SELECT 1 FROM delivery_steps WHERE id=NEW.id OR (delivery_id=NEW.delivery_id AND (number=NEW.number OR status='running')))
    BEGIN SELECT RAISE(ABORT, 'delivery evidence cannot be replaced'); END
    """)

    execute("""
    CREATE TRIGGER delivery_settings_update BEFORE UPDATE ON delivery_settings
    WHEN NEW.id!=OLD.id OR NEW.version!=OLD.version+1
      OR NEW.max_parallel_tasks < (SELECT COUNT(*) FROM deliveries WHERE #{@active})
    BEGIN SELECT RAISE(ABORT, 'invalid worker capacity change'); END
    """)

    execute(
      "CREATE TRIGGER delivery_settings_delete BEFORE DELETE ON delivery_settings BEGIN SELECT RAISE(ABORT, 'worker capacity is required'); END"
    )

    capacity_guards("(SELECT max_parallel_tasks FROM delivery_settings WHERE id=1)")

    for operation <- ["INSERT", "UPDATE"] do
      execute("""
      CREATE TRIGGER delivery_plan_scopes_#{String.downcase(operation)} BEFORE #{operation} ON delivery_steps
      WHEN NEW.kind='plan' AND NEW.status='finished' AND (
        EXISTS (SELECT 1 FROM json_tree(NEW.receipt) WHERE key IS NOT NULL GROUP BY parent,key HAVING COUNT(*)>1)
        OR         COALESCE(json_type(NEW.receipt,'$.report.file_scopes'),'null') NOT IN ('null','array')
        OR (json_type(NEW.receipt,'$.report.file_scopes')='array' AND (
          json_array_length(NEW.receipt,'$.report.file_scopes') NOT BETWEEN 1 AND 64
          OR EXISTS (SELECT 1 FROM json_each(NEW.receipt,'$.report.file_scopes') s WHERE
            s.type!='object' OR (SELECT COUNT(*) FROM json_each(s.value))!=2
            OR COALESCE(json_extract(s.value,'$.kind'),'') NOT IN ('file','directory')
            OR COALESCE(json_type(s.value,'$.path'),'')!='text'
            OR length(CAST(json_extract(s.value,'$.path') AS BLOB)) NOT BETWEEN 1 AND 1024
            OR json_extract(s.value,'$.path')!=trim(json_extract(s.value,'$.path'))
            OR instr(json_extract(s.value,'$.path'), char(0))>0
            OR json_extract(s.value,'$.path') GLOB '*[' || char(1) || '-' || char(31) || char(127) || ']*'
            OR instr(json_extract(s.value,'$.path'), char(92))>0
            OR instr(json_extract(s.value,'$.path'), '*')>0 OR instr(json_extract(s.value,'$.path'), '?')>0
            OR instr(json_extract(s.value,'$.path'), '[')>0 OR instr(json_extract(s.value,'$.path'), ']')>0
            OR instr(json_extract(s.value,'$.path'), '{')>0 OR instr(json_extract(s.value,'$.path'), '}')>0
            OR instr(json_extract(s.value,'$.path'), ':')>0
            OR instr('/' || json_extract(s.value,'$.path') || '/', '//')>0
            OR instr('/' || json_extract(s.value,'$.path') || '/', '/./')>0
            OR instr('/' || json_extract(s.value,'$.path') || '/', '/../')>0
            OR instr('/' || lower(json_extract(s.value,'$.path')) || '/', '/.git/')>0)
          OR (SELECT COUNT(*) FROM json_each(NEW.receipt,'$.report.file_scopes')) !=
             (SELECT COUNT(DISTINCT json_extract(value,'$.path')) FROM json_each(NEW.receipt,'$.report.file_scopes')))))
      BEGIN SELECT RAISE(ABORT, 'invalid predicted file scopes'); END
      """)
    end

    # SQLite folds ASCII only; Unicode predictions conservatively conflict.
    execute("""
    CREATE VIEW delivery_scope_conflicts AS
    SELECT DISTINCT incoming.id AS delivery_id, claimed.id AS blocker_id
    FROM deliveries incoming
    JOIN delivery_steps p ON p.delivery_id=incoming.id AND p.kind='plan' AND p.status='finished'
    JOIN deliveries claimed ON claimed.id!=incoming.id
      AND json_extract(claimed.intent,'$.git_common_dir')=json_extract(incoming.intent,'$.git_common_dir')
    JOIN delivery_steps peer ON peer.delivery_id=claimed.id AND peer.kind='plan' AND peer.status='finished'
    JOIN json_each(p.receipt,'$.report.file_scopes') a
    JOIN json_each(peer.receipt,'$.report.file_scopes') b
    WHERE incoming.#{@active} AND (claimed.#{@active} OR claimed.cleanup='unknown')
      AND json_type(p.receipt,'$.report.file_scopes')='array'
      AND json_type(peer.receipt,'$.report.file_scopes')='array'
      AND EXISTS (SELECT 1 FROM delivery_steps i WHERE i.delivery_id=claimed.id AND i.kind='implement')
      AND (
        length(CAST(json_extract(a.value,'$.path') AS BLOB))!=length(json_extract(a.value,'$.path'))
        OR length(CAST(json_extract(b.value,'$.path') AS BLOB))!=length(json_extract(b.value,'$.path'))
        OR lower(json_extract(a.value,'$.path'))=lower(json_extract(b.value,'$.path'))
        OR substr(lower(json_extract(a.value,'$.path')),1,length(json_extract(b.value,'$.path'))+1)=lower(json_extract(b.value,'$.path')) || '/'
        OR substr(lower(json_extract(b.value,'$.path')),1,length(json_extract(a.value,'$.path'))+1)=lower(json_extract(a.value,'$.path')) || '/')
    """)

    execute("""
    CREATE TRIGGER delivery_scope_admission BEFORE INSERT ON delivery_steps
    WHEN NEW.kind='implement' AND (
      EXISTS (SELECT 1 FROM deliveries WHERE cleanup='unknown')
      OR EXISTS (SELECT 1 FROM agent_runs WHERE cleanup='unknown')
      OR EXISTS (SELECT 1 FROM delivery_scope_conflicts WHERE delivery_id=NEW.delivery_id))
    BEGIN SELECT RAISE(ABORT, 'predicted file scope is held'); END
    """)
  end

  def down do
    if repo().query!("SELECT COUNT(*) FROM deliveries WHERE #{@active}").rows |> hd() |> hd() > 2,
      do: raise("Refusing to discard live scheduling evidence")

    if repo().query!("SELECT max_parallel_tasks FROM delivery_settings WHERE id=1").rows != [[2]],
      do: raise("Refusing to discard configured worker capacity")

    if repo().query!(
         "SELECT COUNT(*) FROM delivery_steps WHERE kind='plan' AND json_type(receipt,'$.report.file_scopes') IS NOT NULL"
       ).rows != [[0]],
       do: raise("Refusing to discard typed scope history")

    execute("DROP TRIGGER delivery_steps_no_replace")
    execute("DROP TRIGGER delivery_scope_admission")
    execute("DROP VIEW delivery_scope_conflicts")
    execute("DROP TRIGGER delivery_plan_scopes_insert")
    execute("DROP TRIGGER delivery_plan_scopes_update")
    capacity_guards("2")
    execute("DROP TABLE delivery_settings")
  end

  defp capacity_guards(capacity) do
    execute("DROP TRIGGER delivery_guard_insert")
    execute("DROP TRIGGER delivery_guard_update")

    for {operation, acquisition} <- [
          {"INSERT", "NEW.#{@active}"},
          {"UPDATE",
           "(NEW.#{@active} AND NOT (OLD.#{@active})) OR (NEW.status='integrating' AND OLD.status!='integrating')"}
        ] do
      execute("""
      CREATE TRIGGER delivery_guard_#{String.downcase(operation)} BEFORE #{operation} ON deliveries
      WHEN (#{acquisition}) AND (
        EXISTS (SELECT 1 FROM agent_runs WHERE #{@manual})
        OR EXISTS (SELECT 1 FROM deliveries d WHERE d.id!=NEW.id AND (d.cleanup='unknown' OR d.status='integrating'))
        OR (SELECT COUNT(*) FROM deliveries d WHERE d.id!=NEW.id AND d.#{@active})>=#{capacity}
        OR (NEW.status='integrating' AND EXISTS (SELECT 1 FROM deliveries d WHERE d.id!=NEW.id AND d.#{@active})))
      BEGIN SELECT RAISE(ABORT, 'execution capacity unavailable'); END
      """)
    end
  end
end
