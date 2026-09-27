defmodule Cuckoding.ACPBridgeFixture do
  @moduledoc false

  def install(root, name) do
    File.mkdir_p!(root)
    path = Path.join(root, "#{name}-acp")
    File.cp!(Path.expand("test/support/fixtures/acp_runtime.rb"), path)
    File.chmod!(path, 0o700)
    version = if name == "codex", do: "1.13.1+cuckoding.2", else: "0.81.2+cuckoding.1"
    digest = Base.encode16(:crypto.hash(:sha256, File.read!(path)), case: :lower)

    File.write!(
      Path.join(root, "manifest.json"),
      Jason.encode!(%{
        schema: 1,
        bridges: %{name => %{version: version, sha256: digest}}
      })
    )

    root
  end
end
