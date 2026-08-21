defmodule AgentDesk.Providers.RedactorTest do
  use ExUnit.Case, async: true

  alias AgentDesk.Providers.Redactor

  test "redacts tokens before persistence" do
    text = Redactor.redact("Authorization: Bearer sk-abc123456789 and ghp_abcdefghijklmnopqr")
    refute text =~ "sk-abc123456789"
    refute text =~ "ghp_abcdefghijklmnopqr"
    assert text =~ "[REDACTED]"
  end
end
