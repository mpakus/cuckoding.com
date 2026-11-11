defmodule Boss.CursorReviewTest do
  use ExUnit.Case, async: false
  alias Boss.Agents.Cursor
  alias Boss.Deliveries.Worker

  test "a successful Cursor result becomes the review report" do
    root =
      Path.join(System.tmp_dir!(), "boss-cursor-#{System.unique_integer([:positive])}")

    File.mkdir!(root)
    report = ~s({"verdict":"approved"})

    envelope =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "success",
        "is_error" => false,
        "duration_ms" => 12,
        "session_id" => "private-session",
        "result" => report
      })

    payload = Path.join(root, "payload.json")
    File.write!(payload, envelope)
    script = Path.join(root, "agent")

    File.write!(script, """
    #!/bin/sh
    cat >/dev/null
    cat #{payload}
    printf '\\n'
    exit 0
    """)

    File.chmod!(script, 0o700)
    previous = System.get_env("PATH")
    System.put_env("PATH", root <> ":" <> previous)

    on_exit(fn ->
      System.put_env("PATH", previous)
      File.rm_rf(root)
    end)

    receipt =
      Worker.run_reviewer("cursor", root, "review the diff", fn text ->
        assert text == report
        {:ok, %{"verdict" => "approved"}}
      end)

    assert receipt["status"] == "finished"
    assert receipt["report"] == %{"verdict" => "approved"}
    assert receipt["summary"]["duration_ms"] == 12
    refute inspect(receipt) =~ "private-session"
  end

  test "an error result is not a report" do
    output =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "error",
        "is_error" => true,
        "result" => "failed"
      })

    assert Cursor.report(output) == :error
  end
end
