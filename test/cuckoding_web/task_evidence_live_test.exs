defmodule CuckodingWeb.TaskEvidenceLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.Battles.{Attempt, Battle, Task}
  alias Cuckoding.{BrowserToken, DashboardFixtures, Foundation, Repo, Tabulae}

  setup do
    f =
      DashboardFixtures.fixture("completed", %{
        "title" => "Task",
        "revision" => 1,
        "criteria" => "Frozen criteria"
      })

    for i <- 1..23 do
      Repo.insert!(%Attempt{
        id: Ecto.UUID.generate(),
        battle_id: f.battle.id,
        task_id: f.task.task_id,
        stage: "secutor",
        role: "secutor",
        state: "expired",
        claim_token: Ecto.UUID.generate(),
        deadline_at: f.battle.deadline_at,
        inserted_at: DateTime.add(f.battle.inserted_at, i),
        request: %{
          "role" => %{
            "name" => "Judge",
            "agent_name" => "Saved judge",
            "kind" => "codex",
            "model" => "exact-model",
            "private" => "hidden-sentinel"
          }
        },
        result: %{
          "status" => "changes_requested",
          "summary" => "Review #{i}",
          "feedback" => "Repair the task",
          "candidate_sha" => String.duplicate("a", 40),
          "provider" => %{
            "observed_model" => "actual-model",
            "thoughts" => "hidden-sentinel",
            "tools" => [%{"tool" => "read_file", "status" => "completed", "path" => "lib/app.ex"}]
          }
        }
      })
    end

    Map.put(f, :path, "/arenas/#{f.arena.id}/tabulae/#{f.board.id}")
  end

  test "task dialog shows frozen/public receipts, keeps dirty text and pages stable", f do
    signed = sign_in(f.conn)
    {:ok, view, _} = live(signed, f.path)
    view |> element("button[aria-label='Inspect Task']") |> render_click()
    assert has_element?(view, "#task-evidence", "Frozen criteria")
    assert has_element?(view, "#task-evidence", "Saved judge")
    assert has_element?(view, "#task-evidence", "requested exact-model")
    assert has_element?(view, "#task-evidence", "actual-model")
    assert has_element?(view, "#task-evidence", "Repair the task")
    assert has_element?(view, "#task-evidence", "lib/app.ex")
    assert has_element?(view, "#task-evidence", "not an accepted completion receipt")
    download = evidence_path(f)
    assert has_element?(view, "#task-evidence a[href='#{download}']", "Download evidence")
    refute render(view) =~ "hidden-sentinel"
    view |> form("#draft-form", title: "Keep my draft") |> render_change()
    view |> element("#task-evidence-older") |> render_click()
    assert has_element?(view, "#task-evidence", "Review 3")
    assert has_element?(view, "#task-evidence a[href^='#{download}?before=']")
    refute has_element?(view, "#task-evidence", "Review 23")
    Foundation.broadcast()
    assert has_element?(view, "#draft-title-input[value='Keep my draft']")
    assert has_element?(view, "#task-evidence", "Reading saved attempts")
    assert has_element?(view, "#task-evidence", "draft below differs")
    view |> element("#task-evidence-newer") |> render_click()
    assert has_element?(view, "#task-evidence", "Review 23")
    {:ok, again, _} = live(signed, f.path)
    again |> element("button[aria-label='Inspect Task']") |> render_click()
    assert has_element?(again, "#task-evidence", "Frozen criteria")
  end

  test "a new execution does not replace selected history until explicit navigation", f do
    {:ok, view, _} = f.conn |> sign_in() |> live(f.path)
    view |> element("button[aria-label='Inspect Task']") |> render_click()

    newer =
      Repo.insert!(%Battle{
        id: Ecto.UUID.generate(),
        arena_id: f.arena.id,
        tabula_id: f.board.id,
        fingerprint: String.duplicate("b", 64),
        snapshot: %{},
        state: "completed",
        stage: "summary",
        deadline_at: f.battle.deadline_at,
        inserted_at: DateTime.add(f.battle.inserted_at, 60)
      })

    Repo.insert!(%Task{
      id: Ecto.UUID.generate(),
      battle_id: newer.id,
      task_id: f.task.task_id,
      position: 0,
      state: "skipped",
      snapshot: %{"title" => "Task", "revision" => 2, "criteria" => "Later criteria"}
    })

    Foundation.broadcast()
    assert has_element?(view, "#task-evidence", "Frozen criteria")
    assert has_element?(view, "#task-evidence a[href='#{evidence_path(f)}']")
    refute has_element?(view, "#task-evidence", "Later criteria")

    view
    |> element("#task-evidence button[phx-click=latest]")
    |> render_click(%{"battle_id" => Ecto.UUID.generate()})

    assert has_element?(view, "#task-evidence", "Later criteria")
    assert has_element?(view, "#task-evidence a[href='#{evidence_path(%{f | battle: newer})}']")
    assert has_element?(view, "#task-evidence", "task Skipped")
    view |> element("#task-evidence button[phx-click=earlier]") |> render_click()
    assert has_element?(view, "#task-evidence", "Frozen criteria")

    {:ok, _} =
      Tabulae.save(Ecto.UUID.generate(), f.arena.id, f.board.id, Ecto.UUID.generate(), 0, %{
        "title" => "Other task",
        "description" => "New",
        "criteria" => "New",
        "column" => "specs"
      })

    Foundation.broadcast()
    view |> element("button[aria-label='Edit Other task']") |> render_click()
    assert has_element?(view, "#task-evidence", "has not been included")
    refute has_element?(view, "#task-evidence", "Frozen criteria")
  end

  test "expired component session cannot read another page", f do
    {:ok, view, _} = f.conn |> sign_in() |> live(f.path)
    view |> element("button[aria-label='Inspect Task']") |> render_click()
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> element("#task-evidence-older") |> render_click()
    assert_redirect(view, "/locked")
  end

  test "download is a bounded public page with a scoped attempt cursor and no writes", f do
    signed = sign_in(f.conn)
    counts = {Repo.aggregate(Cuckoding.Command, :count), Repo.aggregate(Cuckoding.Event, :count)}
    conn = get(signed, evidence_path(f))
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert get_resp_header(conn, "content-type") == ["application/json"]

    assert get_resp_header(conn, "content-disposition") ==
             [~s(attachment; filename="task-#{f.task.task_id}-#{f.battle.id}.json")]

    data = json_response(conn, 200)
    assert data["format"] == "cuckoding-task-evidence-v1"
    assert {:ok, _, 0} = DateTime.from_iso8601(data["exported_at"])
    assert data["execution"]["snapshot"]["criteria"] == "Frozen criteria"
    assert data["scope"]["battle_id"] == f.battle.id
    assert data["pagination"] == %{"before" => nil, "more" => true, "page_size" => 20}
    assert length(data["attempts"]) == 20
    assert hd(data["attempts"])["state"] == "expired"
    assert data["notice"] =~ "not completion proof"
    refute conn.resp_body =~ "hidden-sentinel"
    refute conn.resp_body =~ "claim_token"
    refute conn.resp_body =~ "deadline_at"
    cursor = List.last(data["attempts"])["id"]
    older = signed |> get(evidence_path(f), %{before: cursor}) |> json_response(200)
    assert length(older["attempts"]) == 3
    refute older["pagination"]["more"]
    assert older["pagination"]["before"] == cursor

    assert counts ==
             {Repo.aggregate(Cuckoding.Command, :count), Repo.aggregate(Cuckoding.Event, :count)}
  end

  test "download rejects missing sessions, foreign scope/cursors and oversized output", f do
    assert f.conn |> get(evidence_path(f)) |> response(401)
    signed = sign_in(f.conn)
    other = DashboardFixtures.fixture("completed")

    for path <- [
          evidence_path(%{f | arena: other.arena}),
          evidence_path(%{f | board: other.board}),
          evidence_path(%{f | task: other.task}),
          evidence_path(%{f | battle: other.battle})
        ] do
      assert signed |> get(path) |> response(404)
    end

    for cursor <- ["invalid", Ecto.UUID.generate(), ["malformed"]] do
      assert signed |> get(evidence_path(f), %{before: cursor}) |> response(404)
    end

    foreign =
      Repo.insert!(%Attempt{
        id: Ecto.UUID.generate(),
        battle_id: other.battle.id,
        task_id: other.task.task_id,
        stage: "secutor",
        state: "failed",
        claim_token: Ecto.UUID.generate(),
        deadline_at: other.battle.deadline_at,
        request: %{},
        result: %{}
      })

    assert signed |> get(evidence_path(f), %{before: foreign.id}) |> response(404)

    Repo.insert!(%Attempt{
      id: Ecto.UUID.generate(),
      battle_id: f.battle.id,
      task_id: f.task.task_id,
      stage: "secutor",
      state: "failed",
      claim_token: Ecto.UUID.generate(),
      deadline_at: f.battle.deadline_at,
      request: %{},
      inserted_at: DateTime.add(f.battle.inserted_at, 100),
      result: %{"summary" => String.duplicate("x", 2 * 1024 * 1024)}
    })

    assert signed |> get(evidence_path(f)) |> response(413)
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    assert signed |> get(evidence_path(f)) |> response(401)
  end

  defp evidence_path(f),
    do:
      "/arenas/#{f.arena.id}/tabulae/#{f.board.id}/tasks/#{f.task.task_id}/executions/#{f.battle.id}/evidence.json"
end
