defmodule Mix.Tasks.Cuckoding.App do
  @shortdoc "Build a local macOS .app from the Mix release (no Burrito)"
  @moduledoc """
  Packages Cuckoding as a local macOS `.app`.

  OTP 28 has no Burrito ERTS, so this task bundles the Mix release (local ERTS)
  into the Tauri app resources and uses a small sidecar shim to start it.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.shell().info("Building Cuckoding.app for local use (Mix release sidecar)...")
    env = [{"MIX_ENV", "prod"}, {"SECRET_KEY_BASE", secret_key_base()}]

    mix!(~w(compile --warnings-as-errors), env)
    mix!(~w(assets.deploy), env)
    mix!(~w(release desktop --overwrite), env)
    relax_release_perms!()
    write_sidecar()
    tauri!(~w(build --bundles app --ci))
    embed_release!()
    maybe_codesign()

    Mix.shell().info("""
    Done. Open:

      src-tauri/target/release/bundle/macos/Cuckoding.app
    """)
  end

  defp mix!(args, env) do
    case System.cmd("mix", args,
           env: env,
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {_, status} -> Mix.raise("mix #{Enum.join(args, " ")} failed with #{status}")
    end
  end

  defp tauri!(args) do
    env = [
      {"CARGO_TARGET_DIR", Path.expand("src-tauri/target")}
    ]

    case System.cmd(tauri_cli!(), args,
           env: env,
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      {_, status} -> Mix.raise("tauri #{Enum.join(args, " ")} failed with #{status}")
    end
  end

  defp tauri_cli! do
    base = Path.join([ExTauri.installation_path(), "bin", "cargo-tauri"])

    cond do
      File.exists?(base) -> base
      File.exists?(base <> ".exe") -> base <> ".exe"
      true -> Mix.raise("Tauri CLI not found. Run mix ex_tauri.install first.")
    end
  end

  defp write_sidecar do
    triplet = ExTauri.host_triplet()
    File.mkdir_p!("burrito_out")

    script = """
    #!/bin/sh
    set -eu
    DIR="$(cd "$(dirname "$0")" && pwd)"
    for candidate in \
      "$DIR/../Resources/rel/desktop/bin/desktop" \
      "$DIR/../Resources/desktop/bin/desktop"
    do
      if [ -x "$candidate" ]; then
        exec "$candidate" start "$@"
      fi
    done
    echo "Cuckoding Mix release not found next to the app sidecar." >&2
    exit 1
    """

    hyphen = Path.join("burrito_out", "desktop-#{triplet}")
    underscore = Path.join("burrito_out", "desktop_#{triplet}")
    File.write!(hyphen, script)
    File.chmod!(hyphen, 0o755)
    File.cp!(hyphen, underscore)
    File.chmod!(underscore, 0o755)
    :ok
  end

  defp relax_release_perms! do
    root = Path.expand("_build/prod/rel/desktop")
    _ = System.cmd("chmod", ["-R", "u+rwX", root], stderr_to_stdout: true)
    :ok
  end

  defp embed_release! do
    app = Path.expand("src-tauri/target/release/bundle/macos/Cuckoding.app")
    dest = Path.join(app, "Contents/Resources/rel/desktop")
    src = Path.expand("_build/prod/rel/desktop")

    unless File.dir?(app) do
      Mix.raise("Cuckoding.app was not produced at #{app}")
    end

    File.rm_rf!(dest)
    File.mkdir_p!(Path.dirname(dest))

    case System.cmd("cp", ["-R", src, dest], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {_, status} -> Mix.raise("copy Mix release into .app failed with #{status}")
    end
  end

  defp maybe_codesign do
    app = Path.expand("src-tauri/target/release/bundle/macos/Cuckoding.app")

    if match?({:unix, :darwin}, :os.type()) and File.dir?(app) do
      System.cmd("codesign", ["--force", "--deep", "-s", "-", app],
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )
    end
  end

  defp secret_key_base do
    System.get_env("SECRET_KEY_BASE") ||
      :crypto.strong_rand_bytes(48) |> Base.encode64(padding: false)
  end
end
