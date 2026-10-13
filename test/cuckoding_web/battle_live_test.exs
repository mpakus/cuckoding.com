defmodule CuckodingWeb.BattleLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Cuckoding.{
    Battles,
    BrowserToken,
    Foundation,
    ProjectChecks,
    Repo,
    Tabulae,
    Team,
    TeamAssignments
  }

  setup do
    %{arena: arena, board: board, path: executable} =
      Cuckoding.PlanningFixtures.planning_fixture()

    models = Foundation.workspace().connection["models"]

    {:ok, _} =
      Foundation.check_codex(
        Ecto.UUID.generate(),
        Foundation.workspace().revision,
        executable,
        true
      )

    {:ok, probe} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(probe, %{
        "status" => "supported",
        "version" => Cuckoding.Codex.isolation_version()
      })

    {:ok, _} =
      Foundation.inspect_codex(Ecto.UUID.generate(), Foundation.workspace().revision, true)

    {:ok, inspect} = Foundation.claim()

    {:ok, _} =
      Foundation.finish(inspect, %{
        "status" => "checked",
        "authorization" => "chatgpt",
        "catalog_status" => "fresh",
        "models" => models
      })

    team = Team.current()

    roles =
      Enum.map(
        Team.editable(team),
        &Map.merge(&1, %{"agent" => "codex", "model_id" => "test-id"})
      )

    {:ok, team} = Team.save(Ecto.UUID.generate(), team.id, roles)

    {:ok, _} =
      TeamAssignments.adopt(
        Ecto.UUID.generate(),
        arena.id,
        board.id,
        TeamAssignments.assigned(board).id,
        team.id,
        true
      )

    check = %{
      "id" => Ecto.UUID.generate(),
      "name" => "Whitespace",
      "executable" => "git",
      "arguments" => ["diff", "--check"],
      "directory" => ".",
      "timeout_seconds" => 30
    }

    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), arena.id, 0, [check], true)
    task = Ecto.UUID.generate()

    attrs = %{
      "title" => "First task",
      "description" => "Implement the task",
      "criteria" => "Checks pass",
      "column" => "specs",
      "depends_on" => []
    }

    {:ok, _} = Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, task, 0, attrs)

    %{
      arena: arena,
      board: board,
      task: task,
      attrs: attrs,
      path: "/arenas/#{arena.id}/tabulae/#{board.id}"
    }
  end

  test "keyboard submission freezes one scope without checkboxes or a preview ceremony", ctx do
    %{conn: conn, path: path, arena: arena, board: board} = ctx
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, path)
    assert has_element?(view, "#arena-start[type=submit]:not([disabled])", "Start")
    assert has_element?(view, "#battle-start-form[phx-auto-recover=recover]")
    refute has_element?(view, "#battle-start-form input[type=checkbox]")
    assert has_element?(view, "#battle-start-details", "First task")
    assert has_element?(view, "#battle-start-details", "test-model")
    assert has_element?(view, "#battle-start-details", "git")
    assert has_element?(view, "#arena-start-help", "original checkout")
    assert has_element?(view, "#battle-check-scope", "single-process commands only")
    assert has_element?(view, "#battle-check-scope", "Mix/npm pipelines are not yet supported")
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(arena.id, board.id)
    assert battle.state == "running"
    assert has_element?(view, "#battle-activity", "Running")
    refute has_element?(view, "#battle-start-form")
    refute has_element?(view, "button", "Pause")
    refute has_element?(view, "button", "Retry")
    assert has_element?(view, "#battle-inspect[phx-mounted*=ignore_attrs]")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#battle-inspect", battle.id)
    assert Battles.latest(arena.id, board.id).id == battle.id
  end

  test "stale and recovered Start forms cannot reuse old authorization", ctx do
    %{conn: conn, path: path, arena: arena, board: board, task: task, attrs: attrs} = ctx
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, path)
    old = start_params(view)

    {:ok, _} =
      Tabulae.save(Ecto.UUID.generate(), arena.id, board.id, task, 1, %{
        attrs
        | "title" => "Changed task"
      })

    view |> with_target("#arena-battle") |> render_submit("start", old)
    assert Battles.latest(arena.id, board.id) == nil
    assert has_element?(view, "#battle-error", "scope changed")
    old = start_params(view)
    view |> with_target("#arena-battle") |> render_change("recover", old)
    assert has_element?(view, "#battle-error", "connection changed")
    view |> with_target("#arena-battle") |> render_submit("start", old)
    assert Battles.latest(arena.id, board.id) == nil

    {:ok, again, _} = live(signed, path)
    again |> with_target("#arena-battle") |> render_submit("start", start_params(view))
    assert Battles.latest(arena.id, board.id) == nil
    again |> form("#battle-start-form") |> render_submit()
    assert Battles.latest(arena.id, board.id).state == "running"
  end

  test "expired component sessions cannot Start or Stop", ctx do
    %{conn: conn, path: path, arena: arena, board: board} = ctx
    {:ok, view, _} = conn |> sign_in() |> live(path)
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#battle-start-form") |> render_submit()
    assert_redirect(view, "/locked")
    assert Battles.latest(arena.id, board.id) == nil

    {:ok, view, _} = conn |> sign_in() |> live(path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(arena.id, board.id)
    view |> element("#battle-stop") |> render_click()
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#battle-confirm-stop") |> render_click()
    assert_redirect(view, "/locked")
    assert Battles.get(battle.id).state == "running"
  end

  test "durable cards and public receipts survive reconnect while edits remain intact", ctx do
    %{conn: conn, path: path, arena: arena, board: board, task: task} = ctx
    signed = sign_in(conn)
    {:ok, view, _} = live(signed, path)
    view |> element("button[aria-label='Edit First task']") |> render_click()
    view |> form("#draft-form", title: "Unsaved title") |> render_change()
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(arena.id, board.id)
    assert has_element?(view, "#draft-title-input[value='Unsaved title']")
    assert has_element?(view, "#draft-form fieldset[disabled]")
    assert has_element?(view, "#draft-locked", "frozen")

    render_submit(
      view,
      "save",
      Map.merge(ctx.attrs, %{
        "task_id" => task,
        "tabula_id" => board.id,
        "revision" => "1",
        "title" => "Unsaved title"
      })
    )

    assert has_element?(view, "#draft-error", "cannot be edited")
    assert hd(Tabulae.tasks(board.id)).title == "First task"

    [projection] = Battles.tasks(battle.id)
    projection |> Ecto.Changeset.change(state: "review") |> Repo.update!()
    Foundation.broadcast()
    assert has_element?(view, "#column-review #task-#{task}")
    assert has_element?(view, "#draft-title-input[value='Unsaved title']")
    assert has_element?(view, "#draft-editor[phx-mounted*=ignore_attrs]")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#column-review #task-#{task}")

    again |> element("button", "New draft") |> render_click()
    again |> form("#draft-form", title: "Later work") |> render_submit()
    assert length(Tabulae.tasks(board.id)) == 2
    assert length(Battles.tasks(battle.id)) == 1
    assert has_element?(again, "#battle-progress", "0 / 1")
  end

  test "Stop confirms and waits for cleanup; restart attention never offers resume", ctx do
    %{conn: conn, path: path, arena: arena, board: board} = ctx
    {:ok, view, _} = conn |> sign_in() |> live(path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(arena.id, board.id)
    {:ok, _} = Battles.claim_next(battle.id)
    view |> with_target("#arena-battle") |> render_click("stop", %{"battle_id" => battle.id})
    assert Battles.get(battle.id).state == "running"
    view |> element("#battle-stop") |> render_click()
    assert has_element?(view, "#battle-stop-question", "Stop this battle?")
    view |> element("#battle-keep-running") |> render_click()
    assert Battles.get(battle.id).state == "running"
    view |> element("#battle-stop") |> render_click()
    view |> element("#battle-confirm-stop") |> render_click()
    assert Battles.get(battle.id).state == "stopping"
    assert has_element?(view, "#battle-activity", "waiting for owned worker cleanup")
    refute has_element?(view, "#battle-start-form")
    refute has_element?(view, "#battle-activity", "Stopped after")

    Battles.get(battle.id)
    |> Ecto.Changeset.change(state: "needs_attention", reason: "restart_uncertain")
    |> Repo.update!()

    Foundation.broadcast()
    assert has_element?(view, "#battle-activity", "will not replay")
    refute has_element?(view, "button", "Resume")
    refute has_element?(view, "#battle-start-form")
  end

  test "completed results name their local branch and distinguish a new battle", ctx do
    %{conn: conn, path: path, arena: arena, board: board} = ctx
    {:ok, view, _} = conn |> sign_in() |> live(path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(arena.id, board.id)
    reference = "refs/heads/ccoding/battles/#{battle.id}"

    battle
    |> Ecto.Changeset.change(
      state: "completed",
      context: %{"native_battle" => %{"reference" => reference}}
    )
    |> Repo.update!()

    Foundation.broadcast()
    assert has_element?(view, "#battle-result code", "ccoding/battles/#{battle.id}")
    refute has_element?(view, "#battle-result code", "refs/heads/")
    assert has_element?(view, "#battle-result", "original branch has not been merged")

    assert has_element?(
             view,
             "#battle-start-scope",
             "new battle from the current committed source"
           )

    assert has_element?(view, "#battle-inspect", battle.id)
  end

  test "Inspect escapes public summaries and shows selected receipts without raw payloads", ctx do
    %{conn: conn, path: path, arena: arena, board: board} = ctx
    {:ok, view, _} = conn |> sign_in() |> live(path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(arena.id, board.id)
    {:ok, attempt} = Battles.claim_next(battle.id)

    attempt
    |> Ecto.Changeset.change(
      state: "completed",
      result: %{
        "status" => "passed",
        "summary" => "<script>public summary</script>",
        "candidate_sha" => String.duplicate("a", 40),
        "checks" => [%{"id" => "check-fixture", "status" => "passed", "exit_code" => 0}],
        "raw_payload" => "PRIVATE-RAW-CANARY"
      }
    )
    |> Repo.update!()

    Foundation.broadcast()
    assert has_element?(view, "#battle-attempt-#{attempt.id}", "<script>public summary</script>")
    refute has_element?(view, "#battle-inspect script")
    assert has_element?(view, "#battle-attempt-#{attempt.id}", "check-fixture")
    assert has_element?(view, "#battle-attempt-#{attempt.id}", String.duplicate("a", 40))
    refute render(view) =~ "PRIVATE-RAW-CANARY"
  end

  test "oversized scope and failed final review offer concrete attention guidance", ctx do
    %{conn: conn, path: path, arena: arena, board: board} = ctx
    {:ok, view, _} = conn |> sign_in() |> live(path)
    {:ok, preview} = Battles.preview(arena.id, board.id)

    Phoenix.LiveView.send_update(view.pid, CuckodingWeb.BattleComponent,
      id: "arena-battle",
      preview: %{preview | blockers: ["prompt_scope_too_large"]}
    )

    assert has_element?(view, "#battle-blockers", "Shorten the descriptions or role instructions")
    assert has_element?(view, "#arena-start[disabled]")
    Foundation.broadcast()
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(arena.id, board.id)

    battle
    |> Ecto.Changeset.change(state: "needs_attention", reason: "final_review_changes_requested")
    |> Repo.update!()

    Foundation.broadcast()
    assert has_element?(view, "#battle-activity", "final Secutor review requested changes")
    assert has_element?(view, "#battle-activity", "completion has not been granted")
    refute has_element?(view, "#battle-result")
    refute has_element?(view, "#battle-start-form")
  end

  defp start_params(view) do
    html = view |> element("#battle-start-form") |> render()

    Map.new(~w(key fingerprint), fn name ->
      [_, value] = Regex.run(~r/name="#{name}" value="([^"]+)"/, html)
      {name, value}
    end)
  end
end
