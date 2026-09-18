defmodule CuckodingWeb.PolicyComponentsTest do
  use CuckodingWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CuckodingWeb.PolicyComponents

  test "advisory policy fields are never rendered as enforced" do
    advisory =
      render_component(&PolicyComponents.classification_badge/1, classification: :advisory)

    enforced =
      render_component(&PolicyComponents.classification_badge/1, classification: :enforced)

    assert advisory =~ "Advisory · not enforced"
    assert advisory =~ "Advisory only; not enforced by the host runner"
    refute advisory =~ ">Enforced<"

    assert enforced =~ "Enforced\n</span>"
    assert enforced =~ "Enforced by Cuckoding"
    refute enforced =~ "Advisory"
  end

  test "host runner warning discloses every advisory boundary before execution" do
    html = render_component(&PolicyComponents.host_runner_notice/1, %{})

    assert html =~ "Host runner: not a sandbox"
    assert html =~ "do not confine an arbitrary host process"
    assert html =~ "runtime permission mode"
    assert html =~ "opaque secret references"
    assert html =~ "enforced from unenforced"
  end
end
