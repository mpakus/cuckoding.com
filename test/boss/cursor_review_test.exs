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

  test "an authentication failure stays a short Cursor note" do
    assert %{class: "auth", reason: reason} =
             Cursor.notice(
               "Error: Authentication required. Please run 'agent login' first, or set CURSOR_API_KEY=secret-value\n",
               ""
             )

    assert reason =~ "Authentication required"
    refute reason =~ "secret-value"
  end

  test "a Cursor planning failure keeps the authentication note" do
    root = Path.join(System.tmp_dir!(), "boss-cursor-auth-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    script = Path.join(root, "agent")

    File.write!(script, """
    #!/bin/sh
    echo "Error: Authentication required. Please run 'agent login' first." >&2
    exit 1
    """)

    File.chmod!(script, 0o700)
    previous = System.get_env("PATH")
    System.put_env("PATH", root <> ":" <> previous)

    on_exit(fn ->
      System.put_env("PATH", previous)
      File.rm_rf(root)
    end)

    receipt =
      Worker.run_agent(:plan, root, "plan", fn _ -> {:ok, %{}} end, nil, implementer: "cursor")

    assert receipt["summary"]["error_class"] == "auth"
    assert receipt["reason"] =~ "Authentication required"
    assert receipt["exit_code"] == 1
  end

  test "a Cursor implementer plans without calling Codex" do
    root = Path.join(System.tmp_dir!(), "boss-cursor-plan-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    plan = ~s({"summary":"Add a note","steps":["Edit the file"],"acceptance":["The note exists"]})

    envelope =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "success",
        "is_error" => false,
        "result" => plan
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
      Worker.run_agent(
        :plan,
        root,
        "plan the task",
        fn text ->
          assert text == plan
          {:ok, %{"summary" => "Add a note"}}
        end,
        nil,
        implementer: "cursor"
      )

    assert receipt["status"] == "finished"
    assert receipt["report"]["summary"] == "Add a note"
  end

  test "Cursor implement_args passes --force and json_object strips prose around JSON" do
    assert "--force" in Cursor.implement_args()

    wrapped =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "success",
        "is_error" => false,
        "result" => "Here is the plan:\n{\"summary\":\"ok\"}\nDone."
      })

    assert {:ok, "{\"summary\":\"ok\"}", _} = Cursor.report(wrapped)
  end

  test "a Claude implementer plans and diagnoses with structured_output without calling Codex" do
    root = Path.join(System.tmp_dir!(), "boss-claude-plan-#{System.unique_integer([:positive])}")
    File.mkdir!(root)

    envelope =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "success",
        "is_error" => false,
        "duration_ms" => 40,
        "usage" => %{"input_tokens" => 10, "output_tokens" => 5},
        "structured_output" => %{
          "summary" => "Claude plan",
          "steps" => ["Step 1"],
          "acceptance" => ["Passes check"]
        }
      })

    payload = Path.join(root, "claude_payload.json")
    File.write!(payload, envelope)
    script = Path.join(root, "claude")

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
      Worker.run_agent(
        :plan,
        root,
        "plan via claude",
        fn text -> Jason.decode(text) end,
        nil,
        implementer: "claude",
        report_diagnostics: true
      )

    assert receipt["status"] == "finished"
    assert receipt["validation_code"] == "valid"
    assert receipt["report"]["summary"] == "Claude plan"
  end
end
