#!/usr/bin/env bash
# Start Prometheus + Grafana as native background processes.
#
# Use this on hosts (e.g. Cursor Cloud dev containers) where Docker isn't
# available. Same ports as observability/docker-compose.yml:
#   - Prometheus: http://localhost:19090
#   - Grafana:    http://localhost:3033  (admin / admin)
#
# Runtime state (PIDs, logs, TSDB, sqlite) lives under .runtime/ so you can
# wipe the whole thing with `rm -rf .runtime`.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="${SCRIPT_DIR}/.runtime"
PID_DIR="${RUNTIME_DIR}/pids"
LOG_DIR="${RUNTIME_DIR}/logs"
PROM_DATA="${RUNTIME_DIR}/prometheus-data"
GRAFANA_DATA="${RUNTIME_DIR}/grafana-data"
GRAFANA_PLUGINS="${RUNTIME_DIR}/grafana-plugins"

PROM_BIN="${PROM_BIN:-/opt/prometheus/prometheus}"
GRAFANA_HOMEPATH="${GRAFANA_HOMEPATH:-/usr/share/grafana}"

# Container filesystems are ephemeral on Cursor Cloud / Codespaces / similar.
# If the binaries aren't here (fresh container), bootstrap them. The runtime
# data dir lives in the repo, so it survives container recreation; only the
# binaries need to be re-installed.
if [[ ! -x "${PROM_BIN}" ]] || ! command -v grafana-server >/dev/null 2>&1; then
  echo "observability binaries missing; running install_native.sh"
  "${SCRIPT_DIR}/install_native.sh"
fi

mkdir -p "${PID_DIR}" "${LOG_DIR}" "${PROM_DATA}" "${GRAFANA_DATA}" "${GRAFANA_PLUGINS}"

# Grafana's provisioning file (grafana/provisioning/dashboards/provider.yaml)
# hardcodes /var/lib/grafana/dashboards as the dashboard source — same path
# the Docker bind mount uses. Replicate that natively via a symlink so the
# provider.yaml stays identical to the Docker setup.
DASH_LINK="/var/lib/grafana/dashboards"
DASH_TARGET="${SCRIPT_DIR}/grafana/dashboards"
if [[ ! -L "${DASH_LINK}" || "$(readlink -f "${DASH_LINK}")" != "$(readlink -f "${DASH_TARGET}")" ]]; then
  rm -rf "${DASH_LINK}"
  ln -sfn "${DASH_TARGET}" "${DASH_LINK}"
fi

is_running() {
  local pidfile="$1"
  [[ -f "${pidfile}" ]] && kill -0 "$(cat "${pidfile}")" 2>/dev/null
}

start_prometheus() {
  local pidfile="${PID_DIR}/prometheus.pid"
  if is_running "${pidfile}"; then
    echo "prometheus: already running (pid $(cat "${pidfile}"))"
    return
  fi
  echo "prometheus: starting on :19090"
  nohup "${PROM_BIN}" \
    --config.file="${SCRIPT_DIR}/prometheus.yml" \
    --storage.tsdb.path="${PROM_DATA}" \
    --web.listen-address=":19090" \
    >"${LOG_DIR}/prometheus.log" 2>&1 &
  echo $! >"${pidfile}"
}

start_grafana() {
  local pidfile="${PID_DIR}/grafana.pid"
  if is_running "${pidfile}"; then
    echo "grafana: already running (pid $(cat "${pidfile}"))"
    return
  fi
  echo "grafana: starting on :3033 (admin / admin)"
  # Env-based config — equivalent to the env vars in docker-compose.yml.
  # GF_PATHS_* point Grafana at our repo's provisioning and a local data dir
  # so nothing leaks into /var/lib/grafana except the dashboards symlink.
  GF_SERVER_HTTP_PORT=3033 \
  GF_SECURITY_ADMIN_PASSWORD=admin \
  GF_PATHS_DATA="${GRAFANA_DATA}" \
  GF_PATHS_LOGS="${LOG_DIR}/grafana" \
  GF_PATHS_PLUGINS="${GRAFANA_PLUGINS}" \
  GF_PATHS_PROVISIONING="${SCRIPT_DIR}/grafana/provisioning" \
  nohup grafana server \
    --homepath="${GRAFANA_HOMEPATH}" \
    >"${LOG_DIR}/grafana.stdout.log" 2>&1 &
  echo $! >"${pidfile}"
}

start_prometheus
start_grafana

sleep 1
echo
echo "Status:"
for svc in prometheus grafana; do
  pidfile="${PID_DIR}/${svc}.pid"
  if is_running "${pidfile}"; then
    echo "  ${svc}: running (pid $(cat "${pidfile}")), log ${LOG_DIR}/${svc}.log"
  else
    echo "  ${svc}: FAILED to stay up. Check ${LOG_DIR}/${svc}*.log"
  fi
done
echo
echo "  Prometheus: http://localhost:19090"
echo "  Grafana:    http://localhost:3033  (admin / admin)"
