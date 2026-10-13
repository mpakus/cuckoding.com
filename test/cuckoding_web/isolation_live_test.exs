defmodule CuckodingWeb.IsolationLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest
  alias Cuckoding.{BrowserToken, Codex, Foundation, Repo}

  defp version(version \\ Codex.isolation_version()) do
    {:ok, _} = Foundation.check_codex(Ecto.UUID.generate(), 0, "/bin/sh", true)
    {:ok, claim} = Foundation.claim()
    Foundation.finish(claim, %{"status" => "supported", "version" => version})
  end

  test "optional isolation uses the current form, has cancellation and preserves the wizard", %{
    conn: conn
  } do
    version()
    {:ok, view, _} = conn |> sign_in() |> live("/agents/codex")
    assert has_element?(view, "#wizard-connect")
    assert has_element?(view, "#isolation-check button:not([disabled])", "Run isolation check")
    view |> form("#isolation-check") |> render_submit(%{"consent_key" => "recovered"})
    refute Foundation.pending?()
    view |> form("#isolation-check") |> render_submit()
    assert has_element?(view, "#agent-progress", "Checking execution isolation")
    assert has_element?(view, "#isolation-check button[disabled]")
    {:ok, claim} = Foundation.claim()
    send(view.pid, :clock)
    assert has_element?(view, "#wizard-connect")
    view |> element("#agent-progress button", "Cancel") |> render_click()
    assert has_element?(view, "#agent-progress", "cancelling")
    Foundation.finish(claim, %{"status" => "cancelled"})
    assert has_element?(view, "#isolation-result", "cancelled")
    assert has_element?(view, "#wizard-connect")
    assert has_element?(view, "nav a[href='/team']", "Team")
    assert has_element?(view, "nav a[href='/arenas']", "Arenas")
  end

  test "old versions and expired sessions cannot submit a check", %{conn: conn} do
    version("0.146.0")
    {:ok, view, _} = conn |> sign_in() |> live("/agents/codex")
    assert has_element?(view, "#isolation-check button[disabled]")
    view |> form("#isolation-check") |> render_submit()
    refute Foundation.pending?()
    Repo.update_all(BrowserToken, set: [expires_at: 0])
    view |> form("#isolation-check") |> render_submit()
    assert_redirect(view, "/locked")
    refute Foundation.pending?()
  end
end
