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

    Map.new(~w(key base_revision arena_id tabula_id team_revision_id), fn name ->
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
    assert has_element?(view, "#workflow-core-names[phx-mounted*=ignore_attrs]:not([open])")

    assert has_element?(
             view,
             "#board-workflow a[href='#{path(ctx.board)}/team']",
             "Edit this board's roles"
           )

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
    view |> element("#board-workflow button", "Reload saved workflow") |> render_click()
    assert has_element?(view, "#workflow-discard", "unsaved workflow")
    view |> element("#workflow-discard button", "Keep editing") |> render_click()
    assert has_element?(view, "#workflow-specs[value='Keep my draft']")
    view |> element("#board-workflow button", "Reload saved workflow") |> render_click()
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

  test "optional read stages save reordered roles and display automatic card progress", ctx do
    old = Cuckoding.TeamAssignments.assigned(ctx.board)

    roles =
      for name <- ["Research", "Risk check"],
          do:
            Cuckoding.Team.custom_role()
            |> Map.merge(%{"name" => name, "agent" => "codex", "model_id" => "test-id"})

    {:ok, _} =
      Cuckoding.Team.save(
        Ecto.UUID.generate(),
        old.id,
        Cuckoding.Team.editable(old) ++ roles,
        false,
        ctx.board
      )

    {:ok, view, _} = ctx.conn |> sign_in() |> live(path(ctx.board))
    view |> element("#board-workflow button", "+ Add stage") |> render_click()
    view |> element("#board-workflow button", "+ Add stage") |> render_click()
    view |> element("#board-workflow button[aria-label='Up Risk check']") |> render_click()
    view |> form("#workflow-form") |> render_submit()
    assert has_element?(view, "#workflow-notice", "No work was started")
    steps = Workflows.execution_stages(Workflows.current(ctx.board).definition)
    assert Enum.map(steps, & &1["name"]) == ["Risk check", "Research"]
    [first | _] = steps
    battle = start(ctx.board)

    Enum.reduce_while(1..12, battle, fn _, current ->
      if current.stage == first["key"] do
        {:halt, current}
      else
        {:ok, attempt} = Battles.claim_next(current.id)
        {:ok, next} = Battles.finish(attempt.id, attempt.claim_token, result(attempt))
        {:cont, next}
      end
    end)

    assert has_element?(view, "#column-#{first["key"]}", "First")
    refute has_element?(view, "#column-#{first["key"]} button[aria-label^='Add task']")
    assert has_element?(view, "#workflow-busy", "Finish or Stop")
    {:ok, _} = Battles.stop(battle.id)
    view |> element("#board-workflow button[aria-label='Remove Research']") |> render_click()
    view |> form("#workflow-form") |> render_submit()
    assert length(Workflows.execution_stages(Workflows.current(ctx.board).definition)) == 1

    assert length(
             Workflows.execution_stages(Battles.get(battle.id).snapshot["workflow_definition"])
           ) ==
             2

    team = Cuckoding.TeamAssignments.assigned(ctx.board)
    remaining_role = first["role"]

    unassigned =
      Enum.map(Cuckoding.Team.editable(team), fn role ->
        if role["id"] == remaining_role,
          do: Map.merge(role, %{"agent" => "", "model_id" => ""}),
          else: role
      end)

    {:ok, _} = Cuckoding.Team.save(Ecto.UUID.generate(), team.id, unassigned, false, ctx.board)

    assert has_element?(
             view,
             "#battle-blockers a[href='#{path(ctx.board)}/team#role-#{remaining_role}']",
             "Edit roles"
           )

    assert has_element?(view, "#battle-blockers", "this board's Team")
  end

  test "custom stage access defaults to read and explicit edits and placement are saved", ctx do
    old = Cuckoding.TeamAssignments.assigned(ctx.board)

    role =
      Cuckoding.Team.custom_role()
      |> Map.merge(%{"name" => "Polish", "agent" => "codex", "model_id" => "test-id"})

    {:ok, _} =
      Cuckoding.Team.save(
        Ecto.UUID.generate(),
        old.id,
        Cuckoding.Team.editable(old) ++ [role],
        false,
        ctx.board
      )

    {:ok, view, _} = ctx.conn |> sign_in() |> live(path(ctx.board))
    view |> element("#board-workflow button", "+ Add stage") |> render_click()
    html = view |> render() |> LazyHTML.from_fragment()

    [id] =
      html
      |> LazyHTML.query("#workflow-form input[name='steps[0][key]']")
      |> LazyHTML.attribute("value")

    assert has_element?(view, "#step-access-#{id} option[value=read][selected]")
    assert has_element?(view, "#step-position-#{id} option[value=before][selected]")

    view
    |> form("#workflow-form", steps: %{"0" => %{"access" => "write", "position" => "after"}})
    |> render_change()

    Foundation.broadcast()
    assert has_element?(view, "#step-access-#{id} option[value=write][selected]")
    view |> form("#workflow-form") |> render_submit()
    revision = Workflows.current(ctx.board)
    assert revision.definition["version"] == 4
    [step] = Workflows.execution_stages(revision.definition)
    assert step["access"] == "write" and step["position"] == "after"

    assert Enum.map(revision.definition["columns"], & &1["key"]) ==
             ~w(specs todo in_process) ++ [id] ++ ~w(review completed)

    assert has_element?(view, "#arena-start:not([disabled])")
    {:ok, again, _} = ctx.conn |> sign_in() |> live(path(ctx.board))
    assert has_element?(again, "#step-access-#{id} option[value=write][selected]")
    assert has_element?(again, "#step-position-#{id} option[value=after][selected]")
  end

  test "recovery retains unsaved added stages as text without authority", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(path(ctx.board))

    step = %{
      "key" => "step_" <> Ecto.UUID.generate(),
      "name" => "Recovered research",
      "role" => Ecto.UUID.generate(),
      "_unused_name" => ""
    }

    recovered =
      params(view)
      |> Map.put("labels", Workflows.labels(ctx.board.definition))
      |> Map.put("steps", %{"0" => step})

    view |> with_target("#workflow-#{ctx.board.id}") |> render_click("recover", recovered)
    assert has_element?(view, "input[value='Recovered research']")
    assert has_element?(view, "#workflow-form button[disabled]", "Save workflow")
    view |> form("#workflow-form") |> render_submit()
    assert Workflows.current(ctx.board).revision == 0
    assert has_element?(view, "input[value='Recovered research']")
  end

  test "foreign recovered forms and expired component sessions cannot save", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(path(ctx.board))
    labels = Map.put(Workflows.labels(ctx.board.definition), "specs", "Recovered draft")
    recovered = Map.put(params(view), "labels", labels)
    view |> with_target("#workflow-#{ctx.board.id}") |> render_click("recover", recovered)
    assert has_element?(view, "#workflow-specs[value='Recovered draft']")
    view |> form("#workflow-form") |> render_submit()
    assert Workflows.current(ctx.board).revision == 0
    view |> element("#board-workflow button", "Reload saved workflow") |> render_click()
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
