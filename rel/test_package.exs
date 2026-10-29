Mix.start()
Code.require_file("package.exs", __DIR__)
ExUnit.start()

defmodule Boss.ReleasePackageTest do
  use ExUnit.Case, async: false
  alias Boss.ReleasePackage, as: Package
  @otp "28.5.0.8"
  @openssl "OpenSSL 3.5.9 28 Oct 2026"
  @system "/usr/lib/libSystem.B.dylib"
  @notices ~w(OTP/asmjit/LICENSE.md OTP/pcre/LICENCE OTP/zstd/LICENSE OTP/ryu/LICENSE-Apache2 OTP/ryu/LICENSE-Boost OTP/tcl/erl_posix_str-LICENSE.txt OTP/ryu/to_chars-LICENSE.txt)

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "boss-package-" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)
      )

    File.mkdir!(root)
    previous = System.fetch_env!("PATH")

    on_exit(fn ->
      System.put_env("PATH", previous)
      File.rm_rf!(root)
    end)

    bin = Path.join(root, "bin")
    File.mkdir!(bin)
    tool = Path.join(bin, "otool")

    File.write!(tool, """
    #!/usr/bin/env python3
    import json, sys
    mode, path = sys.argv[1:]
    with open(path + '.loads.json') as file:
        info = json.load(file)
    print(path + ':')
    if mode == '-L':
        for dependency in info['dependencies']:
            print('\t' + dependency + ' (compatibility version 1.0.0, current version 1.0.0)')
    elif mode == '-D' and info.get('id'):
        print(info['id'])
    """)

    File.chmod!(tool, 0o700)
    System.put_env("PATH", bin <> ":" <> previous)
    release = Path.join(root, "release")
    File.mkdir!(release)
    crypto = image(release, "lib/crypto/priv/lib/crypto.so", [@system])
    %{root: root, release: release, crypto: crypto}
  end

  defp manifest do
    %{
      "schema_version" => 1,
      "platform" => "darwin",
      "architecture" => "arm64",
      "otp_version" => @otp,
      "openssl_version" => "3.5.9",
      "runtime_openssl" => @openssl,
      "crypto_linkage" => "static",
      "licenses" => %{
        "otp" => "809fa1ed21450f59827d1e9aec720bbc4b687434fa22283c6cb5dd82a47ab9c0",
        "openssl" => "7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a"
      },
      "sources" => %{
        "otp" => %{"commit" => "882bc060aca3f9491ba6345da56c5076793d31e2"},
        "openssl" => %{"commit" => "45e844fa2a14ec92d146bd8f5778ac130b6625fb"}
      },
      "notices" => Map.new(@notices, &{&1, String.duplicate("a", 64)})
    }
  end

  defp image(root, name, dependencies, opts \\ []) do
    path = Path.join(root, name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Keyword.get(opts, :magic, <<0xCF, 0xFA, 0xED, 0xFE>>) <> "fixture")
    File.write!(path <> ".loads.json", JSON.encode!(%{dependencies: dependencies, id: opts[:id]}))
    path
  end

  test "only the exact supported OTP/OpenSSL pair and source manifest passes" do
    assert :ok = Package.validate_runtime!(@otp, @openssl, manifest())

    for version <- ["28.5", "28.5.0.7", "29.0"] do
      assert_raise Mix.Error, ~r/Expected OTP/, fn ->
        Package.validate_runtime!(version, @openssl, manifest())
      end
    end

    for version <- [
          "OpenSSL 3.5.6 old",
          "OpenSSL 3.6.3 old",
          "OpenSSL 3.5.9-dev",
          "LibreSSL 3.5.9"
        ] do
      assert_raise Mix.Error, ~r/Expected OpenSSL/, fn ->
        Package.validate_runtime!(@otp, version, manifest())
      end
    end

    assert_raise Mix.Error, ~r/pinned static runtime/, fn ->
      Package.validate_runtime!(@otp, @openssl, Map.put(manifest(), "crypto_linkage", "dynamic"))
    end

    assert_raise Mix.Error, ~r/runtime source/, fn ->
      Package.validate_runtime!(
        @otp,
        @openssl,
        put_in(manifest(), ["sources", "otp", "commit"], "wrong")
      )
    end

    assert_raise Mix.Error, ~r/notices are incomplete/, fn ->
      Package.validate_runtime!(@otp, @openssl, Map.put(manifest(), "notices", %{}))
    end
  end

  test "a copied crypto mismatch fails before host-version evidence", c do
    old = Mix.env()
    Mix.env(:prod)

    try do
      version = Application.spec(:crypto, :vsn) |> to_string()
      image(c.release, "lib/crypto-#{version}/priv/lib/crypto.so", [@system])

      release = %{
        path: c.release,
        applications: %{crypto: [vsn: version]},
        erts_version: "fixture"
      }

      assert_raise Mix.Error, ~r/Packaged crypto differs/, fn -> Package.prepare(release) end
    after
      Mix.env(old)
    end
  end

  test "static crypto and contained native dependencies pass", c do
    image(c.release, "lib/crypto/priv/lib/crypto.so", ["@loader_path/crypto.so", @system],
      id: "@loader_path/crypto.so"
    )

    image(c.release, "helpers/libtest.dylib", ["@loader_path/libtest.dylib", @system],
      id: "@loader_path/libtest.dylib"
    )

    image(c.release, "helpers/worker", ["@loader_path/libtest.dylib", @system])
    assert :ok = Package.validate_native!(c.release, c.crypto)
  end

  test "dynamic, unsupported and empty crypto dependencies fail", c do
    for dependencies <- [
          ["/opt/openssl/lib/libcrypto.3.dylib"],
          ["@loader_path/libcrypto.3.dylib"],
          []
        ] do
      image(c.release, "lib/crypto/priv/lib/crypto.so", dependencies)

      assert_raise Mix.Error, ~r/Expected static OpenSSL/, fn ->
        Package.validate_native!(c.release, c.crypto)
      end
    end
  end

  test "every native image is checked, including fat64", c do
    image(c.release, "helpers/worker", ["/opt/unbundled/libbad.dylib"],
      magic: <<0xCA, 0xFE, 0xBA, 0xBF>>
    )

    assert_raise Mix.Error, ~r/External runtime library remains/, fn ->
      Package.validate_native!(c.release, c.crypto)
    end
  end

  test "missing, escaping and unresolved loader dependencies fail", c do
    for dependency <- [
          "@loader_path/missing.dylib",
          "@loader_path/../../../outside.dylib",
          "@rpath/libbad.dylib",
          "/usr/lib/../../opt/libbad.dylib"
        ] do
      image(c.release, "helpers/worker", [dependency])

      assert_raise Mix.Error, ~r/External runtime library remains/, fn ->
        Package.validate_native!(c.release, c.crypto)
      end
    end
  end

  test "an apparently contained loader path cannot follow a symlink outside", c do
    outside = image(c.root, "outside/libbad.dylib", [@system])
    directory = Path.join(c.release, "helpers")
    File.mkdir!(directory)
    File.ln_s!(outside, Path.join(directory, "libbad.dylib"))
    image(c.release, "helpers/worker", ["@loader_path/libbad.dylib"])

    assert_raise Mix.Error,
                 ~r/outside the release or a symlink|External runtime library remains/,
                 fn -> Package.validate_native!(c.release, c.crypto) end
  end

  test "hidden native images are not omitted from closure", c do
    image(c.release, ".hidden/helper", ["/opt/unbundled/libhidden.dylib"])

    assert_raise Mix.Error, ~r/External runtime library remains/, fn ->
      Package.validate_native!(c.release, c.crypto)
    end
  end

  test "vendored root notices exactly match pinned upstream bytes" do
    for {name, hash, size} <- [
          {"Erlang", "809fa1ed21450f59827d1e9aec720bbc4b687434fa22283c6cb5dd82a47ab9c0", 10175},
          {"OpenSSL", "7d5450cb2d142651b8afa315b5f238efc805dad827d91ba367d8516bc9d49e7a", 10175},
          {"Microsoft-STL", "1fc6b6db121d4555d8f661937d7f6013693cd8fd67495d5e5d98c1d18fb83eda",
           12550}
        ] do
      bytes = File.read!(Path.join(__DIR__, "licenses/#{name}-LICENSE.txt"))
      assert byte_size(bytes) == size
      assert Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == hash
    end
  end
end
