#!/usr/bin/env ruby
# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "mach_o_files"
require_relative "release_metadata"

class ReleaseMetadataTest < Minitest::Test
  def test_parses_locked_hex_and_cargo_packages
    Dir.mktmpdir do |directory|
      mix = File.join(directory, "mix.lock")
      cargo = File.join(directory, "Cargo.lock")
      File.write(mix, "%{\n  \"jason\": {:hex, :jason, \"1.4.5\", \"abc123\", [:mix], []}\n}\n")
      File.write(cargo, <<~LOCK)
        version = 4
        [[package]]
        name = "serde"
        version = "1.0.0"
        source = "registry+https://github.com/rust-lang/crates.io-index"
        checksum = "def456"
      LOCK

      assert_equal({"jason" => {version: "1.4.5", checksum: "abc123"}}, ReleaseMetadata.mix_packages(mix))
      assert_equal "serde", ReleaseMetadata.cargo_packages(cargo).first.fetch(:name)
      assert_equal "def456", ReleaseMetadata.cargo_packages(cargo).first.fetch(:checksum)
    end
  end

  def test_reads_hex_license_metadata
    Dir.mktmpdir do |root|
      directory = File.join(root, "deps/jason")
      FileUtils.mkdir_p(directory)
      File.write(File.join(directory, "hex_metadata.config"), "{<<\"licenses\">>,[<<\"Apache-2.0\">>]}.\n")

      assert_equal ["Apache-2.0"], ReleaseMetadata.hex_licenses(root, "jason")
      assert_empty ReleaseMetadata.hex_licenses(root, "missing")
    end
  end

  def test_discovers_mach_o_magic
    Dir.mktmpdir do |root|
      macho = File.join(root, "beam.smp")
      symlink = File.join(root, "beam-link")
      text = File.join(root, "README")
      File.binwrite(macho, [0xFEEDFACF].pack("N") << "payload")
      File.symlink(macho, symlink)
      File.write(text, "not native")

      assert_equal [macho], MachOFiles.list(root)
    end
  end

  def test_reads_bundled_native_dependency
    Dir.mktmpdir do |app|
      release = File.join(app, "Contents/Resources/release")
      binary = File.join(release, "lib/crypto/lib/libcrypto.3.dylib")
      FileUtils.mkdir_p(File.dirname(binary))
      File.binwrite(binary, "signed native library")
      File.write(
        File.join(release, "native-dependencies.json"),
        JSON.generate(
          "dependencies" => [{
            "name" => "openssl",
            "version" => "3.6.3",
            "license" => "Apache-2.0",
            "path" => "lib/crypto/lib/libcrypto.3.dylib"
          }]
        )
      )

      component = ReleaseMetadata.native_components(app).fetch(0)
      assert_equal "pkg:generic/openssl@3.6.3", component.fetch("bom-ref")
      assert_equal Digest::SHA256.hexdigest("signed native library"), component.fetch("hashes").fetch(0).fetch("content")
      assert_equal "Apache-2.0", component.fetch("licenses").fetch(0).fetch("expression")
    end
  end

  def test_writes_tauri_update_manifest_with_signature_and_schema_impact
    Dir.mktmpdir do |directory|
      archive = File.join(directory, "Cuckoding-0.2.0-macos-arm64.app.tar.gz")
      signature = "#{archive}.sig"
      manifest = File.join(directory, "latest.json")
      File.write(archive, "archive")
      File.write(signature, "signed-value\n")

      ReleaseMetadata.write_update_manifest(
        path: manifest,
        version: "0.2.0",
        archive: archive,
        signature: signature,
        base_url: "https://updates.example.test/releases/",
        timestamp: Time.utc(2026, 9, 18, 12)
      )

      parsed = JSON.parse(File.read(manifest))
      assert_equal "0.2.0", parsed.fetch("version")
      assert_equal true, parsed.fetch("schema_change")
      assert_equal "signed-value", parsed.dig("platforms", "darwin-aarch64", "signature")
      assert_equal(
        "https://updates.example.test/releases/Cuckoding-0.2.0-macos-arm64.app.tar.gz",
        parsed.dig("platforms", "darwin-aarch64", "url")
      )
    end
  end

  def test_rejects_non_https_update_base_url
    assert_raises(RuntimeError) do
      ReleaseMetadata.write_update_manifest(
        path: "unused",
        version: "0.2.0",
        archive: "archive",
        signature: "signature",
        base_url: "http://updates.example.test"
      )
    end
  end
end
