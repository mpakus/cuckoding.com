defmodule Boss.ReleasePackage do
  @moduledoc false
  @otp "28.5.0.8"
  @openssl "3.5.9"
  @sources %{
    "otp" => "882bc060aca3f9491ba6345da56c5076793d31e2",
    "openssl" => "45e844fa2a14ec92d146bd8f5778ac130b6625fb"
  }
  @licenses %{
    "otp" => "809fa1ed21450f59827d1e9aec720bbc4b687434fa22283c6cb5dd82a47ab9c0",
    "openssl" => "7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a"
  }
  @stl_license "1fc6b6db121d4555d8f661937d7f6013693cd8fd67495d5e5d98c1d18fb83eda"
  @notices ~w(OTP/asmjit/LICENSE.md OTP/pcre/LICENCE OTP/zstd/LICENSE OTP/ryu/LICENSE-Apache2 OTP/ryu/LICENSE-Boost OTP/tcl/erl_posix_str-LICENSE.txt OTP/ryu/to_chars-LICENSE.txt)

  def prepare(release) do
    unless Mix.env() == :prod, do: Mix.raise("Build releases with MIX_ENV=prod")

    unless :os.type() == {:unix, :darwin},
      do: Mix.raise("Release packaging currently supports macOS only")

    crypto =
      Path.join(
        release.path,
        "lib/crypto-#{release.applications[:crypto][:vsn]}/priv/lib/crypto.so"
      )

    runtime = runtime!(crypto, release.erts_version)
    validate_native!(release.path, crypto)
    copy_notices(release, runtime)
    File.cp!(runtime.path, Path.join(release.path, "RUNTIME_INFO.json"))
    {sha, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    {status, 0} = System.cmd("git", ["status", "--porcelain", "--untracked-files=normal"])

    File.write!(Path.join(release.path, "BUILD_INFO"), """
    BOSS #{release.version}
    Source commit: #{String.trim(sha)}
    Source local changes: #{String.trim(status) != ""}
    macOS: #{String.trim(command!("sw_vers", ["-productVersion"]))}
    Architecture: #{String.trim(command!("uname", ["-m"]))}
    Elixir: #{System.version()}
    OTP: #{@otp}
    OTP source: #{@sources["otp"]}
    ERTS: #{release.erts_version}
    OpenSSL: #{runtime.info["runtime_openssl"]}
    OpenSSL source: #{@sources["openssl"]}
    Crypto linkage: static
    Crypto SHA256: #{runtime.info["crypto_sha256"]}
    Runtime manifest SHA256: #{digest(runtime.path)}
    Native images: build signatures retained; no Developer ID signature or notarization
    """)

    File.cp!("docs/RELEASE.md", Path.join(release.path, "README.md"))

    %{
      release
      | overlays: ["LICENSES", "BUILD_INFO", "RUNTIME_INFO.json", "README.md" | release.overlays]
    }
  end

  def validate_runtime!(otp, openssl, info) do
    versions!(otp, openssl)

    expected = %{
      "schema_version" => 1,
      "platform" => "darwin",
      "architecture" => "arm64",
      "otp_version" => @otp,
      "openssl_version" => @openssl,
      "crypto_linkage" => "static",
      "runtime_openssl" => openssl,
      "licenses" => @licenses
    }

    unless Map.take(info, Map.keys(expected)) == expected,
      do: Mix.raise("Runtime manifest does not describe the pinned static runtime")

    for {name, commit} <- @sources do
      unless get_in(info, ["sources", name, "commit"]) == commit,
        do: Mix.raise("Unexpected #{name} runtime source")
    end

    unless is_map(info["notices"]) and Enum.sort(Map.keys(info["notices"])) == Enum.sort(@notices),
      do: Mix.raise("Runtime third-party notices are incomplete")

    :ok
  end

  defp versions!(otp, openssl) do
    unless otp == @otp, do: Mix.raise("Expected OTP #{@otp}, got #{otp}")

    unless String.split(openssl) |> Enum.take(2) == ["OpenSSL", @openssl],
      do: Mix.raise("Expected OpenSSL #{@openssl}, got #{openssl}")
  end

  defp runtime!(crypto, erts_version) do
    root = :code.root_dir() |> List.to_string()
    original = Application.app_dir(:crypto, "priv/lib/crypto.so")
    hash = digest(original)

    unless digest(crypto) == hash,
      do: Mix.raise("Packaged crypto differs from the running runtime")

    openssl =
      case :crypto.info_lib() do
        [{name, _, version}] when name in ["OpenSSL", ~c"OpenSSL"] -> to_string(version)
        _ -> Mix.raise("Unsupported crypto library")
      end

    otp =
      File.read!(Path.join([root, "releases", System.otp_release(), "OTP_VERSION"]))
      |> String.trim()

    versions!(otp, openssl)
    path = Path.expand("../../../RUNTIME_INFO.json", root)
    info = File.read!(path) |> JSON.decode!()
    validate_runtime!(otp, openssl, info)

    unless info["crypto_sha256"] == hash and info["erts_version"] == to_string(erts_version) and
             info["erts_version"] == to_string(:erlang.system_info(:version)) and
             info["architecture"] == String.trim(command!("uname", ["-m"])),
           do: Mix.raise("Runtime manifest crypto/ERTS/architecture identity mismatch")

    %{path: path, root: Path.dirname(path), info: info}
  end

  def validate_native!(root, crypto) do
    crypto_dependencies =
      if macho?(crypto), do: dependencies(crypto) -- install_names(crypto), else: []

    unless crypto_dependencies != [] and Enum.all?(crypto_dependencies, &system_library?/1),
      do: Mix.raise("Expected static OpenSSL crypto with only system-library dependencies")

    for file <- Path.wildcard(Path.join(root, "**/*"), match_dot: true), macho?(file) do
      unless contained_regular?(root, file),
        do: Mix.raise("Native runtime image is outside the release or a symlink: #{file}")

      for dependency <- dependencies(file) -- install_names(file) do
        unless system_library?(dependency) or bundled_library?(root, file, dependency),
          do: Mix.raise("External runtime library remains: #{file}: #{dependency}")
      end
    end

    :ok
  end

  defp dependencies(file) do
    for line <- String.split(command!("otool", ["-L", file]), "\n"),
        [_, path] <- [Regex.run(~r/^\s+(.+) \(compatibility version/, line)],
        do: path
  end

  defp install_names(file),
    do: command!("otool", ["-D", file]) |> String.split("\n", trim: true) |> Enum.drop(1)

  defp system_library?(path) do
    path = Path.expand(path)
    String.starts_with?(path, "/usr/lib/") or String.starts_with?(path, "/System/Library/")
  end

  defp bundled_library?(root, file, "@loader_path/" <> suffix) do
    contained_regular?(root, Path.expand(suffix, Path.dirname(file)))
  end

  defp bundled_library?(_, _, _), do: false

  defp contained_regular?(root, resolved) do
    String.starts_with?(resolved, root <> "/") and
      Enum.reduce_while(Path.split(Path.relative_to(resolved, root)), root, fn part, parent ->
        path = Path.join(parent, part)

        case File.lstat(path) do
          {:ok, %{type: :directory}} -> {:cont, path}
          {:ok, %{type: :regular}} when path == resolved -> {:cont, path}
          _ -> {:halt, false}
        end
      end) == resolved
  end

  defp macho?(file) do
    if File.regular?(file) do
      File.open!(file, [:read, :binary], fn stream ->
        IO.binread(stream, 4) in [
          <<0xFE, 0xED, 0xFA, 0xCE>>,
          <<0xFE, 0xED, 0xFA, 0xCF>>,
          <<0xCE, 0xFA, 0xED, 0xFE>>,
          <<0xCF, 0xFA, 0xED, 0xFE>>,
          <<0xCA, 0xFE, 0xBA, 0xBE>>,
          <<0xBE, 0xBA, 0xFE, 0xCA>>,
          <<0xCA, 0xFE, 0xBA, 0xBF>>,
          <<0xBF, 0xBA, 0xFE, 0xCA>>
        ]
      end)
    else
      false
    end
  end

  defp copy_notices(release, runtime) do
    target = Path.join(release.path, "LICENSES")
    File.mkdir_p!(target)
    elixir = Application.app_dir(:elixir, "../../LICENSE") |> Path.expand()
    File.cp!(elixir, Path.join(target, "Elixir-LICENSE"))
    File.cp!("assets/node_modules/tailwindcss/LICENSE", Path.join(target, "Tailwind-LICENSE"))
    File.cp!("LICENSE", Path.join(target, "BOSS-LICENSE"))

    for {key, name} <- [{"otp", "Erlang-LICENSE.txt"}, {"openssl", "OpenSSL-LICENSE.txt"}] do
      source = Path.join("rel/licenses", name)
      unless digest(source) == @licenses[key], do: Mix.raise("Pinned #{key} license changed")
      File.cp!(source, Path.join(target, name))
    end

    stl = "rel/licenses/Microsoft-STL-LICENSE.txt"
    unless digest(stl) == @stl_license, do: Mix.raise("Pinned Microsoft STL license changed")
    stl_target = Path.join(target, "Erlang-third-party/ryu/Microsoft-STL-LICENSE.txt")
    File.mkdir_p!(Path.dirname(stl_target))
    File.cp!(stl, stl_target)

    for {name, hash} <- runtime.info["notices"] do
      source = Path.join([runtime.root, "NOTICES", name])
      unless digest(source) == hash, do: Mix.raise("Runtime notice changed: #{name}")
      destination = Path.join([target, "Erlang-third-party", String.trim_leading(name, "OTP/")])
      File.mkdir_p!(Path.dirname(destination))
      File.cp!(source, destination)
    end

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

  defp digest(path), do: :crypto.hash(:sha256, File.read!(path)) |> Base.encode16(case: :lower)

  defp command!(executable, args) do
    case System.cmd(executable, args, stderr_to_stdout: true) do
      {output, 0} -> output
      {output, status} -> Mix.raise("#{executable} failed (#{status}): #{output}")
    end
  end
end
