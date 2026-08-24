defmodule AgentDeskWeb.WorkspaceViewTest do
  use ExUnit.Case, async: true

  alias AgentDeskWeb.WorkspaceView

  test "task_forest nests crew children under the parent" do
    parent =
      task("p1", nil, "Crew: auth", "queued", "parent", nil, ~U[2026-01-02 00:00:00Z])

    backend =
      task("b1", "p1", "Backend", "assigned", "lane", "backend", ~U[2026-01-02 00:00:01Z])

    review =
      task("r1", "p1", "Review: auth", "blocked", "review", "review", ~U[2026-01-02 00:00:02Z])

    lone = task("t9", nil, "Chore", "queued", nil, nil, ~U[2026-01-01 00:00:00Z])

    assert [
             %{task: ^parent, children: [^backend, ^review]},
             %{task: ^lone, children: []}
           ] = WorkspaceView.task_forest([review, backend, lone, parent])

    assert WorkspaceView.crew_progress(parent, [backend, review]) ==
             "0/1 lanes done · review waiting"

    items = WorkspaceView.sidebar_task_items([parent, backend, review, lone])
    assert Enum.map(items, & &1.id) == ["p1", "b1", "r1", "t9"]
    refute WorkspaceView.completable_task?(review)
    assert WorkspaceView.completable_task?(backend)
  end

  defp task(id, parent_id, title, status, kind, lane, inserted_at) do
    orchestration =
      cond do
        is_binary(kind) and is_binary(lane) -> %{"kind" => kind, "lane" => lane}
        is_binary(kind) -> %{"kind" => kind}
        true -> nil
      end

    metadata = if orchestration, do: %{"orchestration" => orchestration}, else: %{}

    %{
      id: id,
      parent_task_id: parent_id,
      title: title,
      status: status,
      metadata: metadata,
      inserted_at: inserted_at
    }
  end
end
