#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "time"
require "uri"

module ReleaseMetadata
  module_function

  def mix_packages(path)
    File.read(path).scan(/^\s*"([^"]+)": \{:hex, :[^,]+, "([^"]+)", "([0-9a-f]+)"/)
        .to_h { |name, version, checksum| [name, {version: version, checksum: checksum}] }
  end

  def cargo_packages(path)
    File.read(path).split(/^\[\[package\]\]\s*$/).map do |block|
      name = block[/^name = "([^"]+)"$/, 1]
      version = block[/^version = "([^"]+)"$/, 1]
      next unless name && version

      {
        name: name,
        version: version,
        checksum: block[/^checksum = "([0-9a-f]+)"$/, 1]
      }
    end.compact
  end

  def hex_licenses(root, name)
    path = File.join(root, "deps", name, "hex_metadata.config")
    return [] unless File.file?(path)

    block = File.read(path)[/\{<<"licenses">>,\[(.*?)\]\}\./m, 1]
    block ? block.scan(/<<"([^"]+)">>/).flatten : []
  end

  def cargo_metadata(root)
    command = [
      ENV.fetch("RTK_BIN", "rtk"), "proxy", ENV.fetch("CARGO_BIN", "cargo"), "metadata", "--manifest-path",
      File.join(root, "desktop/src-tauri/Cargo.toml"), "--locked", "--offline",
      "--filter-platform", "aarch64-apple-darwin", "--format-version", "1"
    ]
    output, error, status = Open3.capture3({"CARGO_NET_OFFLINE" => "true"}, *command)
    raise "cargo metadata failed: #{error}" unless status.success?

    JSON.parse(output).fetch("packages")
  end

  def release_components(root, app)
    locked = mix_packages(File.join(root, "mix.lock"))
    directories = Dir.glob(File.join(app, "Contents/Resources/release/lib/*"))
                     .select { |path| File.directory?(path) }

    directories.map do |path|
      basename = File.basename(path)
      match = basename.match(/\A(.+)-(\d[^\/]*)\z/)
      next unless match

      name = match[1]
      version = match[2]
      package = locked[name]
      kind = package && package[:version] == version ? "hex" : "otp"
      component = {
        "type" => "library",
        "name" => name,
        "version" => version,
        "bom-ref" => "pkg:#{kind == "hex" ? "hex" : "generic/erlang"}/#{name}@#{version}"
      }
      component["hashes"] = [{"alg" => "SHA-256", "content" => package[:checksum]}] if kind == "hex"
      licenses = hex_licenses(root, name)
      component["licenses"] = licenses.map { |license| {"license" => {"name" => license}} } unless licenses.empty?
      component
    end.compact
  end

  def cargo_components(root)
    locked = cargo_packages(File.join(root, "desktop/src-tauri/Cargo.lock"))
             .to_h { |package| [[package[:name], package[:version]], package] }

    cargo_metadata(root).map do |metadata|
      package = locked.fetch([metadata.fetch("name"), metadata.fetch("version")], {})
      component = {
        "type" => "library",
        "name" => metadata.fetch("name"),
        "version" => metadata.fetch("version"),
        "bom-ref" => "pkg:cargo/#{metadata.fetch("name")}@#{metadata.fetch("version")}"
      }
      component["hashes"] = [{"alg" => "SHA-256", "content" => package[:checksum]}] if package[:checksum]
      license = metadata["license"]
      component["licenses"] = [{"expression" => license}] if license && !license.empty?
      component
    end
  end

  def native_components(app)
    release = File.join(app, "Contents/Resources/release")
    manifest = File.join(release, "native-dependencies.json")
    return [] unless File.file?(manifest)

    JSON.parse(File.read(manifest)).fetch("dependencies").map do |dependency|
      binary = File.join(release, dependency.fetch("path"))
      raise "bundled native dependency is missing: #{binary}" unless File.file?(binary)

      {
        "type" => "library",
        "name" => dependency.fetch("name"),
        "version" => dependency.fetch("version"),
        "bom-ref" => "pkg:generic/#{dependency.fetch("name")}@#{dependency.fetch("version")}",
        "hashes" => [{"alg" => "SHA-256", "content" => Digest::SHA256.file(binary).hexdigest}],
        "licenses" => [{"expression" => dependency.fetch("license")}]
      }
    end
  end

  def git(root, *args)
    output, error, status = Open3.capture3(ENV.fetch("RTK_BIN", "rtk"), "git", "-C", root, *args)
    raise "git #{args.join(" ")} failed: #{error}" unless status.success?

    output.strip
  end

  def generate(root:, app:, archive:, output:, update_archive: nil, update_signature: nil, update_base_url: nil)
    FileUtils.mkdir_p(output)
    version = JSON.parse(File.read(File.join(root, "desktop/src-tauri/tauri.conf.json"))).fetch("version")
    components = (release_components(root, app) + cargo_components(root) + native_components(app))
                 .uniq { |component| component.fetch("bom-ref") }
                 .sort_by { |component| component.fetch("bom-ref") }
    sbom_path = File.join(output, "Cuckoding-#{version}.cdx.json")
    provenance_path = File.join(output, "Cuckoding-#{version}.provenance.json")

    sbom = {
      "bomFormat" => "CycloneDX",
      "specVersion" => "1.6",
      "version" => 1,
      "metadata" => {
        "component" => {
          "type" => "application",
          "name" => "Cuckoding",
          "version" => version,
          "bom-ref" => "pkg:generic/cuckoding@#{version}"
        }
      },
      "components" => components
    }
    File.write(sbom_path, JSON.pretty_generate(sbom) << "\n")

    timestamp = ENV["SOURCE_DATE_EPOCH"] ? Time.at(Integer(ENV.fetch("SOURCE_DATE_EPOCH"))).utc : Time.now.utc
    provenance = {
      "schema" => "https://cuckoding.local/schemas/release-provenance-v1",
      "generated_at" => timestamp.iso8601,
      "subject" => {
        "name" => File.basename(archive),
        "sha256" => Digest::SHA256.file(archive).hexdigest,
        "bytes" => File.size(archive)
      },
      "source" => {
        "revision" => git(root, "rev-parse", "HEAD"),
        "dirty" => !git(root, "status", "--porcelain").empty?
      },
      "build" => {
        "builder" => ENV.fetch("GITHUB_ACTIONS", "false") == "true" ? "github-actions" : "local",
        "target" => "aarch64-apple-darwin",
        "mix_lock_sha256" => Digest::SHA256.file(File.join(root, "mix.lock")).hexdigest,
        "cargo_lock_sha256" => Digest::SHA256.file(File.join(root, "desktop/src-tauri/Cargo.lock")).hexdigest
      }
    }
    File.write(provenance_path, JSON.pretty_generate(provenance) << "\n")

    update_paths = []
    if update_archive && update_signature && update_base_url
      manifest_path = File.join(output, "latest.json")
      write_update_manifest(
        path: manifest_path,
        version: version,
        archive: update_archive,
        signature: update_signature,
        base_url: update_base_url,
        timestamp: timestamp
      )
      update_paths = [update_archive, update_signature, manifest_path]
    end

    checksum_path = File.join(output, "SHA256SUMS")
    paths = [archive, sbom_path, provenance_path] + update_paths
    File.write(checksum_path, paths.map { |path| "#{Digest::SHA256.file(path).hexdigest}  #{File.basename(path)}" }.join("\n") << "\n")
    puts "Generated #{components.length} SBOM components, provenance, and checksums in #{output}"
  end

  def write_update_manifest(path:, version:, archive:, signature:, base_url:, timestamp: Time.now.utc)
    uri = URI.parse(base_url)
    raise "update base URL must use HTTPS" unless uri.is_a?(URI::HTTPS) && uri.host

    manifest = {
      "version" => version,
      "notes" => "https://github.com/mpakus/cuckoding.com/releases/tag/v#{version}",
      "pub_date" => timestamp.utc.iso8601,
      "platforms" => {
        "darwin-aarch64" => {
          "signature" => File.read(signature).strip,
          "url" => "#{base_url.delete_suffix("/")}/#{File.basename(archive)}"
        }
      },
      "schema_change" => true
    }
    File.write(path, JSON.pretty_generate(manifest) << "\n")
  end
end

if $PROGRAM_NAME == __FILE__
  unless [4, 7].include?(ARGV.length)
    abort "usage: release_metadata.rb ROOT APP ARCHIVE OUTPUT [UPDATE_ARCHIVE UPDATE_SIGNATURE UPDATE_BASE_URL]"
  end

  ReleaseMetadata.generate(
    root: ARGV[0],
    app: ARGV[1],
    archive: ARGV[2],
    output: ARGV[3],
    update_archive: ARGV[4],
    update_signature: ARGV[5],
    update_base_url: ARGV[6]
  )
end
