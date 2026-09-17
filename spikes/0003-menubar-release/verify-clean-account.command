#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "${0%/*}" && pwd)
app="$script_dir/Cuckoding Shell Spike.app"
executable="$app/Contents/MacOS/cuckoding-shell-spike"
release="$app/Contents/Resources/release"
evidence_dir="$script_dir/evidence"
expected_account=${1:-qa}
account=$(/usr/bin/id -un)
uid=$(/usr/bin/id -u)
stamp=$(/bin/date -u +%Y%m%dT%H%M%SZ)
log="$evidence_dir/clean-account-$stamp.log"
shell_pid=
beam_pid=

/bin/mkdir -p "$evidence_dir"
/usr/bin/touch "$log"

exec 3>&1
exec >>"$log" 2>&1

say() {
  /bin/echo "$1" | /usr/bin/tee /dev/fd/3
}

pass() {
  say "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ) PASS $1"
}

fail() {
  say "$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ) FAIL $1"
  exit 1
}

bundle_runtime_alive() {
  [ -n "$beam_pid" ] || return 1
  command=$(/bin/ps -o command= -p "$beam_pid" 2>/dev/null || true)
  case "$command" in
    "$release"/*/bin/beam.smp*) return 0 ;;
    *) return 1 ;;
  esac
}

cleanup() {
  if [ -n "$shell_pid" ] && /bin/kill -0 "$shell_pid" 2>/dev/null; then
    /bin/kill -TERM "$shell_pid" 2>/dev/null || true
    count=0
    while /bin/kill -0 "$shell_pid" 2>/dev/null && [ "$count" -lt 60 ]; do
      /bin/sleep 0.1
      count=$((count + 1))
    done
    /bin/kill -KILL "$shell_pid" 2>/dev/null || true
  fi
  if bundle_runtime_alive; then
    /bin/kill -TERM "$beam_pid" 2>/dev/null || true
    /bin/sleep 1
    /bin/kill -KILL "$beam_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT HUP INT TERM

[ "$account" = "$expected_account" ] || fail "expected account $expected_account, got $account"
[ "$uid" -ne 0 ] || fail "must not run as root"
[ -x "$executable" ] || fail "app executable is missing"
pass "running as separate account $account (uid $uid)"
pass "app bundle is readable and executable"

PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME="$HOME" "$executable" &
shell_pid=$!

count=0
while [ "$count" -lt 200 ]; do
  beam_pid=$(/bin/ps -axo pid=,user=,command= | /usr/bin/awk -v user="$account" -v release="$release" \
    '$2 == user && index($0, release) && index($0, "beam.smp") { print $1; exit }')
  [ -n "$beam_pid" ] && break
  /bin/kill -0 "$shell_pid" 2>/dev/null || fail "app exited before its bundled runtime became ready"
  /bin/sleep 0.1
  count=$((count + 1))
done
[ -n "$beam_pid" ] || fail "bundled runtime did not become ready within 20 seconds"

shell_user=$(/bin/ps -o user= -p "$shell_pid" | /usr/bin/awk '{$1=$1; print}')
beam_user=$(/bin/ps -o user= -p "$beam_pid" | /usr/bin/awk '{$1=$1; print}')
[ "$shell_user" = "$account" ] || fail "shell process belongs to $shell_user"
[ "$beam_user" = "$account" ] || fail "runtime process belongs to $beam_user"
pass "shell and bundled runtime belong to $account"

beam_command=$(/bin/ps -o command= -p "$beam_pid")
case "$beam_command" in
  "$release"/*/bin/beam.smp*) pass "bundled ERTS is running from the app" ;;
  *) fail "runtime is not the app-bundled ERTS" ;;
esac

listeners=
count=0
while [ "$count" -lt 50 ]; do
  listeners=$(/usr/sbin/lsof -nP -a -p "$beam_pid" -iTCP -sTCP:LISTEN 2>/dev/null || true)
  [ -n "$listeners" ] && break
  /bin/sleep 0.1
  count=$((count + 1))
done
[ -n "$listeners" ] || fail "runtime has no TCP listener"
/bin/echo "$listeners" | /usr/bin/awk 'NR > 1 && $0 !~ /127\.0\.0\.1:/ { exit 1 }' || \
  fail "runtime exposed a non-loopback TCP listener"
pass "runtime listens only on loopback"

say ""
say "In the menu bar, open Cuckoding and choose Cuckoding."
say "Confirm the browser shows the authenticated Cuckoding page, then type yes and press Return:"
IFS= read -r browser_confirmation
[ "$browser_confirmation" = "yes" ] || fail "browser handoff was not confirmed"
pass "human confirmed authenticated browser handoff"

/bin/kill -TERM "$shell_pid"
count=0
while /bin/kill -0 "$shell_pid" 2>/dev/null && [ "$count" -lt 80 ]; do
  /bin/sleep 0.1
  count=$((count + 1))
done
/bin/kill -0 "$shell_pid" 2>/dev/null && fail "shell did not exit within 8 seconds"
count=0
while bundle_runtime_alive && [ "$count" -lt 50 ]; do
  /bin/sleep 0.1
  count=$((count + 1))
done
bundle_runtime_alive && fail "bundled runtime survived shell shutdown"
shell_pid=
beam_pid=
pass "quit left no shell or bundled runtime process"
pass "clean-account verification complete"

say "Evidence: $log"
