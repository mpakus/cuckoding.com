defmodule AgentDesk.EventsTest do
  use AgentDesk.DataCase

  alias AgentDesk.Events
  alias AgentDesk.GitRepo
  alias AgentDesk.Projects

  test "appends an event for an open project" do
    repo = GitRepo.tmp_repo!()
    {:ok, project} = Projects.open_project(repo)

    assert {:ok, event} =
             Events.append(%{
               project_id: project.id,
               type: "test.ping",
               source: "events_test",
               payload: %{"ok" => true}
             })

    assert event.project_id == project.id
    assert event.type == "test.ping"
    assert event.payload["ok"] == true
    assert event.correlation_id

    AgentDesk.Projects.Supervisor.stop_runtime(project.id)
  after
    :ok
  end
end
