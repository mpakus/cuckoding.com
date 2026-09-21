#!/bin/sh
set -eu

script_dir=${0%/*}
desktop_dir=$(CDPATH= cd -- "$script_dir" && pwd)
root_dir=$(CDPATH= cd -- "$desktop_dir/.." && pwd)
app="$desktop_dir/src-tauri/target/release/bundle/macos/Cuckoding.app"
final_dist="$desktop_dir/dist"
rtk_bin=$(rtk which rtk)
cargo_bin=$(rtk proxy rustup which --toolchain 1.90.0 cargo)
toolchain_bin=${cargo_bin%/*}
tauri_cli=$(rtk proxy which cargo-tauri)
version=$(rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin /usr/bin/ruby -rjson \
  -e 'puts JSON.parse(File.read(ARGV[0])).fetch("version")' \
  "$desktop_dir/src-tauri/tauri.conf.json")
notary_archive=$(rtk proxy mktemp "${TMPDIR:-/tmp}/Cuckoding-notary.XXXXXX.zip")
temporary_updater_key=""
candidate=""
updater_private_path=${TAURI_SIGNING_PRIVATE_KEY_PATH:-}
updater_private_password=${TAURI_SIGNING_PRIVATE_KEY_PASSWORD:-}

cleanup() {
  rtk proxy rm -f "$notary_archive" ${temporary_updater_key:+"$temporary_updater_key"}
  if [ -n "$candidate" ] && [ -d "$candidate" ]; then
    echo "Incomplete release candidate retained for inspection: $candidate" >&2
  fi
}
trap cleanup EXIT HUP INT TERM

if [ -n "${TAURI_SIGNING_PRIVATE_KEY:-}" ]; then
  temporary_updater_key=$(rtk proxy mktemp "${TMPDIR:-/tmp}/Cuckoding-updater.XXXXXX.key")
  rtk proxy chmod 600 "$temporary_updater_key"
  printf '%s' "$TAURI_SIGNING_PRIVATE_KEY" > "$temporary_updater_key"
  updater_private_path=$temporary_updater_key
fi

unset TAURI_SIGNING_PRIVATE_KEY TAURI_SIGNING_PRIVATE_KEY_PATH TAURI_SIGNING_PRIVATE_KEY_PASSWORD

if [ "$(rtk proxy uname -s)" != "Darwin" ] || [ "$(rtk proxy uname -m)" != "arm64" ]; then
  echo "release.sh requires an Apple Silicon Mac" >&2
  exit 69
fi

if [ -z "${CUCKODING_SIGNING_IDENTITY:-}" ]; then
  echo "CUCKODING_SIGNING_IDENTITY is required" >&2
  exit 64
fi

if [ -z "${CUCKODING_UPDATE_ENDPOINT:-}" ] || \
  [ -z "${CUCKODING_UPDATER_PUBLIC_KEY:-}" ] || \
  [ -z "${CUCKODING_UPDATE_BASE_URL:-}" ]; then
  echo "CUCKODING_UPDATE_ENDPOINT, CUCKODING_UPDATER_PUBLIC_KEY, and CUCKODING_UPDATE_BASE_URL are required" >&2
  exit 64
fi

if [ -z "$updater_private_path" ]; then
  echo "TAURI_SIGNING_PRIVATE_KEY or TAURI_SIGNING_PRIVATE_KEY_PATH is required" >&2
  exit 64
fi

if [ -z "$updater_private_password" ]; then
  echo "TAURI_SIGNING_PRIVATE_KEY_PASSWORD is required" >&2
  exit 64
fi

if [ ! -f "$updater_private_path" ] || [ -L "$updater_private_path" ] || \
  [ $((0$(rtk proxy stat -f %Lp "$updater_private_path") & 077)) -ne 0 ]; then
  echo "updater private key must be a non-symlinked private regular file" >&2
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
candidate=$(rtk proxy mktemp -d "$desktop_dir/src-tauri/target/release/Cuckoding-dist.XXXXXX")
archive="$candidate/Cuckoding-$version-macos-arm64.zip"
update_archive="$candidate/Cuckoding-$version-macos-arm64.app.tar.gz"
rtk proxy ditto -c -k --keepParent "$app" "$notary_archive"
rtk proxy sh "$desktop_dir/notarize.sh" "$app" "$notary_archive" "$candidate/evidence"
rtk proxy ditto -c -k --keepParent "$app" "$archive"
rtk proxy tar -czf "$update_archive" -C "${app%/*}" "${app##*/}"
rtk proxy env PATH="$toolchain_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  TAURI_SIGNING_PRIVATE_KEY_PATH="$updater_private_path" \
  TAURI_SIGNING_PRIVATE_KEY_PASSWORD="$updater_private_password" \
  "$tauri_cli" signer sign "$update_archive"
rtk proxy env -u GEM_HOME -u GEM_PATH PATH="$toolchain_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  RTK_BIN="$rtk_bin" CARGO_BIN="$cargo_bin" /usr/bin/ruby \
  "$desktop_dir/release_metadata.rb" "$root_dir" "$app" "$archive" "$candidate" \
  "$update_archive" "$update_archive.sig" "$CUCKODING_UPDATE_BASE_URL"

rtk proxy chmod 755 "$candidate"
rtk proxy sh "$desktop_dir/promote_release.sh" "$candidate" "$final_dist" \
  "$desktop_dir"
candidate=""
echo "Release artifact: $final_dist/${archive##*/}"
echo "Updater artifact: $final_dist/${update_archive##*/}"
