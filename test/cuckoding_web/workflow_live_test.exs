defmodule CuckodingWeb.WorkflowLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  import Cuckoding.BattleFixtures
  alias Cuckoding.{Battles, BrowserToken, Foundation, Repo, Workflows}

  setup do
    fixture()
  end

  defp path(board), do: "/arenas/#{board.arena_id}/tabulae/#{board.id}"

  defp params(view) do
    html = view |> render() |> LazyHTML.from_fragment()

    Map.new(~w(key base_revision arena_id tabula_id), fn name ->
      {name,
       html
       |> LazyHTML.query("#workflow-form input[name=#{name}]")
       |> LazyHTML.attribute("value")
       |> hd()}
    end)
  end

  test "Advanced dialog saves labels and keeps one Start with its frozen workflow", ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, path(ctx.board))
    assert has_element?(view, "#arena-advanced button", "Board columns")
    assert has_element?(view, "dialog#board-workflow[phx-hook=Dialog]:not([open])")
    assert has_element?(view, "#workflow-form[phx-auto-recover=recover]")

    labels =
      Map.merge(Workflows.labels(ctx.board.definition), %{
        "specs" => "Discovery",
        "todo" => "Ready",
        "review" => "Judge <script>literal</script>"
      })

    view |> form("#workflow-form", labels: labels) |> render_submit()
    assert has_element?(view, "#workflow-notice", "No work was started")
    assert has_element?(view, "#column-specs #heading-specs", "Discovery")
    assert has_element?(view, "#column-specs button[aria-label='Add task to Discovery']")
    assert has_element?(view, "#draft-column option[value=specs]", "Discovery")
    assert has_element?(view, "#draft-column option[value=todo]", "Ready")
    assert has_element?(view, "#brief-planning", "cards in Discovery")
    view |> element("button[aria-label='Edit First']") |> render_click()
    assert has_element?(view, "#draft-editor", "move this task to Ready")
    refute has_element?(view, "#board-workflow script")
    assert has_element?(view, "#workflow-history[phx-mounted*=ignore_attrs]")
    assert Workflows.current(ctx.board).revision == 1
    assert has_element?(view, "#arena-start:not([disabled])")
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.board.arena_id, ctx.board.id)
    assert battle.snapshot["workflow_revision"] == 1
    assert has_element?(view, "#battle-frozen-workflow", "Discovery")
    assert has_element?(view, "#workflow-busy", "Finish or Stop")

    view
    |> form("#workflow-form", labels: Map.put(labels, "specs", "Cannot change"))
    |> render_submit()

    assert Workflows.current(ctx.board).revision == 1
    {:ok, _} = Battles.stop(battle.id)

    {:ok, _} =
      Workflows.save_labels(
        Ecto.UUID.generate(),
        ctx.board.arena_id,
        ctx.board.id,
        1,
        Map.put(labels, "specs", "Later name")
      )

    assert has_element?(view, "#heading-specs", "Later name")
    assert has_element?(view, "#battle-frozen-workflow", "Discovery")
    refute has_element?(view, "#battle-frozen-workflow", "Later name")
    {:ok, again, _} = live(signed, path(ctx.board))
    assert has_element?(again, "#workflow-specs[value='Later name']")
    {:ok, arena_view, _} = live(signed, "/arenas/#{ctx.board.arena_id}")
    assert has_element?(arena_view, "#heading-specs", "Later name")
  end

  test "live changes preserve dirty names and stale submissions need explicit reload", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(path(ctx.board))
    view |> form("#workflow-form", labels: %{"specs" => "Keep my draft"}) |> render_change()
    Foundation.broadcast()
    assert has_element?(view, "#workflow-specs[value='Keep my draft']")
    old = params(view)
    labels = Map.put(Workflows.labels(ctx.board.definition), "specs", "Saved elsewhere")

    {:ok, _} =
      Workflows.save_labels(Ecto.UUID.generate(), ctx.board.arena_id, ctx.board.id, 0, labels)

    assert has_element?(view, "#workflow-specs[value='Keep my draft']")
    assert has_element?(view, "#workflow-form button[disabled]")
    view |> form("#workflow-form") |> render_submit(old)
    assert Workflows.current(ctx.board).revision == 1
    assert has_element?(view, "#workflow-specs[value='Keep my draft']")
    view |> element("#board-workflow button", "Reload saved names") |> render_click()
    assert has_element?(view, "#workflow-discard", "unsaved names")
    view |> element("#workflow-discard button", "Keep editing") |> render_click()
    assert has_element?(view, "#workflow-specs[value='Keep my draft']")
    view |> element("#board-workflow button", "Reload saved names") |> render_click()
    view |> element("#workflow-discard button", "Discard draft and reload") |> render_click()
    assert has_element?(view, "#workflow-specs[value='Saved elsewhere']")
    refute has_element?(view, "#workflow-discard")
  end

  test "browser unused-field metadata does not reject a valid column form", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(path(ctx.board))
    labels = Map.put(Workflows.labels(ctx.board.definition), "specs", "Mission brief")
    browser_labels = Map.put(labels, "_unused_todo", "")

    view
    |> with_target("#workflow-#{ctx.board.id}")
    |> render_click("change", Map.put(params(view), "labels", browser_labels))

    assert has_element?(view, "#workflow-specs[value='Mission brief']")
    refute has_element?(view, "#workflow-error")
    assert has_element?(view, "#workflow-form button:not([disabled])")

    view |> form("#workflow-form") |> render_submit()
    assert Workflows.current(ctx.board).revision == 1

    view
    |> with_target("#workflow-#{ctx.board.id}")
    |> render_click(
      "change",
      Map.put(params(view), "labels", Map.put(labels, "_unused_foreign", ""))
    )

    assert has_element?(view, "#workflow-error", "five different names")
    assert Workflows.current(ctx.board).revision == 1
  end

  test "foreign recovered forms and expired component sessions cannot save", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(path(ctx.board))
    labels = Map.put(Workflows.labels(ctx.board.definition), "specs", "Recovered draft")
    recovered = Map.put(params(view), "labels", labels)
    view |> with_target("#workflow-#{ctx.board.id}") |> render_click("recover", recovered)
    assert has_element?(view, "#workflow-specs[value='Recovered draft']")
    view |> form("#workflow-form") |> render_submit()
    assert Workflows.current(ctx.board).revision == 0
    view |> element("#board-workflow button", "Reload saved names") |> render_click()
    view |> element("#workflow-discard button", "Discard draft and reload") |> render_click()

    view
    |> form("#workflow-form", labels: labels)
    |> render_change(%{"tabula_id" => Ecto.UUID.generate()})

    refute has_element?(view, "#workflow-specs[value='Recovered draft']")
    assert has_element?(view, "#workflow-error", "draft is kept")
    assert Workflows.current(ctx.board).revision == 0
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#workflow-form", labels: labels) |> render_submit()
    assert_redirect(view, "/locked")
    assert Workflows.current(ctx.board).revision == 0
  end
end
