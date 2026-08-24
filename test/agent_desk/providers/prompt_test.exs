defmodule AgentDesk.Providers.PromptTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.Prompt

  test "appends non-image attachment paths to the prompt text" do
    text =
      Prompt.with_file_notes("look", [
        %{"name" => "notes.md", "path" => "/tmp/notes.md", "mime" => "text/markdown"}
      ])

    assert text =~ "look"
    assert text =~ "notes.md"
    assert text =~ "/tmp/notes.md"
  end

  test "leaves image-only attachments out of the text notes" do
    text =
      Prompt.with_file_notes("see this", [
        %{"name" => "shot.png", "path" => "/tmp/shot.png", "mime" => "image/png"}
      ])

    assert text == "see this"
  end
end
