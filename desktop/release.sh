#!/bin/sh
set -eu

script_dir=${0%/*}
desktop_dir=$(CDPATH= cd -- "$script_dir" && pwd)
root_dir=$(CDPATH= cd -- "$desktop_dir/.." && pwd)
app="$desktop_dir/src-tauri/target/release/bundle/macos/Cuckoding.app"
dist="$desktop_dir/dist"
version=$(rtk proxy env -u GEM_HOME -u GEM_PATH /usr/bin/ruby -rjson \
  -e 'puts JSON.parse(File.read(ARGV[0])).fetch("version")' \
  "$desktop_dir/src-tauri/tauri.conf.json")
archive="$dist/Cuckoding-$version-macos-arm64.zip"
notary_archive=$(rtk proxy mktemp "${TMPDIR:-/tmp}/Cuckoding-notary.XXXXXX.zip")

cleanup() { rtk proxy rm -f "$notary_archive"; }
trap cleanup EXIT HUP INT TERM

if [ "$(rtk proxy uname -s)" != "Darwin" ] || [ "$(rtk proxy uname -m)" != "arm64" ]; then
  echo "release.sh requires an Apple Silicon Mac" >&2
  exit 69
fi

if [ -z "${CUCKODING_SIGNING_IDENTITY:-}" ]; then
  echo "CUCKODING_SIGNING_IDENTITY is required" >&2
  exit 64
fi

if [ -z "${CUCKODING_NOTARY_PROFILE:-}" ] && \
  { [ -z "${CUCKODING_NOTARY_KEY_PATH:-}" ] || \
    [ -z "${CUCKODING_NOTARY_KEY_ID:-}" ] || \
    [ -z "${CUCKODING_NOTARY_ISSUER:-}" ]; }; then
  echo "notarization credentials are required" >&2
  exit 64
fi

if [ -n "$(rtk git -C "$root_dir" status --porcelain)" ]; then
  echo "release builds require a clean worktree" >&2
  exit 65
fi

rtk proxy sh "$desktop_dir/build.sh"
rtk proxy sh "$desktop_dir/sign.sh" "$app"
rtk proxy rm -rf "$dist"
rtk proxy mkdir -p "$dist"
rtk proxy ditto -c -k --keepParent "$app" "$notary_archive"
rtk proxy sh "$desktop_dir/notarize.sh" "$app" "$notary_archive" "$dist/evidence"
rtk proxy rm -f "$archive"
rtk proxy ditto -c -k --keepParent "$app" "$archive"
rtk proxy env -u GEM_HOME -u GEM_PATH /usr/bin/ruby \
  "$desktop_dir/release_metadata.rb" "$root_dir" "$app" "$archive" "$dist"

echo "Release artifact: $archive"
