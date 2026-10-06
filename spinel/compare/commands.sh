#!/usr/bin/env bash
# Runs k commands with CRuby and with a compiled k, each from a fresh copy of the fixture home built by
# setup.sh, and compares their stdout, stderr, exit status, written files, git commits and pushes, and
# kubectl calls. stdout and stderr are compared apart, since how they interleave depends on buffering.
#
# Usage: spinel/compare/commands.sh <k executable>
#
# RUBY selects the Ruby running k (default: ruby on PATH). Exits non-zero when any command differs.
# VERBOSE=<n> also prints the last n lines of each command's output.

set -u

HARNESS=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HARNESS/../.." && pwd)
COMPILED_K=$(cd "$(dirname "${1:?usage: $0 <k executable>}")" && pwd)/$(basename "$1")
RUBY=${RUBY:-ruby}
WORK=$(cd "$(mktemp -d)" && pwd -P) # k compares Dir.pwd, a real path, with paths under HOME
trap 'rm -rf "$WORK"' EXIT

bash "$HARNESS/setup.sh" "$WORK/template" > /dev/null

passed=0
failed=0

# Replaces what legitimately differs between runs: random pod names, timestamps in names and the work dir
normalize() {
  perl -pi -e "s/-run-[0-9a-f]{6}/-run-XXXXXX/g; s/(k-context-add|write-access-test)-[0-9]+/\$1-T/g; s#\Q$WORK\E/(ruby|compiled)#WORK/SIDE#g" "$@"
}

compare() { # label, expected exit status with CRuby, stdin, k arguments...
  local label=$1 expected_exit=$2 input=$3
  shift 3

  for side in ruby compiled; do
    rm -rf "${WORK:?}/$side" "$WORK/$side-remotes"
    cp -R "$WORK/template" "$WORK/$side"
    cp -R "$WORK/template-remotes" "$WORK/$side-remotes"
    : > "$WORK/$side.calls"
    if [ $side = ruby ]; then executable=("$RUBY" "$ROOT/k"); else executable=("$COMPILED_K"); fi

    # git@github.com: URLs resolve to bare repos under <side>-remotes through url.insteadOf
    (
      cd "$WORK/$side/.k/demo" &&
      printf "%b" "$input" | env \
        HOME="$WORK/$side" \
        PATH="$HARNESS/fakebin:$PATH" \
        FAKE_KUBECTL_LOG="$WORK/$side.calls" \
        EDITOR="$HARNESS/fakebin/editor" \
        KAIL_PATH="$HARNESS/fakebin/kail" \
        TZ=Europe/Stockholm \
        GIT_TERMINAL_PROMPT=0 \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        GIT_AUTHOR_NAME=Bot GIT_AUTHOR_EMAIL=bot@example.com GIT_COMMITTER_NAME=Bot GIT_COMMITTER_EMAIL=bot@example.com \
        GIT_AUTHOR_DATE=2026-10-01T12:00:00+0200 GIT_COMMITTER_DATE=2026-10-01T12:00:00+0200 \
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="url.$WORK/$side-remotes/.insteadOf" GIT_CONFIG_VALUE_0=git@github.com: \
        "${executable[@]}" "$@" > "$WORK/$side.out" 2> "$WORK/$side.err"
      echo "[exit $?]" >> "$WORK/$side.out"
    )
    (
      cd "$WORK/$side/.k/demo" && git log --format='%s%n%b' -3
      git -C "$WORK/$side-remotes/acme/demo.git" log --format='%s%n%b' -1
    ) > "$WORK/$side.git"
  done
  normalize "$WORK"/{ruby,compiled}.{out,err,calls}

  local differences=""
  # Guards against both sides failing alike, eg. for a tool missing on this machine
  tail -1 "$WORK/ruby.out" | grep -q "\[exit $expected_exit\]$" || differences+=" ruby-exit-status-not-$expected_exit"
  cmp -s "$WORK/ruby.out" "$WORK/compiled.out" || differences+=" stdout"
  cmp -s "$WORK/ruby.err" "$WORK/compiled.err" || differences+=" stderr"
  diff -qr -x .git "$WORK/ruby" "$WORK/compiled" > /dev/null || differences+=" files"
  cmp -s "$WORK/ruby.git" "$WORK/compiled.git" || differences+=" git"
  cmp -s "$WORK/ruby.calls" "$WORK/compiled.calls" || differences+=" kubectl"

  if [ -z "$differences" ]; then
    passed=$((passed + 1))
    printf "same     %-45s %s\n" "$label" "$(tail -1 "$WORK/ruby.out")"
  else
    failed=$((failed + 1))
    printf "DIFFERS  %-45s (%s )\n" "$label" "$differences"
    diff "$WORK/ruby.out" "$WORK/compiled.out" | head -20
    diff "$WORK/ruby.err" "$WORK/compiled.err" | head -20
    diff "$WORK/ruby.calls" "$WORK/compiled.calls" | head -10
    diff "$WORK/ruby.git" "$WORK/compiled.git" | head -10
    diff -r -x .git "$WORK/ruby" "$WORK/compiled" | head -10
  fi
  if [ -n "${VERBOSE:-}" ]; then sed 's/^/           | /' "$WORK/ruby.out" | tail -"$VERBOSE"; fi
}

compare "k" 0 ""
compare "k contexts" 0 "" contexts
compare "k contexts:use other" 0 "" contexts:use other
compare "k contexts:add (prompts)" 0 "\n\n\n\nnone\n" contexts:add git@github.com:acme/third.git
compare "k applications" 0 "" applications
compare "k applications worker" 0 "" applications worker
compare "k releases web-app" 0 "" releases web-app
compare "k rollback web-app (decline)" 0 "2\nn\n" rollback web-app
compare "k rollback web-app (confirm)" 0 "2\ny\n" rollback web-app
compare "k rollback web-app (bad index)" 1 "9\n" rollback web-app
compare "k deploy web-app" 0 "" deploy web-app
compare "k generate" 0 "" generate
compare "k generate bogus" 1 "" generate bogus
compare "k generate application shop" 0 "" generate application shop
compare "k generate deployment (prompt)" 0 "1\n" generate deployment web-app
compare "k generate resource configmap" 0 "" generate resource web-app configmap
compare "k secrets:edit app-env" 0 "" secrets:edit app-env
compare "k config web-app" 0 "" config web-app
compare "k config:edit web-app (shared secret)" 0 "2\n" config:edit web-app
compare "k config:set web-app" 1 "" config:set web-app FOO=bar "QUOTED=a b"
compare "k config:get web-app API_KEY" 0 "" config:get web-app API_KEY
compare "k applicatons (did you mean)" 1 "" applicatons
compare "k pg:psq (did you mean)" 1 "" pg:psq
compare "k nope" 1 "" nope
compare "k run web-app 'exit 3'" 3 "" run web-app "exit 3"
compare "k run web-app ok" 0 "" run web-app "echo hi"
compare "k run web-app (shell syntax)" 0 "" run web-app "echo \"it's\" \$((6 * 7)) | tr a-z A-Z
printf '%s\\n' ünïcode"
compare "k console web-app" 0 "" console web-app
compare "k exec web-app echo hi" 7 "" exec web-app echo hi
compare "k sh web-app" 7 "" sh web-app
compare "k logs web-app" 0 "" logs web-app
compare "k node:failover node-1" 0 "y\n" node:failover node-1
compare "k clickhouse:table-size events" 0 "" clickhouse:table-size events
compare "k clickhouse:table-size empty" 1 "" clickhouse:table-size empty

echo "$passed same, $failed differ"
[ "$failed" -eq 0 ]
