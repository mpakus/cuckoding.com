#!/bin/sh
set -eu

if [ "$#" -ne 3 ]; then
  echo "usage: promote_release.sh CANDIDATE FINAL BACKUP_PARENT" >&2
  exit 64
fi

candidate=$1
final=$2
backup_parent=$3

if [ ! -d "$candidate" ] || [ -L "$candidate" ] || \
  [ ! -s "$candidate/SHA256SUMS" ] || [ ! -s "$candidate/latest.json" ]; then
  echo "release candidate is incomplete or unsafe: $candidate" >&2
  exit 66
fi

if { [ -e "$final" ] || [ -L "$final" ]; } && \
  { [ ! -d "$final" ] || [ -L "$final" ]; }; then
  echo "refusing to replace a non-directory or symlink: $final" >&2
  exit 66
fi

backup=""
if [ -d "$final" ]; then
  backup=$(rtk proxy mktemp -d "$backup_parent/dist-backup.XXXXXX")
  rtk proxy mv "$final" "$backup/dist"
fi

if ! rtk proxy mv "$candidate" "$final"; then
  if [ -n "$backup" ]; then
    rtk proxy mv "$backup/dist" "$final" || \
      echo "Restore the prior release manually from $backup/dist" >&2
  fi
  exit 1
fi

if [ -n "$backup" ]; then
  echo "Previous release retained at $backup/dist"
fi
