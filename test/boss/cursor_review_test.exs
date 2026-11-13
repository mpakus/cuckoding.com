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

  test "Cursor implement_args passes --force and --model auto by default, and classifies Free-tier model unavailable" do
    assert Cursor.implement_args() == [
             "--print",
             "--force",
             "--output-format",
             "json",
             "--trust",
             "--model",
             "auto"
           ]

    assert Cursor.args() == [
             "--print",
             "--output-format",
             "json",
             "--mode",
             "ask",
             "--sandbox",
             "enabled",
             "--trust",
             "--model",
             "auto"
           ]

    assert %{class: "model_unavailable"} =
             Cursor.notice(
               "ActionRequiredError: Model unavailable on Free Free includes Grok 4.7, Grok 4.6, and Auto with fixed settings. Switch to an included model to continue.\n",
               ""
             )

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

    credit_err =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "success",
        "is_error" => true,
        "result" => "Credit balance is too low"
      })

    assert %{class: "rate_limit", reason: "Claude Code: Credit balance is too low"} =
             Boss.Agents.Claude.notice("", credit_err)
  end

  test "Cursor stage finishes cleanly when an MCP helper lingers and pre-tool prose contains braces" do
    root =
      Path.join(System.tmp_dir!(), "boss-cursor-linger-#{System.unique_integer([:positive])}")

    File.mkdir!(root)

    plan_json =
      Jason.encode!(%{
        "summary" => "Handle {braces} safely",
        "steps" => ["Inspect %{config: true}"],
        "acceptance" => ["Passes test"],
        "file_scopes" => [%{"path" => "lib/app.ex", "kind" => "file"}],
        "clarification" => nil,
        "complexity" => "small"
      })

    # Simulate multi-turn Cursor result where Turn 1 prose contains Elixir %{...} braces
    multi_turn =
      "I'll check %{http: :ok} and {:error, :timeout} in the repo first.\n" <> plan_json

    envelope =
      Jason.encode!(%{
        "type" => "result",
        "subtype" => "success",
        "is_error" => false,
        "duration_ms" => 55,
        "result" => multi_turn
      })

    # Notice never leaks raw success envelope prose
    assert Cursor.notice("", envelope) == %{
             class: nil,
             reason:
               "Cursor did not finish with a valid result and clean exit. No fallback was started."
           }

    payload = Path.join(root, "linger_payload.json")
    File.write!(payload, envelope)
    script = Path.join(root, "agent")

    # Spawn a lingering child (closing stdio like an MCP daemon) and exit 0
    File.write!(script, """
    #!/bin/sh
    cat >/dev/null
    (sleep 10 </dev/null >/dev/null 2>&1) &
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
        "plan with lingering mcp",
        &Boss.Deliveries.Protocol.plan/1,
        nil,
        implementer: "cursor",
        report_diagnostics: true
      )

    assert receipt["status"] == "finished"
    assert receipt["outcome"] == "exited"
    assert receipt["cleanup"] == "group_empty"
    assert receipt["validation_code"] == "valid"
    assert receipt["report"]["summary"] == "Handle {braces} safely"
  end

  test "provider rate-limit diagnostics name Cursor Agent instead of Codex" do
    alias Boss.Deliveries.Diagnostics

    step = %{
      kind: "implement",
      status: "failed",
      receipt: %{
        "reason" =>
          "Cursor Agent: ActionRequiredError: You've hit your usage limit Get Cursor Pro for more Agent usage."
      }
    }

    delivery = %{implementer: "cursor", analytic: "cursor", reviewer: "cursor"}

    msg =
      Diagnostics.provider_message(
        "provider_rate_limit",
        Diagnostics.stage_agent_id(delivery, "implement"),
        step.receipt["reason"]
      )

    assert msg =~ "Cursor Agent reported a quota, usage, or credit limit"
    assert msg =~ "You've hit your usage limit"
    refute msg =~ "Codex"

    rewritten =
      Diagnostics.attention(
        "Codex reported a quota or rate limit. This workflow stopped before another model call. Retry after capacity is available.",
        [step],
        delivery
      )

    assert rewritten == msg
  end
end
