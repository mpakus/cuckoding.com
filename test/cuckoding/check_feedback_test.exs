defmodule Cuckoding.CheckFeedbackTest do
  use ExUnit.Case, async: true
  alias Cuckoding.Battles.Attempt
  alias Cuckoding.CheckFeedback

  defp excerpt(text),
    do: %{
      "version" => "bounded-guest-feedback-v1",
      "excerpt" => text,
      "excerpt_sha256" => :crypto.hash(:sha256, text) |> Base.encode16(case: :lower),
      "excerpt_bytes" => byte_size(text),
      "truncated" => false
    }

  test "excerpts are closed UTF-8 data with exact transformed bytes and hash" do
    good = excerpt("expected yes\nactual no")
    assert CheckFeedback.valid_excerpt?(good)
    assert CheckFeedback.current?(%{})
    refute CheckFeedback.current?(%{"check_feedback" => "unknown"})

    for value <- [
          nil,
          Map.put(good, "extra", "no"),
          Map.put(good, "excerpt_sha256", String.duplicate("a", 64)),
          Map.put(good, "excerpt_bytes", true),
          Map.put(good, "truncated", 0),
          excerpt(String.duplicate("x", 4097)),
          excerpt("hidden\e[31m"),
          excerpt("unsafe\u202E"),
          excerpt(<<255>>)
        ] do
      refute CheckFeedback.valid_excerpt?(value)
    end
  end

  test "feedback is bound to one failed check and never grants historical or foreign authority" do
    id = Ecto.UUID.generate()

    attempt = %Attempt{
      id: id,
      stage: "checks",
      request: %{"snapshot" => %{"check_feedback" => CheckFeedback.policy()}}
    }

    row = %{
      "id" => Ecto.UUID.generate(),
      "request_id" => id,
      "candidate_sha" => String.duplicate("a", 40),
      "status" => "failed",
      "stdout_sha256" => String.duplicate("b", 64),
      "stdout_bytes" => 50
    }

    feedback =
      CheckFeedback.project(
        Map.merge(row, %{"check_id" => row["id"], "failure_output" => excerpt("assertion failed")})
      )

    result = %{
      "status" => "checks_failed",
      "candidate_sha" => row["candidate_sha"],
      "checks" => [row],
      "check_feedback" => [feedback]
    }

    assert CheckFeedback.valid_result?(attempt, result)
    refute CheckFeedback.valid_result?(attempt, Map.put(result, "checks", [nil]))

    for field <- ~w(request_id check_id candidate_sha stdout_sha256 stdout_bytes) do
      refute CheckFeedback.valid_result?(
               attempt,
               put_in(result["check_feedback"], [Map.put(feedback, field, "foreign")])
             )
    end

    refute CheckFeedback.valid_result?(attempt, Map.delete(result, "check_feedback"))
    refute CheckFeedback.valid_result?(%{attempt | stage: "speculator"}, result)
    old = %{attempt | request: %{"snapshot" => %{}}}
    refute CheckFeedback.valid_result?(old, result)
    assert CheckFeedback.valid_result?(old, Map.delete(result, "check_feedback"))
    passed = %{"status" => "passed", "check_feedback" => []}
    assert CheckFeedback.valid_result?(attempt, passed)
    public = CheckFeedback.public([feedback])
    refute inspect(public) =~ "assertion failed"
    refute inspect(public) =~ "request_id"
    assert hd(public)["excerpt_bytes"] == 16
  end
end
