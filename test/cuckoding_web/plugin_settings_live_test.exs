defmodule CuckodingWeb.PluginSettingsLiveTest do
  use CuckodingWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Cuckoding.Plugins.Activation
  alias Cuckoding.Plugins.Plugin
  alias Cuckoding.Plugins.Registry
  alias Cuckoding.Repo

  setup do
    root =
      System.tmp_dir!()
      |> String.replace_prefix("/var/", "/private/var/")
      |> Path.join("cuckoding-live-diagnostics-#{System.unique_integer([:positive])}")

    previous = Application.get_env(:cuckoding, :diagnostics_output_root)
    Application.put_env(:cuckoding, :diagnostics_output_root, root)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:cuckoding, :diagnostics_output_root, previous),
        else: Application.delete_env(:cuckoding, :diagnostics_output_root)

      File.rm_rf!(root)
    end)

    :ok
  end

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

  test "settings discloses exclusions before creating a local diagnostics bundle", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/settings/plugins")

    assert has_element?(view, "#diagnostics-heading", "Diagnostics")
    assert has_element?(view, "#diagnostics-heading + p", "Review a private support bundle")
    assert render(view) =~ "excludes source files"
    assert render(view) =~ "This bundle stays on this Mac until you delete it"
    assert render(view) =~ "Cuckoding does not upload it"

    view |> element("button", "Create diagnostics bundle") |> render_click()

    assert has_element?(view, "p[role=status]", "Diagnostics bundle created for review.")
    assert render(view) =~ "Saved locally:"
  end

  test "runner isolation label comes from its validated manifest", %{conn: conn} do
    Registry.discover(
      bundled_dir: Application.app_dir(:cuckoding, "priv/plugins"),
      user_dir: Path.join(System.tmp_dir!(), "missing-plugin-dir"),
      find_executable: fn _name -> nil end
    )

    plugin = Repo.get_by!(Plugin, key: "container-runner-stub")
    {:ok, view, _html} = live(conn, ~p"/settings/plugins")

    assert has_element?(
             view,
             "#plugin-#{plugin.id}",
             "Isolation No container isolation declared"
           )
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
