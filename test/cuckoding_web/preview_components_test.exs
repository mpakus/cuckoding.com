defmodule CuckodingWeb.PreviewComponentsTest do
  use CuckodingWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias CuckodingWeb.PreviewComponents

  test "renders textual health, a safe preview link, and accessible worktree actions" do
    html =
      render_component(&PreviewComponents.preview_panel/1,
        preview_url: "http://127.0.0.1:45000",
        health: {:unhealthy, 503},
        worktree_path: "/private/tmp/example"
      )

    assert html =~ "Unhealthy · HTTP 503"
    assert html =~ ~s(href="http://127.0.0.1:45000")
    assert html =~ "Open preview"
    assert html =~ "Open in Finder"
    assert html =~ "Open in editor"
    assert html =~ ~s(aria-label="Worktree actions")

    unsafe =
      render_component(&PreviewComponents.preview_panel/1,
        preview_url: "javascript:alert(1)",
        health: :healthy,
        worktree_path: "/private/tmp/example"
      )

    assert unsafe =~ ~s(href="#")
    refute unsafe =~ ~s(href="javascript:)
  end
end
