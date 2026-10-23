defmodule Cuckoding.BuildInfoFixtures do
  @moduledoc false
  def info do
    %{
      "format" => 1,
      "build_id" => "00000000-0000-4000-8000-000000000001",
      "application" => "0.1.0",
      "channel" => "local-preview",
      "source_revision" => String.duplicate("a", 40),
      "source_dirty" => true,
      "source_sha256" => String.duplicate("b", 64),
      "built_at" => "2026-10-23T00:00:00Z",
      "target" => "aarch64-apple-darwin",
      "schema" => 17,
      "elixir" => "1.20.3",
      "otp" => "28.5",
      "rust" => "1.97.1"
    }
  end
end
