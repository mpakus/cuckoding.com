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
    assert has_element?(view, "#battle-capacity-scope", "Up to two Arenas")
    assert has_element?(view, "#battle-capacity-scope", "sequentially")
    assert has_element?(view, "#arena-start-help", "original checkout")
    assert has_element?(view, "#battle-command-scope", "single-process commands only")
    assert has_element?(view, "#battle-command-scope", "Mix/npm pipelines are not yet supported")
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(arena.id, board.id)
    assert battle.state == "running"
    assert has_element?(view, "#battle-activity", "Running")
    refute has_element?(view, "#battle-start-form")
    assert has_element?(view, "#battle-pause[type=button]", "Pause")
    refute has_element?(view, "button", "Retry")
    assert has_element?(view, "#battle-inspect[phx-mounted*=ignore_attrs]")
    {:ok, again, _} = live(signed, path)
    assert has_element?(again, "#battle-inspect", battle.id)
    assert Battles.latest(arena.id, board.id).id == battle.id
  end

  test "Start needs task criteria but no separate project-check setup", ctx do
    {:ok, _} = ProjectChecks.save(Ecto.UUID.generate(), ctx.arena.id, 1, [], true)
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    assert has_element?(view, "#arena-start[type=submit]:not([disabled])", "Start")
    assert has_element?(view, "#battle-check-scope", "Verification belongs in each task")
    refute has_element?(view, "#battle-command-scope")
    refute has_element?(view, "#battle-blockers")
    assert has_element?(view, "#battle-start-details", "no command tests will run")
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    assert battle.snapshot["checks"] == []
    assert hd(battle.snapshot["tasks"])["criteria"] == ctx.attrs["criteria"]
  end

  test "Pause and Resume survive reconnect, reject stale controls and preserve unsaved text",
       ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> element("button[aria-label='Edit First task']") |> render_click()
    view |> form("#draft-form", title: "Keep this draft") |> render_change()
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    pause = control_params(view, "#battle-pause")
    view |> element("#battle-pause") |> render_click()
    assert Battles.get(battle.id).state == "paused"
    assert has_element?(view, "#battle-resume[type=button]", "Resume")
    assert has_element?(view, "#battle-pause-help", "original deadline")
    assert has_element?(view, "#draft-title-input[value='Keep this draft']")
    assert has_element?(view, "#draft-form fieldset[disabled]")
    old_resume = control_params(view, "#battle-resume")
    {:ok, again, _} = live(signed, ctx.path)
    assert has_element?(again, "#battle-activity", "Paused")
    again |> with_target("#arena-battle") |> render_click("resume", old_resume)
    assert Battles.get(battle.id).state == "paused"
    assert has_element?(again, "#battle-error", "control changed")
    again |> element("#battle-resume") |> render_click()
    assert Battles.get(battle.id).state == "running"
    view |> with_target("#arena-battle") |> render_click("pause", pause)
    assert Battles.get(battle.id).state == "running"
    assert Battles.get(battle.id).deadline_at == battle.deadline_at
  end

  test "Pausing explains pending work and Stop remains available", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    {:ok, _} = Battles.claim_next(battle.id)
    view |> element("#battle-pause") |> render_click()
    assert has_element?(view, "#battle-pause-status", "current stage is finishing")
    refute has_element?(view, "#battle-resume")
    view |> element("#battle-stop") |> render_click()
    view |> element("#battle-confirm-stop") |> render_click()
    assert Battles.get(battle.id).state == "stopping"
    refute has_element?(view, "#battle-resume")
  end

  test "recovered checkpoint explains Resume and rejects pre-restart controls", ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> element("button[aria-label='Edit First task']") |> render_click()
    view |> form("#draft-form", title: "Retain my draft after restart") |> render_change()
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    old = control_params(view, "#battle-pause")
    {:ok, [recovered]} = Battles.recover()
    assert has_element?(view, "#battle-recovery-status[role=status]", "Paused after restart")
    assert has_element?(view, "#battle-recovery-status", "No work has been replayed")
    assert has_element?(view, "#battle-resume[type=button]", "Resume")
    assert has_element?(view, "#draft-title-input[value='Retain my draft after restart']")
    view |> with_target("#arena-battle") |> render_click("resume", old)
    assert Battles.get(battle.id).state == "paused"
    assert has_element?(view, "#battle-error", "control changed")
    stale = control_params(view, "#battle-resume")
    {:ok, again, _} = live(signed, ctx.path)
    again |> with_target("#arena-battle") |> render_click("resume", stale)
    assert Battles.get(battle.id) == recovered
    again |> element("#battle-resume") |> render_click()
    assert Battles.get(battle.id).state == "running"
    assert Battles.get(battle.id).reason == nil
    refute has_element?(again, "#battle-recovery-status")
    assert Battles.attempts(battle.id) == []
  end

  test "expired sessions cannot Resume a recovered checkpoint", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    {:ok, [recovered]} = Battles.recover()
    assert has_element?(view, "#battle-recovery-status")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#battle-resume") |> render_click()
    assert_redirect(view, "/locked")
    assert Battles.get(battle.id) == recovered
  end

  test "expired component sessions cannot Pause or Resume", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    assert has_element?(view, "#battle-pause")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#battle-pause") |> render_click()
    assert_redirect(view, "/locked")
    assert Battles.get(battle.id).state == "running"
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    view |> element("#battle-pause") |> render_click()
    assert has_element?(view, "#battle-resume")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#battle-resume") |> render_click()
    assert_redirect(view, "/locked")
    assert Battles.get(battle.id).state == "paused"
  end

  defp control_params(view, selector) do
    html = view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query(selector)

    Map.new(~w(key battle_id revision), fn name ->
      {name, html |> LazyHTML.attribute("phx-value-#{name}") |> hd()}
    end)
  end

  defp fail_coordinator(battle, reason \\ "provider_error") do
    for payload <- [
          %{
            "status" => "admitted",
            "head" => String.duplicate("a", 40),
            "native_battle" => %{},
            "resolved_checks" => battle.snapshot["checks"]
          },
          %{"status" => "prepared", "preparation" => %{}},
          %{
            "status" => "failed",
            "reason" => reason,
            "provider" => %{"status" => reason}
          }
        ] do
      {:ok, attempt} = Battles.claim_next(battle.id)

      result =
        Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
        |> Map.merge(payload)
        |> Map.put("cleanup_verified", true)

      {:ok, _} = Battles.finish(attempt.id, attempt.claim_token, result)
    end

    Battles.get(battle.id)
  end

  test "waiting retry shows exact role and model; guarded cancellation preserves an unsaved draft",
       ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> element("button[aria-label='Edit First task']") |> render_click()
    view |> form("#draft-form", title: "Keep my draft during backoff") |> render_change()
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    fail_coordinator(battle, "connection_lost")
    Foundation.broadcast()
    assert has_element?(view, "#battle-activity", "Waiting to retry")
    assert has_element?(view, "#battle-backoff[role=status]", "retrying in")
    assert has_element?(view, "#battle-activity", "Summa Rudis")
    assert has_element?(view, "#battle-activity", "requested model test-model")
    assert has_element?(view, "#battle-cancel-backoff[type=button]")
    stale = control_params(view, "#battle-cancel-backoff")
    {:ok, again, _} = live(signed, ctx.path)
    again |> with_target("#arena-battle") |> render_click("cancel-backoff", stale)
    assert has_element?(again, "#battle-backoff")
    assert has_element?(again, "#battle-error", "control changed")
    view |> element("#battle-cancel-backoff") |> render_click()
    refute has_element?(view, "#battle-backoff")
    assert has_element?(view, "#battle-retry", "Retry failed stage")
    assert has_element?(view, "#draft-title-input[value='Keep my draft during backoff']")
    assert Battles.get(battle.id).state == "needs_attention"
    assert Battles.get(battle.id).context["provider_retries"] == nil
  end

  test "expired component sessions cannot cancel a scheduled retry", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    waiting = fail_coordinator(battle, "connection_lost")
    Foundation.broadcast()
    assert has_element?(view, "#battle-cancel-backoff")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#battle-cancel-backoff") |> render_click()
    assert_redirect(view, "/locked")
    assert Battles.get(battle.id) == waiting
  end

  test "Skip confirms dependent tasks, preserves input and rejects recovered confirmation", ctx do
    dependent = Ecto.UUID.generate()

    {:ok, _} =
      Tabulae.save(
        Ecto.UUID.generate(),
        ctx.arena.id,
        ctx.board.id,
        dependent,
        0,
        Map.merge(ctx.attrs, %{"title" => "Dependent task", "depends_on" => [ctx.task]})
      )

    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> element("button[aria-label='Edit First task']") |> render_click()
    view |> form("#draft-form", title: "Keep my unsaved title") |> render_change()
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    fail_coordinator(battle)
    Foundation.broadcast()
    assert has_element?(view, "#battle-skip[type=button]", "Skip task")
    view |> element("#battle-skip") |> render_click()
    assert has_element?(view, "#battle-skip-confirmation", "First task")
    assert has_element?(view, "#battle-skip-confirmation li", "Dependent task")
    assert has_element?(view, "#battle-skip-confirmation", "may use provider allowance")
    stale = Map.put(control_params(view, "#battle-confirm-skip"), "task_id", ctx.task)
    {:ok, again, _} = live(signed, ctx.path)
    again |> with_target("#arena-battle") |> render_click("skip", stale)
    assert Battles.get(battle.id).state == "needs_attention"
    assert has_element?(again, "#battle-error", "control changed")
    view |> element("#battle-confirm-skip") |> render_click()
    assert Battles.get(battle.id).state == "stopped"
    assert has_element?(view, "#battle-omissions", "1 skipped · 1 deferred")
    assert has_element?(view, "#battle-omissions", "unfinished")
    assert has_element?(view, "#draft-title-input[value='Keep my unsaved title']")
    refute has_element?(view, "#battle-result")
    assert has_element?(view, "#battle-start-scope")
  end

  test "Skip refuses foreign ids and expired sessions", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    fail_coordinator(battle)
    Foundation.broadcast()
    view |> element("#battle-skip") |> render_click()

    params =
      control_params(view, "#battle-confirm-skip") |> Map.put("task_id", Ecto.UUID.generate())

    view |> with_target("#arena-battle") |> render_click("skip", params)
    assert Battles.get(battle.id).state == "needs_attention"
    view |> element("#battle-skip") |> render_click()
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#battle-confirm-skip") |> render_click()
    assert_redirect(view, "/locked")
    assert Battles.get(battle.id).state == "needs_attention"
  end

  test "partial results never use the completed result label", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)

    Repo.update!(
      Ecto.Changeset.change(battle,
        state: "partial",
        context: %{
          "omitted_tasks" => [%{"id" => ctx.task, "state" => "skipped"}],
          "native_battle" => %{"reference" => "refs/heads/ccoding/battles/#{battle.id}"}
        }
      )
    )

    Foundation.broadcast()
    assert has_element?(view, "#battle-partial-result", "remain unfinished")
    refute has_element?(view, "#battle-result")
    assert has_element?(view, "#battle-start-scope")
    refute has_element?(view, "#battle-skip")
  end

  test "Retry is keyboard accessible, preserves input and rejects a recovered control", ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> element("button[aria-label='Edit First task']") |> render_click()
    view |> form("#draft-form", title: "Keep my text") |> render_change()
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id) |> fail_coordinator()
    assert has_element?(view, "#battle-retry[type=button]", "Retry failed stage")
    assert has_element?(view, "#battle-retry-help", "provider allowance")
    assert has_element?(view, "#draft-title-input[value='Keep my text']")
    previous = control_params(view, "#battle-retry")
    {:ok, again, _} = live(signed, ctx.path)
    again |> with_target("#arena-battle") |> render_click("retry", previous)
    assert Battles.get(battle.id).state == "needs_attention"
    assert has_element?(again, "#battle-error", "control changed")
    again |> element("#battle-retry") |> render_click()
    assert Battles.get(battle.id).state == "running"
    assert Battles.get(battle.id).stage == "coordinator"
    assert has_element?(again, "#battle-pause")
    refute has_element?(again, "#battle-retry")
    view |> with_target("#arena-battle") |> render_click("retry", previous)
    assert length(Battles.get(battle.id).context["provider_retries"]) == 1
  end

  test "expired sessions and foreign battle ids cannot Retry", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id) |> fail_coordinator()
    assert has_element?(view, "#battle-retry")
    params = control_params(view, "#battle-retry") |> Map.put("battle_id", Ecto.UUID.generate())
    view |> with_target("#arena-battle") |> render_click("retry", params)
    assert Battles.get(battle.id).state == "needs_attention"
    assert has_element?(view, "#battle-error", "control changed")
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#battle-retry") |> render_click()
    assert_redirect(view, "/locked")
    assert Battles.get(battle.id).state == "needs_attention"
  end

  test "blocked Start shows the exact connection and refuses execution", ctx do
    workspace = Foundation.workspace()

    Repo.update!(
      Ecto.Changeset.change(workspace,
        connection: Map.put(workspace.connection, "catalog_status", "stale")
      )
    )

    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    assert has_element?(view, "#arena-start[disabled]", "Start")
    assert has_element?(view, "a[href='/agents/codex']")
    assert has_element?(view, "#battle-blockers", "Speculator, Implementor, Secutor, Summa Rudis")

    assert view
           |> element("#battle-blockers")
           |> render()
           |> LazyHTML.from_fragment()
           |> LazyHTML.query("a[href='/agents/codex']")
           |> Enum.count() == 1

    view |> form("#battle-start-form") |> render_submit()
    assert has_element?(view, "#battle-blockers", "last model lookup failed")
    assert Battles.latest(ctx.arena.id, ctx.board.id) == nil
  end

  test "missing models link to Team and explicit save/adoption repairs Start without reassignment",
       ctx do
    saved = Team.current()

    roles =
      Enum.map(Team.editable(saved), fn role ->
        if role["id"] in ~w(speculator secutor), do: Map.put(role, "model_id", ""), else: role
      end)

    {:ok, incomplete} = Team.save(Ecto.UUID.generate(), saved.id, roles)

    {:ok, _} =
      TeamAssignments.adopt(
        Ecto.UUID.generate(),
        ctx.arena.id,
        ctx.board.id,
        saved.id,
        incomplete.id,
        true
      )

    {:ok, preview} = Battles.preview(ctx.arena.id, ctx.board.id)
    assert preview.blockers == ["model_unassigned"]
    signed = sign_in(ctx.conn)
    {:ok, board, _} = live(signed, ctx.path)
    assert has_element?(board, "#arena-start[disabled]")
    assert has_element?(board, "#battle-blockers", "Speculator, Secutor")
    assert has_element?(board, "#battle-blockers", "no model is selected")
    team_path = "/team?arena=#{ctx.arena.id}&tabula=#{ctx.board.id}"

    assert has_element?(
             board,
             "#battle-blockers a[href='#{team_path}#role-speculator']",
             "Choose model"
           )

    refute has_element?(board, "#battle-blockers a[href='/agents/codex']")
    assert has_element?(board, "#battle-start-team", "Model needed")
    assert has_element?(board, "#scope-team", "Codex · Model needed")
    assert has_element?(board, "#scope-team a[href='#{team_path}']", "Edit saved defaults")
    board |> form("#battle-start-form") |> render_submit()
    assert Battles.latest(ctx.arena.id, ctx.board.id) == nil

    {:ok, editor, _} = live(signed, team_path)
    assert has_element?(editor, "#role-speculator", "Agent selected · choose a model")
    assert has_element?(editor, "#team-incomplete", "Speculator, Secutor")

    editor
    |> form("#team-form",
      roles: %{speculator: %{model_id: "test-id"}, secutor: %{model_id: "test-id"}}
    )
    |> render_submit()

    refute has_element?(editor, "#team-incomplete")
    assert TeamAssignments.assigned(ctx.board).id == incomplete.id
    assert has_element?(board, "#arena-start[disabled]")
    board |> form("#scope-team-form") |> render_submit()
    assert has_element?(board, "#arena-start:not([disabled])")

    assert Enum.map(
             TeamAssignments.assigned(ctx.board).definition["roles"],
             &Map.take(&1, ~w(agent model_id model))
           ) ==
             Enum.map(saved.definition["roles"], &Map.take(&1, ~w(agent model_id model)))

    assert Repo.get!(Cuckoding.TeamRevision, incomplete.id) == incomplete
    {:ok, again, _} = live(signed, ctx.path)
    again |> form("#battle-start-form") |> render_submit()
    assert Battles.latest(ctx.arena.id, ctx.board.id).state == "running"
    assert length(Tabulae.tasks(ctx.board.id)) == 1
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

    again |> element("button[aria-label='Add task to Specs']") |> render_click()
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

  test "clean timing-gap pause survives reconnect and requires a fresh Resume control", ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    now = DateTime.utc_now()
    gap = Cuckoding.BattleClock.gap({now, 0}, {DateTime.add(now, 60), 1_000})
    {:ok, [paused]} = Battles.observe_timing_gap(gap)
    assert has_element?(view, "#battle-timing-paused", "Paused after a timing gap")

    assert has_element?(
             view,
             "#battle-timing-observation",
             "does not prove sleep or worker cleanup"
           )

    stale = control_params(view, "#battle-resume")
    {:ok, again, _} = live(signed, ctx.path)
    again |> with_target("#arena-battle") |> render_click("resume", stale)
    assert Battles.get(battle.id) == paused
    again |> element("#battle-resume") |> render_click()
    assert Battles.get(battle.id).state == "running"
    assert Battles.get(battle.id).deadline_at == battle.deadline_at
    assert Battles.attempts(battle.id) == []
  end

  test "active timing-gap receipt explains rejection and requires confirmed Stop after reconnect",
       ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    {:ok, attempt} = Battles.claim_next(battle.id)
    now = DateTime.utc_now()
    gap = Cuckoding.BattleClock.gap({now, 0}, {DateTime.add(now, 60), 60_000})
    {:ok, [_]} = Battles.observe_timing_gap(gap)
    assert has_element?(view, "#battle-timing-cancelling", "waiting for owned worker cleanup")

    receipt =
      Map.merge(
        Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256)),
        %{"status" => "cancelled", "cleanup_verified" => true}
      )

    {:ok, _} = Battles.finish(attempt.id, attempt.claim_token, receipt)
    assert has_element?(view, "#battle-attempt-#{attempt.id}", "not accepted work")
    assert has_element?(view, "#battle-attempt-#{attempt.id}", "Worker cleanup verified")
    refute has_element?(view, "#battle-resume")
    refute has_element?(view, "#battle-retry")
    refute has_element?(view, "#battle-skip")
    view |> element("#battle-stop") |> render_click()
    {:ok, again, _} = live(signed, ctx.path)
    refute has_element?(again, "#battle-stop-confirmation")
    assert has_element?(again, "#battle-timing-observation")
    again |> element("#battle-stop") |> render_click()
    again |> element("#battle-confirm-stop") |> render_click()
    assert Battles.get(battle.id).state == "stopped"
    assert Repo.get!(Cuckoding.Battles.Attempt, attempt.id).result == receipt
  end

  test "recovery inspections remain visible after reconnect without resuming work", ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    id = Ecto.UUID.generate()

    battle =
      Repo.update!(
        Ecto.Changeset.change(battle,
          state: "needs_attention",
          reason: "restart_requires_inspection",
          context: %{"integration_recovery_pending" => id}
        )
      )

    Foundation.broadcast()
    assert has_element?(view, "#battle-recovery-inspecting", "No Git change will be repeated")

    for status <- ~w(failed integrated) do
      receipt = %{
        "status" => status,
        "reason" => "battle_mismatch",
        "head" => String.duplicate("a", 40)
      }

      Repo.update!(
        Ecto.Changeset.change(battle,
          context: %{"integration_reconciliations" => %{id => receipt}}
        )
      )

      Foundation.broadcast()
      refute has_element?(view, "#battle-recovery-inspecting")
      assert has_element?(view, "#battle-reconciliation-#{id}", "No Git change was repeated")

      assert has_element?(
               view,
               "#battle-reconciliation-#{id}",
               if(status == "failed",
                 do: "Cleanup remains uncertain",
                 else: "Retained integration and cleanup verified"
               )
             )

      refute has_element?(view, "#battle-resume")
      refute has_element?(view, "#battle-start-form")
      {:ok, again, _} = live(signed, ctx.path)
      assert has_element?(again, "#battle-reconciliation-#{id}")
      refute has_element?(again, "#battle-resume")
    end
  end

  test "provider closure inspection survives reconnect without presenting accepted work", ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    id = Ecto.UUID.generate()

    battle =
      Repo.update!(
        Ecto.Changeset.change(battle,
          state: "needs_attention",
          reason: "restart_requires_inspection",
          context: %{"provider_closure_pending" => id}
        )
      )

    Foundation.broadcast()

    assert has_element?(
             view,
             "#battle-provider-closure-pending",
             "No agent turn will be repeated"
           )

    for verified <- [false, true] do
      Repo.update!(
        Ecto.Changeset.change(battle,
          context: %{
            "provider_closures" => %{
              id => %{
                "status" => if(verified, do: "closed", else: "failed"),
                "cleanup_verified" => verified
              }
            }
          }
        )
      )

      Foundation.broadcast()
      refute has_element?(view, "#battle-provider-closure-pending")

      assert has_element?(
               view,
               "#battle-provider-closure-#{id}",
               "Its work has not been accepted"
             )

      assert has_element?(
               view,
               "#battle-provider-closure-#{id}",
               if(verified, do: "You can Stop", else: "could not be verified")
             )

      refute has_element?(view, "#battle-resume")
      refute has_element?(view, "#battle-retry")
      refute has_element?(view, "#battle-skip")
      {:ok, again, _} = live(signed, ctx.path)

      assert has_element?(
               again,
               "#battle-provider-closure-#{id}",
               "Its work has not been accepted"
             )
    end
  end

  test "expired receipts explain retained work and require confirmed Stop after reconnect", ctx do
    signed = sign_in(ctx.conn)
    {:ok, view, _} = live(signed, ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    {:ok, attempt} = Battles.claim_next(battle.id)

    receipt =
      Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
      |> Map.merge(%{
        "status" => "admitted",
        "head" => String.duplicate("a", 40),
        "native_battle" => %{"reference" => "refs/heads/ccoding/battles/#{battle.id}"},
        "resolved_checks" => battle.snapshot["checks"],
        "cleanup_verified" => true
      })

    assert {:error, "late_result_rejected"} =
             Battles.finish(attempt.id, attempt.claim_token, receipt, attempt.deadline_at)

    assert has_element?(view, "#battle-activity", "result was not accepted")
    assert has_element?(view, "#battle-progress", "0 / 1")
    assert has_element?(view, "#battle-attempt-#{attempt.id}", "Worker cleanup verified")
    assert has_element?(view, "#battle-attempt-#{attempt.id}", "Reported result (not accepted)")
    refute has_element?(view, "#battle-resume")
    refute has_element?(view, "#battle-retry")
    refute has_element?(view, "#battle-skip")
    view |> element("#battle-stop") |> render_click()
    assert has_element?(view, "#battle-stop-question")
    assert Battles.get(battle.id).state == "needs_attention"

    {:ok, again, _} = live(signed, ctx.path)
    refute has_element?(again, "#battle-stop-question")
    again |> with_target("#arena-battle") |> render_click("stop", %{"battle_id" => battle.id})
    assert Battles.get(battle.id).state == "needs_attention"
    again |> element("#battle-stop") |> render_click()
    again |> element("#battle-confirm-stop") |> render_click()
    assert Battles.get(battle.id).state == "stopped"
    assert has_element?(again, "#battle-activity", "Stopped after worker cleanup")
    assert has_element?(again, "#battle-attempt-#{attempt.id}", "not accepted work")
    assert Repo.get!(Cuckoding.Battles.Attempt, attempt.id).result == receipt
  end

  test "expired receipts with unknown cleanup explain why Stop cannot release the Arena", ctx do
    {:ok, view, _} = ctx.conn |> sign_in() |> live(ctx.path)
    view |> form("#battle-start-form") |> render_submit()
    battle = Battles.latest(ctx.arena.id, ctx.board.id)
    {:ok, attempt} = Battles.claim_next(battle.id)

    receipt =
      Map.take(attempt.request, ~w(battle_id request_id task_id stage criteria_sha256))
      |> Map.merge(%{"status" => "failed", "reason" => "timeout", "cleanup_verified" => false})

    {:error, "late_result_rejected"} =
      Battles.finish(attempt.id, attempt.claim_token, receipt, attempt.deadline_at)

    assert has_element?(view, "#battle-attempt-#{attempt.id}", "Worker cleanup is uncertain")
    view |> element("#battle-stop") |> render_click()
    view |> element("#battle-confirm-stop") |> render_click()
    assert Battles.get(battle.id).state == "needs_attention"
    assert has_element?(view, "#arena-battle", "Stop cannot claim cleanup is complete")
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

    assert has_element?(
             view,
             "#battle-blockers",
             "Shorten descriptions, criteria or check arguments"
           )

    assert has_element?(view, "#arena-start[disabled]", "Start")
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
