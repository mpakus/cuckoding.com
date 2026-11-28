#!/usr/bin/env bash
# Claim this tag before notarytool submit. A duplicate asset must never be overwritten.
set -euo pipefail
submitted="${1:?expected signed DMG path}"
test -f "$submitted"
tag="${GITHUB_REF_NAME:?}"
sha="$(git rev-parse HEAD)"
test "$(gh api "repos/$GITHUB_REPOSITORY/commits/$tag" --jq .sha)" = "$sha"
test "$(gh release view "$tag" --json isDraft --jq .isDraft)" = true
folder="$(dirname "$submitted")"
intent="$folder/NOTARY_REQUEST.json"
if [[ $# == 2 ]]; then
  receipt="$folder/NOTARY_SUBMISSION.json"
  jq -e --arg id "$2" 'select(.submission_id == $id) | {submission_id,submitted_sha256}' "$folder/NOTARIZATION.json" > "$receipt"
  gh release upload "$tag" "$receipt"
  exit 0
fi
digest="$(shasum -a 256 "$submitted" | cut -d ' ' -f 1)"
archive_sha="$(jq -er '.source_archive_sha256' "$(dirname "$submitted")/SIGNING_INFO.json")"
jq -n --arg archive "$archive_sha" --arg tag "$tag" --arg sha "$sha" --arg hash "$digest" \
  --arg run "$GITHUB_RUN_ID" --arg attempt "$GITHUB_RUN_ATTEMPT" \
  '{tag:$tag, commit:$sha, source_archive_sha256:$archive, submitted_sha256:$hash, run_id:$run, run_attempt:$attempt}' > "$intent"
gh release upload "$tag" "$intent"
gh release upload "$tag" "$submitted"
