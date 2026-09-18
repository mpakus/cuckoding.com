#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: notarize.sh APP ARCHIVE EVIDENCE_DIRECTORY" >&2
  exit 64
fi

app=$1
archive=$2
evidence_dir=$3
profile=${CUCKODING_NOTARY_PROFILE:-}
key_path=${CUCKODING_NOTARY_KEY_PATH:-}
key_id=${CUCKODING_NOTARY_KEY_ID:-}
issuer=${CUCKODING_NOTARY_ISSUER:-}
result="$evidence_dir/notarization-submission.json"
log="$evidence_dir/notarization-log.json"

rtk proxy mkdir -p "$evidence_dir"

if [ -z "$profile" ] && \
  { [ ! -f "$key_path" ] || [ -z "$key_id" ] || [ -z "$issuer" ]; }; then
  echo "set CUCKODING_NOTARY_PROFILE or all three App Store Connect key variables" >&2
  exit 64
fi

if [ ! -d "$app" ] || [ ! -f "$archive" ]; then
  echo "notarization app or archive is missing" >&2
  exit 66
fi

if [ -z "$profile" ]; then
  key_mode=$(rtk proxy /usr/bin/stat -f '%Lp' "$key_path")
  case "$key_mode" in
    400|600) ;;
    *)
      echo "notarization key must be mode 0400 or 0600" >&2
      exit 77
      ;;
  esac
fi

if [ -n "$profile" ]; then
  rtk proxy xcrun notarytool submit "$archive" --keychain-profile "$profile" \
    --wait --output-format json > "$result"
elif [ -f "$key_path" ] && [ -n "$key_id" ] && [ -n "$issuer" ]; then
  rtk proxy xcrun notarytool submit "$archive" --key "$key_path" \
    --key-id "$key_id" --issuer "$issuer" --wait --output-format json > "$result"
else
  echo "invalid notarization credential configuration" >&2
  exit 64
fi

submission_id=$(rtk proxy /usr/bin/plutil -extract id raw -o - "$result")
status=$(rtk proxy /usr/bin/plutil -extract status raw -o - "$result")

if [ -n "$profile" ]; then
  rtk proxy xcrun notarytool log "$submission_id" --keychain-profile "$profile" "$log"
else
  rtk proxy xcrun notarytool log "$submission_id" --key "$key_path" \
    --key-id "$key_id" --issuer "$issuer" "$log"
fi

if [ "$status" != "Accepted" ]; then
  echo "notarization status: $status; inspect $log" >&2
  exit 1
fi

issue_count=$(rtk proxy env -u GEM_HOME -u GEM_PATH PATH=/usr/bin:/bin:/usr/sbin:/sbin \
  /usr/bin/ruby -rjson -e 'puts Array(JSON.parse(File.read(ARGV[0]))["issues"]).length' "$log")
if [ "$issue_count" -ne 0 ]; then
  echo "notarization returned $issue_count issue(s); inspect $log" >&2
  exit 1
fi

rtk proxy xcrun stapler staple "$app"
rtk proxy xcrun stapler validate "$app"
rtk proxy /usr/sbin/spctl --assess --type execute --verbose=4 "$app"
echo "Notarization accepted, logged, stapled, and Gatekeeper-verified"
