#!/usr/bin/env bash
# Runs `k pg:proxy` with CRuby and with a compiled k against a Postgres 17 container using SCRAM-SHA-256
# authentication, sends queries through it with psql (including a failing connection and Ctrl-C), and
# compares the queries' results, the proxy's output and its kubectl calls. Both with and without
# K_LISTEN_ON_ALL_INTERFACES.
#
# Usage: spinel/compare/pg-proxy.sh <k executable>
#
# Needs docker, psql, socat and python3. RUBY selects the Ruby running k (default: ruby on PATH).
# POSTGRES_PORT sets the port Postgres is published on (default: 54329). Exits non-zero on any difference.

set -u

HARNESS=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HARNESS/../.." && pwd)
COMPILED_K=$(cd "$(dirname "${1:?usage: $0 <k executable>}")" && pwd)/$(basename "$1")
RUBY=${RUBY:-ruby}
export POSTGRES_PORT=${POSTGRES_PORT:-54329}
WORK=$(cd "$(mktemp -d)" && pwd -P)
CONTAINER=k-compare-pg-proxy-$$

stop_port_forwards() { # which a crashing proxy can leave behind, holding their ports
  pkill -f "TCP-LISTEN:[0-9]*,bind=127.0.0.1,reuseaddr,fork TCP:127.0.0.1:$POSTGRES_PORT" 2> /dev/null
}

cleanup() {
  docker rm --force "$CONTAINER" > /dev/null 2>&1
  stop_port_forwards
  rm -rf "$WORK"
}
trap cleanup EXIT

docker run --detach --name "$CONTAINER" --publish "127.0.0.1:$POSTGRES_PORT:5432" \
  --env POSTGRES_PASSWORD=postgres postgres:17-alpine > /dev/null || exit 1
for _ in $(seq 1 60); do
  PGPASSWORD=postgres psql -h 127.0.0.1 -p "$POSTGRES_PORT" -U postgres -tAc "select 1" > /dev/null 2>&1 && break
  sleep 0.5
done
PGPASSWORD=postgres psql -q -h 127.0.0.1 -p "$POSTGRES_PORT" -U postgres \
  -c "create role app login password 's3cret'" -c "create database app owner app" || exit 1

bash "$HARNESS/setup.sh" "$WORK/home" > /dev/null

run_proxy() { # executable..., writes to $out
  : > "$out/kubectl-calls.log"
  (
    cd "$WORK/home/.k/demo" || exit 1
    # Run with SIGINT's default disposition, which a background job of a non-interactive shell lacks
    HOME="$WORK/home" PATH="$HARNESS/fakebin-pg-proxy:$PATH" FAKE_KUBECTL_LOG="$out/kubectl-calls.log" \
      python3 -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
      "$@" pg:proxy > "$out/proxy.out" 2>&1 &
    proxy=$!
    for _ in $(seq 1 50); do grep -q "Listening" "$out/proxy.out" 2> /dev/null && break; sleep 0.2; done

    query() { # name, database, sql
      PGCONNECT_TIMEOUT=15 psql -h localhost -p 10000 -U whoever -d "$2" -tAc "$3" > "$out/$1.out" 2>&1
      echo "exit $?" >> "$out/$1.out"
    }
    query q1 app-db "select current_user, current_database(), 6 * 7"
    query q2 app-db "select count(*), sum(n) from generate_series(1, 100000) n"
    query q3 no-such-db "select 1"
    query q4 app-db "select 'still serving'"

    # Let the proxy finish logging the last connection before interrupting it
    for _ in $(seq 1 15); do
      size=$(wc -c < "$out/proxy.out")
      sleep 1
      [ "$(wc -c < "$out/proxy.out")" = "$size" ] && break
    done
    kill -INT $proxy
    wait $proxy
    echo "proxy exit $?" >> "$out/proxy.out"
  )
  stop_port_forwards
}

failed=0
for listen_on_all in false true; do
  for side in ruby compiled; do
    out="$WORK/$side-$listen_on_all"
    mkdir -p "$out"
    if [ $side = ruby ]; then executable=("$RUBY" "$ROOT/k"); else executable=("$COMPILED_K"); fi
    K_LISTEN_ON_ALL_INTERFACES=$listen_on_all run_proxy "${executable[@]}"
  done

  label="pg:proxy (K_LISTEN_ON_ALL_INTERFACES=$listen_on_all)"
  if ! grep -q "^app|app|42$" "$WORK/ruby-$listen_on_all/q1.out"; then
    failed=$((failed + 1))
    printf "FAILED   %s: the proxy doesn't work with CRuby either\n" "$label"
    cat "$WORK/ruby-$listen_on_all/q1.out" "$WORK/ruby-$listen_on_all/proxy.out"
  elif diff -r "$WORK/ruby-$listen_on_all" "$WORK/compiled-$listen_on_all" > "$WORK/diff"; then
    printf "same     %-45s %s\n" "$label" "$(tr '\n' ' ' < "$WORK/compiled-$listen_on_all/q1.out")"
  else
    failed=$((failed + 1))
    printf "DIFFERS  %s\n" "$label"
    head -40 "$WORK/diff"
  fi
done

[ "$failed" -eq 0 ]
