#!/bin/sh
set -eu

script_dir=${0%/*}
desktop_dir=$(CDPATH= cd -- "$script_dir" && pwd)
app=${1:-"$desktop_dir/src-tauri/target/release/bundle/macos/Cuckoding.app"}
identity=${CUCKODING_SIGNING_IDENTITY:-}
entitlements="$desktop_dir/entitlements/beam.plist"
main="$app/Contents/MacOS/cuckoding-shell"
files=$(rtk proxy mktemp "${TMPDIR:-/tmp}/cuckoding-mach-o.XXXXXX")

cleanup() { rtk proxy rm -f "$files" "$files.entitlements" "$files.details"; }
trap cleanup EXIT HUP INT TERM

if [ -z "$identity" ]; then
  echo "CUCKODING_SIGNING_IDENTITY is required" >&2
  exit 64
fi

if [ ! -x "$main" ]; then
  echo "Cuckoding app bundle is missing: $app" >&2
  exit 66
fi

if rtk proxy find "$app" -type f -name '*.cstemp' -print -quit | rtk rg -q .; then
  echo "bundle contains an interrupted codesign temporary file; rebuild it first" >&2
  exit 65
fi

rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/ruby \
  "$desktop_dir/mach_o_files.rb" "$app" > "$files"

if ! beam=$(rtk rg '/beam\.smp$' "$files"); then
  echo "bundled BEAM executable was not found" >&2
  exit 65
fi

while IFS= read -r path; do
  [ "$path" = "$main" ] && continue

  if [ "${path##*/}" = "beam.smp" ]; then
    rtk proxy /usr/bin/codesign --force --options runtime --timestamp \
      --entitlements "$entitlements" --sign "$identity" "$path"
  else
    rtk proxy /usr/bin/codesign --force --options runtime --timestamp \
      --sign "$identity" "$path"
  fi
done < "$files"

rtk proxy /usr/bin/codesign --force --options runtime --timestamp \
  --sign "$identity" "$main"
rtk proxy /usr/bin/codesign --force --options runtime --timestamp \
  --sign "$identity" "$app"

rtk proxy /usr/bin/codesign --display --verbose=4 "$app" > /dev/null 2> "$files.details"
rtk rg -q 'flags=.*runtime' "$files.details"
team=
if [ "$identity" != "-" ]; then
  rtk rg -q '^Timestamp=' "$files.details"
  team=$(rtk proxy /usr/bin/sed -n 's/^TeamIdentifier=//p' "$files.details")
  if [ -z "$team" ] || [ "$team" = "not set" ]; then
    echo "signed app has no Developer ID TeamIdentifier" >&2
    exit 1
  fi
fi

while IFS= read -r path; do
  rtk proxy /usr/bin/codesign --verify --strict --verbose=2 "$path"
  rtk proxy /usr/bin/codesign --display --verbose=4 "$path" > /dev/null 2> "$files.details"
  rtk rg -q 'flags=.*runtime' "$files.details"
  if [ -n "$team" ]; then
    rtk rg -Fq "TeamIdentifier=$team" "$files.details"
    rtk rg -q '^Timestamp=' "$files.details"
  fi
done < "$files"

rtk proxy /usr/bin/codesign --verify --deep --strict --verbose=2 "$app"
rtk proxy /usr/bin/codesign --display --entitlements :- "$beam" \
  > "$files.entitlements" 2> /dev/null
rtk proxy /usr/libexec/PlistBuddy -c 'Print :com.apple.security.cs.allow-jit' \
  "$files.entitlements" | rtk rg -q '^true$'

if rtk proxy /usr/bin/codesign --display --entitlements :- "$app" 2> /dev/null | \
  rtk rg -q 'com\.apple\.security\.get-task-allow'; then
  echo "release app must not include get-task-allow" >&2
  exit 1
fi

count=$(rtk wc -l < "$files" | rtk tr -d ' ')
echo "Signed and verified $count Mach-O files in $app"
