defmodule CuckodingWeb.BuildInfoLiveTest do
  use CuckodingWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    original = Application.get_env(:cuckoding, :build_info)
    on_exit(fn -> Application.put_env(:cuckoding, :build_info, original) end)
  end

  test "source UI does not borrow a packaged identity", %{conn: conn} do
    Application.delete_env(:cuckoding, :build_info)
    {:ok, view, _} = conn |> sign_in() |> live("/settings")
    assert has_element?(view, "#build-identity", "Source UI preview")
    refute has_element?(view, "#build-details")
  end

  test "Settings presents only validated public package fields with truthful scope", %{conn: conn} do
    info = Cuckoding.BuildInfoFixtures.info()
    Application.put_env(:cuckoding, :build_info, info)
    {:ok, view, _} = conn |> sign_in() |> live("/settings")
    assert has_element?(view, "#build-identity", info["build_id"])
    assert has_element?(view, "#build-details", info["source_sha256"])
    assert has_element?(view, "#build-details", "Local changes were present")
    assert has_element?(view, "#build-details", "does not prove signing")
    refute has_element?(view, "#build-details[open]")
    Application.put_env(:cuckoding, :build_info, Map.put(info, "credential", "BUILD_CANARY"))
    {:ok, again, html} = conn |> sign_in() |> live("/settings")
    refute has_element?(again, "#build-details")
    refute html =~ "BUILD_CANARY"
  end
end
