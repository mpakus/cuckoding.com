defmodule Boss.ReleasePackage do
  @moduledoc false

  def prepare(release) do
    unless Mix.env() == :prod, do: Mix.raise("Build releases with MIX_ENV=prod")

    unless :os.type() == {:unix, :darwin},
      do: Mix.raise("Release packaging currently supports macOS only")

    crypto =
      Path.join(
        release.path,
        "lib/crypto-#{release.applications[:crypto][:vsn]}/priv/lib/crypto.so"
      )

    source = Enum.find(dependencies(crypto), &String.ends_with?(&1, "/libcrypto.3.dylib"))

    unless source && Path.type(source) == :absolute,
      do: Mix.raise("Expected a build-host OpenSSL 3 libcrypto dependency")

    bundled = Path.join(Path.dirname(crypto), "libcrypto.3.dylib")
    File.write!(bundled, File.read!(source))
    command!("install_name_tool", ["-id", "@loader_path/libcrypto.3.dylib", bundled])
    images = Path.wildcard(Path.join(release.path, "**/*")) |> Enum.filter(&macho?/1)

    changed =
      for image <- images, source in dependencies(image) do
        unless Path.dirname(image) == Path.dirname(bundled),
          do: Mix.raise("Unexpected OpenSSL consumer directory: #{image}")

        command!("install_name_tool", ["-change", source, "@loader_path/libcrypto.3.dylib", image])

        image
      end

    for image <- Enum.uniq([bundled | changed]) do
      command!("codesign", ["--force", "--sign", "-", image])
      command!("codesign", ["--verify", "--strict", image])
    end

    for file <- Path.wildcard(Path.join(release.path, "**/*")),
        macho?(file),
        dependency <- dependencies(file) -- install_names(file) do
      unless system_library?(dependency) or bundled_library?(release.path, file, dependency),
        do: Mix.raise("External runtime library remains: #{file}: #{dependency}")
    end

    copy_notices(release, source)
    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    {status, 0} = System.cmd("git", ["status", "--porcelain", "--untracked-files=normal"])

    File.write!(Path.join(release.path, "BUILD_INFO"), """
    BOSS #{release.version}
    Source commit: #{String.trim(sha)}
    Source local changes: #{String.trim(status) != ""}
    macOS: #{String.trim(command!("sw_vers", ["-productVersion"]))}
    Architecture: #{String.trim(command!("uname", ["-m"]))}
    Elixir: #{System.version()}
    OTP: #{System.otp_release()}
    ERTS: #{release.erts_version}
    Modified native images: ad-hoc signed; no Developer ID signature or notarization
    """)

    File.cp!("docs/RELEASE.md", Path.join(release.path, "README.md"))
    %{release | overlays: ["LICENSES", "BUILD_INFO", "README.md" | release.overlays]}
  end

  defp dependencies(file) do
    for line <- String.split(command!("otool", ["-L", file]), "\n"),
        [_, path] <- [Regex.run(~r/^\s+(.+) \(compatibility version/, line)],
        do: path
  end

  defp install_names(file) do
    command!("otool", ["-D", file]) |> String.split("\n", trim: true) |> Enum.drop(1)
  end

  defp system_library?(path),
    do: String.starts_with?(path, "/usr/lib/") or String.starts_with?(path, "/System/Library/")

  defp bundled_library?(root, file, "@loader_path/" <> suffix) do
    resolved = Path.expand(suffix, Path.dirname(file))
    String.starts_with?(resolved, root <> "/") and File.regular?(resolved)
  end

  defp bundled_library?(_, _, _), do: false

  defp macho?(file) do
    if File.regular?(file) do
      File.open!(file, [:read, :binary], fn stream ->
        IO.binread(stream, 4) in [
          <<0xFE, 0xED, 0xFA, 0xCE>>,
          <<0xFE, 0xED, 0xFA, 0xCF>>,
          <<0xCE, 0xFA, 0xED, 0xFE>>,
          <<0xCF, 0xFA, 0xED, 0xFE>>,
          <<0xCA, 0xFE, 0xBA, 0xBE>>,
          <<0xBE, 0xBA, 0xFE, 0xCA>>
        ]
      end)
    else
      false
    end
  end

  defp copy_notices(release, crypto_source) do
    target = Path.join(release.path, "LICENSES")
    File.mkdir_p!(target)
    elixir = Application.app_dir(:elixir, "../../LICENSE") |> Path.expand()
    File.cp!(elixir, Path.join(target, "Elixir-LICENSE"))
    File.cp!("assets/node_modules/tailwindcss/LICENSE", Path.join(target, "Tailwind-LICENSE"))
    if File.regular?("LICENSE"), do: File.cp!("LICENSE", Path.join(target, "BOSS-LICENSE"))
    erlang = :code.root_dir() |> List.to_string()

    otp_notice =
      Enum.find(
        ["COPYRIGHT", "LICENSE", "LICENSE.txt", "../../LICENSE.txt"],
        &File.regular?(Path.expand(&1, erlang))
      ) || Mix.raise("No Erlang license notice found")

    File.cp!(Path.expand(otp_notice, erlang), Path.join(target, "Erlang-LICENSE.txt"))
    openssl = Path.join([Path.dirname(crypto_source), "..", "LICENSE.txt"]) |> Path.expand()
    File.cp!(openssl, Path.join(target, "OpenSSL-LICENSE.txt"))

    for {app, path} <- Mix.Project.deps_paths(), Map.has_key?(release.applications, app) do
      destination = Path.join(target, Atom.to_string(app))
      File.mkdir_p!(destination)
      notices = Path.wildcard(Path.join(path, "{LICENSE*,COPYING*,COPYRIGHT*,NOTICE*}"))
      notices = if notices == [], do: Path.wildcard(Path.join(path, "README*")), else: notices
      if notices == [], do: Mix.raise("No dependency notice source found for #{app}")
      Enum.each(notices, &File.cp!(&1, Path.join(destination, Path.basename(&1))))

      if app in [:ecto, :ecto_sql, :db_connection],
        do: File.cp!(elixir, Path.join(destination, "Apache-2.0.txt"))

      if app == :yaml_elixir,
        do: File.cp!("rel/licenses/yaml_elixir-LICENSE", Path.join(destination, "MIT.txt"))
    end
  end

  defp command!(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> Mix.raise("#{executable} failed (#{status}): #{output}")
    end
  end
end
