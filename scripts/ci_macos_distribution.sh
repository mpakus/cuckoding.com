#!/bin/bash
set -eu
exec python3 -B "$(dirname "$0")/ci_macos_distribution.py" "$@"
