defmodule Boss.Repo.Migrations.AllowCursorReviewer do
  use Ecto.Migration

  def up do
    rewrite_trigger("delivery_request_pin")
    rewrite_trigger("autopilot_insert")
    replace_delivery_check(
      "reviewer IN ('codex','claude')",
      "reviewer IN ('codex','claude','cursor')"
    )
  end

  def down do
    flush()

    case repo().query!("SELECT COUNT(*) FROM deliveries WHERE reviewer='cursor'").rows do
      [[0]] -> :ok
      _ -> raise "Refusing to discard Cursor reviewer history"
    end

    restore_trigger("autopilot_insert")
    restore_trigger("delivery_request_pin")

    replace_delivery_check(
      "reviewer IN ('codex','claude','cursor')",
      "reviewer IN ('codex','claude')"
    )
  end

  defp rewrite_trigger(name) do
    replace_trigger(name, "NOT IN ('codex','claude')", "NOT IN ('codex','claude','cursor')")
  end

  defp restore_trigger(name) do
    replace_trigger(name, "NOT IN ('codex','claude','cursor')", "NOT IN ('codex','claude')")
  end

  defp replace_trigger(name, needle, replacement) do
    flush()

    [[sql]] =
      repo().query!("SELECT sql FROM sqlite_schema WHERE type='trigger' AND name=?", [name]).rows

    if String.contains?(sql, needle) do
      execute("DROP TRIGGER #{name}")
      execute(String.replace(sql, needle, replacement, global: false))
    else
      raise "Missing #{name} reviewer boundary"
    end
  end

  defp replace_delivery_check(needle, replacement) do
    flush()
    database = repo()

    [[sql]] =
      database.query!("SELECT sql FROM sqlite_schema WHERE type='table' AND name='deliveries'").rows

    unless String.contains?(sql, needle), do: raise("Missing deliveries reviewer check")
    revised = String.replace(sql, needle, replacement, global: false)
    database.query!("PRAGMA writable_schema=ON")

    database.query!("UPDATE sqlite_schema SET sql=? WHERE type='table' AND name='deliveries'", [
      revised
    ])

    database.query!("PRAGMA writable_schema=RESET")

    [[current]] =
      database.query!("SELECT sql FROM sqlite_schema WHERE type='table' AND name='deliveries'").rows

    unless String.contains?(current, replacement), do: raise("Reviewer check was not updated")
  end
end
