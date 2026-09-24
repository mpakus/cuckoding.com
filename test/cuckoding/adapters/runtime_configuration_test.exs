defmodule Cuckoding.Adapters.RuntimeConfigurationTest do
  use ExUnit.Case, async: false

  alias Cuckoding.Adapters.RuntimeConfiguration

  setup do
    root =
      Path.expand("tmp/cuckoding-discovery-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok,
     root: root,
     options: [
       home: root,
       path: "",
       system_dirs: [],
       application_dirs: [Path.join(root, "Apps With Spaces")]
     ]}
  end

  test "finds both Codex desktop bundle names, including paths with spaces", fixture do
    for app <- ["Codex.app", "ChatGPT.app"] do
      path =
        executable!(
          Path.join([fixture.root, "Apps With Spaces", app, "Contents/Resources/codex"])
        )

      assert RuntimeConfiguration.default_executable("codex", fixture.options) == path
      assert RuntimeConfiguration.default_executable("claude_code", fixture.options) == ""
      File.rm!(path)
    end

    user_app =
      executable!(Path.join(fixture.root, "Applications/Codex.app/Contents/Resources/codex"))

    assert RuntimeConfiguration.default_executable(
             "codex",
             Keyword.put(fixture.options, :application_dirs, [
               Path.join(fixture.root, "Applications")
             ])
           ) == user_app
  end

  test "PATH wins over standard locations and discovery does not run candidates", fixture do
    path = executable!(Path.join(fixture.root, "path with spaces/codex"))
    executable!(Path.join(fixture.root, ".local/bin/codex"))
    options = Keyword.put(fixture.options, :path, Path.dirname(path))
    assert RuntimeConfiguration.default_executable("codex", options) == path
    assert RuntimeConfiguration.default_executable("custom_agent", options) == ""
    assert RuntimeConfiguration.default_executable("unknown", options) == ""
  end

  test "finds supported runtime names in common user locations", fixture do
    for {runtime, name, directory} <- [
          {"codex", "codex", ".volta/bin"},
          {"claude_code", "claude", ".local/bin"},
          {"cursor_agent", "cursor-agent", ".npm-global/bin"},
          {"cursor_agent", "agent", ".bun/bin"},
          {"opencode", "opencode", ".opencode/bin"}
        ] do
      path = executable!(Path.join([fixture.root, directory, name]))
      assert RuntimeConfiguration.default_executable(runtime, fixture.options) == path
      File.rm!(path)
    end
  end

  test "ignores directories, non-executables, broken symlinks and relative PATH entries",
       fixture do
    path = Path.join(fixture.root, ".local/bin/codex")
    File.mkdir_p!(path)
    assert RuntimeConfiguration.default_executable("codex", fixture.options) == ""
    File.rmdir!(path)
    File.write!(path, "not an executable")
    File.chmod!(path, 0o600)
    assert RuntimeConfiguration.default_executable("codex", fixture.options) == ""
    File.rm!(path)
    File.ln_s!(Path.join(fixture.root, "missing"), path)
    assert RuntimeConfiguration.default_executable("codex", fixture.options) == ""
    File.rm!(path)

    target = executable!(Path.join(fixture.root, "real-codex"))
    File.ln_s!(target, path)
    assert RuntimeConfiguration.default_executable("codex", fixture.options) == path

    assert RuntimeConfiguration.default_executable("codex",
             home: nil,
             path: Path.relative_to_cwd(Path.dirname(path)),
             system_dirs: [],
             application_dirs: []
           ) == ""
  end

  test "native shell discovery home is independent of the app-owned HOME", fixture do
    previous = System.get_env("CUCKODING_RUNTIME_HOME")
    System.put_env("CUCKODING_RUNTIME_HOME", fixture.root)

    on_exit(fn ->
      if previous,
        do: System.put_env("CUCKODING_RUNTIME_HOME", previous),
        else: System.delete_env("CUCKODING_RUNTIME_HOME")
    end)

    path = executable!(Path.join(fixture.root, ".local/bin/codex"))

    assert RuntimeConfiguration.default_executable(
             "codex",
             Keyword.delete(fixture.options, :home)
           ) == path
  end

  defp executable!(path) do
    File.mkdir_p!(Path.dirname(path))
    # An invalid program is enough: discovery checks metadata, never executes it.
    File.write!(path, "this must never be executed")
    File.chmod!(path, 0o700)
    path
  end
end
