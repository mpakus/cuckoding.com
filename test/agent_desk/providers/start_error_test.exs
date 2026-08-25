defmodule AgentDesk.Providers.StartErrorTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers

  test "explains a missing provider CLI" do
    assert Providers.start_error_message(:not_found) =~ "provider CLI"
    assert Providers.start_error_message({:error, :enoent}) =~ "provider CLI"
    assert Providers.start_error_message({:spawn_failed, "enoent"}) =~ "provider CLI"
  end

  test "explains a git worktree failure" do
    message = Providers.start_error_message({128, "fatal: already exists\nmore"})
    assert message =~ "isolated worktree"
    assert message =~ "fatal: already exists"
    refute message =~ "more"
  end

  test "explains an empty git repository" do
    message = Providers.start_error_message(:empty_repository)
    assert message =~ "empty Git repository"
    refute message =~ "ambiguous argument"
    refute message =~ "Make an initial commit"
  end

  test "explains a changeset rejection" do
    assert Providers.start_error_message(%Ecto.Changeset{errors: []}) =~ "Could not save"
  end

  test "explains a stopped session and handshake timeout" do
    assert Providers.start_error_message(:not_started) =~ "Resume"
    assert Providers.start_error_message(:handshake_timeout) =~ "did not finish starting"
  end
end
