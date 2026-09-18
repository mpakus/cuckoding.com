defmodule CuckodingWeb.PluginSettingsLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.Plugins.Activation
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Plugins.Registry
  alias Cuckoding.Repo

  test "settings exposes health and requires reviewed activation controls", %{conn: conn} do
    discover()
    plugin = Repo.get_by!(Plugin, key: "valid-shell")

    {:ok, view, html} = live(conn, ~p"/settings/plugins")

    assert has_element?(view, "h1", "Plugins")
    assert has_element?(view, "#plugin-#{plugin.id}", "Health: Available")
    assert has_element?(view, "#plugin-#{plugin.id} fieldset", "Review and enable a scope")
    assert has_element?(view, "p[role=status][aria-live=polite]")
    refute html =~ ~r/tabindex="[1-9]/

    view
    |> form("#plugin-#{plugin.id} form[phx-submit=enable]", %{
      "plugin_id" => plugin.id,
      "scope_type" => "global",
      "scope_id" => "",
      "network" => "external",
      "reason" => "Reviewed external access",
      "confirmed" => "true"
    })
    |> render_submit()

    assert has_element?(view, "#plugin-#{plugin.id}", "global · Enabled")
    assert has_element?(view, "#plugin-#{plugin.id}", "approval: external_network")

    assert {:ok, _plugin} = Registry.mark_unhealthy(plugin.id, "restart limit reached")
    {:ok, degraded, _html} = live(conn, ~p"/settings/plugins")
    assert has_element?(degraded, "#plugin-#{plugin.id}", "Health: Degraded")

    assert has_element?(
             degraded,
             "#plugin-#{plugin.id}",
             "Detection detail: restart limit reached"
           )

    assert has_element?(degraded, "#plugin-#{plugin.id} button[disabled]", "Enable scope")
  end

  test "server rejects a bypassed confirmation", %{conn: conn} do
    discover()
    plugin = Repo.get_by!(Plugin, key: "valid-shell")
    {:ok, view, _html} = live(conn, ~p"/settings/plugins")

    view
    |> render_submit("enable", %{
      "plugin_id" => plugin.id,
      "scope_type" => "global",
      "scope_id" => "",
      "network" => "external",
      "reason" => "Not confirmed"
    })

    assert has_element?(view, "p[role=alert]", "Review and confirm")
    assert Repo.aggregate(Activation, :count) == 0
  end

  defp discover do
    Registry.discover(
      bundled_dir: Path.expand("../fixtures/plugins", __DIR__),
      user_dir: Path.join(System.tmp_dir!(), "missing-plugin-dir"),
      find_executable: fn
        "fake-tool" -> "/opt/fake-tool"
        _name -> nil
      end,
      command_runner: fn _path, _args, _options -> {"fake-tool 1.4.0", 0} end
    )
  end
end
