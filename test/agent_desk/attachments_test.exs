defmodule AgentDesk.AttachmentsTest do
  use AgentDesk.DataCase, async: true

  alias AgentDesk.Agents.Session
  alias AgentDesk.Attachments
  alias AgentDesk.Projects.Project

  test "stores the file under the session data directory" do
    project = %Project{id: Ecto.UUID.generate(), canonical_path: System.tmp_dir!()}
    session = %Session{id: Ecto.UUID.generate()}

    source =
      Path.join(System.tmp_dir!(), "cuckoding-attach-#{System.unique_integer([:positive])}.txt")

    File.write!(source, "hello")

    try do
      att = Attachments.store!(project, session, source, "hello.txt", "text/plain")

      assert att["name"] == "hello.txt"
      assert att["mime"] == "text/plain"
      assert File.read!(att["path"]) == "hello"
      refute String.starts_with?(Path.expand(att["path"]), Path.expand(project.canonical_path))
    after
      File.rm(source)
    end
  end
end
