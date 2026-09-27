#!/usr/bin/ruby --disable=gems
# frozen_string_literal: true

require "digest"
require "json"

# Code signing changes Mach-O bytes. Verify build hashes before signing, then
# record signed hashes before signing the enclosing application resource seal.
module BridgeManifest
  module_function

  def check(release, refresh: false)
    release = File.realpath(release)
    paths = Dir.glob(File.join(release, "lib/cuckoding-*/priv/agent_bridges/manifest.json"))
    raise "Expected one packaged ACP manifest" unless paths.length == 1

    path = paths.first
    regular_owned_file!(path, release)
    manifest = JSON.parse(File.read(path))
    unless manifest.fetch("schema") == 1 && manifest.fetch("bridges").keys.sort == %w[claude codex]
      raise "Invalid ACP manifest"
    end

    manifest.fetch("bridges").each do |name, entry|
      filename = "#{name}-acp"
      raise "Invalid ACP executable name" unless entry.fetch("executable") == filename

      binary = File.join(File.dirname(path), filename)
      regular_owned_file!(binary, release)
      digest = Digest::SHA256.file(binary).hexdigest
      raise "ACP bridge integrity mismatch" unless refresh || entry.fetch("sha256") == digest

      entry["sha256"] = digest
    end
    File.write(path, JSON.pretty_generate(manifest) + "\n") if refresh
    true
  end

  def regular_owned_file!(path, root)
    stat = File.lstat(path)
    unless stat.file? && (stat.mode & 0o022).zero? && File.realpath(path) == path && path.start_with?(root + "/")
      raise "Unsafe ACP package file"
    end
  end
end

if $PROGRAM_NAME == __FILE__
  raise "Usage: bridge_manifest.rb RELEASE verify|refresh-after-signing" unless ARGV.length == 2 && %w[verify refresh-after-signing].include?(ARGV[1])

  BridgeManifest.check(ARGV[0], refresh: ARGV[1] == "refresh-after-signing")
end
