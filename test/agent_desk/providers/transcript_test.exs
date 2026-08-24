defmodule AgentDesk.Providers.TranscriptTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.Event
  alias AgentDesk.Providers.Transcript

  test "windows the newest lines and reports older activity" do
    project_id = Ecto.UUID.generate()
    session_id = Ecto.UUID.generate()

    Enum.each(1..5, fn n ->
      :ok =
        Transcript.append(project_id, session_id, %Event{
          type: :turn_completed,
          payload: %{"summary" => "turn #{n}"},
          occurred_at: DateTime.utc_now()
        })
    end)

    window = Transcript.window(project_id, session_id, limit: 2)

    assert window.total == 5
    assert window.older?
    assert length(window.rows) == 2
    assert List.last(window.rows)["payload"]["summary"] == "turn 5"
  end
end
