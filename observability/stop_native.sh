#!/usr/bin/env bash
# Stop the native Prometheus + Grafana started by run_native.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_DIR="${SCRIPT_DIR}/.runtime/pids"

for svc in prometheus grafana; do
  pidfile="${PID_DIR}/${svc}.pid"
  if [[ -f "${pidfile}" ]]; then
    pid="$(cat "${pidfile}")"
    if kill -0 "${pid}" 2>/dev/null; then
      echo "${svc}: stopping pid ${pid}"
      kill "${pid}" || true
      # Give it 10s to exit gracefully, then SIGKILL.
      for _ in $(seq 1 10); do
        kill -0 "${pid}" 2>/dev/null || break
        sleep 1
      done
      if kill -0 "${pid}" 2>/dev/null; then
        echo "${svc}: still alive, sending SIGKILL"
        kill -9 "${pid}" || true
      fi
    else
      echo "${svc}: not running (stale pidfile)"
    fi
    rm -f "${pidfile}"
  else
    echo "${svc}: no pidfile, nothing to do"
  fi
done
