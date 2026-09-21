#!/bin/sh
set -eu

script_dir=${0%/*}
scratch=$(rtk proxy mktemp -d "${TMPDIR:-/tmp}/Cuckoding-promote-test.XXXXXX")
cleanup() {
  [ -n "$scratch" ] && [ -d "$scratch" ] && rtk proxy rm -rf "$scratch"
}
trap cleanup EXIT HUP INT TERM

rtk proxy mkdir -p "$scratch/candidate" "$scratch/dist"
printf 'old\n' > "$scratch/dist/old.txt"
printf 'checksum\n' > "$scratch/candidate/SHA256SUMS"
printf '{}\n' > "$scratch/candidate/latest.json"
printf 'new\n' > "$scratch/candidate/new.txt"
rtk proxy sh "$script_dir/promote_release.sh" "$scratch/candidate" "$scratch/dist" "$scratch"
test "$(rtk proxy sed -n '1p' "$scratch/dist/new.txt")" = new
set -- "$scratch"/dist-backup.*/dist/old.txt
test "$#" -eq 1 && test -f "$1"

rtk proxy mkdir "$scratch/incomplete"
if rtk proxy sh "$script_dir/promote_release.sh" "$scratch/incomplete" "$scratch/dist" "$scratch" 2>/dev/null; then
  echo "incomplete candidate was promoted" >&2
  exit 1
fi
test -f "$scratch/dist/new.txt"

rtk proxy mkdir "$scratch/protected" "$scratch/complete"
printf 'keep\n' > "$scratch/protected/keep.txt"
printf 'checksum\n' > "$scratch/complete/SHA256SUMS"
printf '{}\n' > "$scratch/complete/latest.json"
rtk proxy ln -s "$scratch/protected" "$scratch/link"
if rtk proxy sh "$script_dir/promote_release.sh" "$scratch/complete" "$scratch/link" "$scratch" 2>/dev/null; then
  echo "symlink destination was replaced" >&2
  exit 1
fi
test -f "$scratch/protected/keep.txt" && test -L "$scratch/link"

rtk proxy ln -s "$scratch/missing" "$scratch/broken-link"
if rtk proxy sh "$script_dir/promote_release.sh" "$scratch/complete" "$scratch/broken-link" "$scratch" 2>/dev/null; then
  echo "broken symlink destination was replaced" >&2
  exit 1
fi
test -L "$scratch/broken-link" && test -d "$scratch/complete"
echo "release promotion checks passed"
