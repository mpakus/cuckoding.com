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
end
