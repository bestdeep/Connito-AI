#!/usr/bin/env bash
# Install Prometheus + Grafana as native binaries on Ubuntu.
#
# Idempotent: safe to re-run. Skips work that's already done. Designed for
# ephemeral containers (Cursor Cloud, Codespaces, etc.) that get recreated
# periodically and lose anything installed under the container fs.
#
# Companion to run_native.sh / stop_native.sh; the run script invokes this
# automatically if the binaries aren't present.

set -euo pipefail

PROM_VERSION="${PROM_VERSION:-3.11.3}"
PROM_DIR="/opt/prometheus"
PROM_BIN="${PROM_DIR}/prometheus"

need_apt_update=0

ensure_pkg() {
  local pkg="$1"
  if ! dpkg -s "${pkg}" >/dev/null 2>&1; then
    if [[ "${need_apt_update}" -eq 0 ]]; then
      apt-get update -qq
      need_apt_update=1
    fi
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${pkg}"
  fi
}

install_prometheus() {
  if [[ -x "${PROM_BIN}" ]]; then
    echo "prometheus: already installed ($("${PROM_BIN}" --version 2>&1 | head -1))"
    return
  fi
  echo "prometheus: installing v${PROM_VERSION}"
  ensure_pkg curl
  ensure_pkg ca-certificates
  local tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "${tmp}"' RETURN
  curl -fL --retry 3 -o "${tmp}/prom.tar.gz" \
    "https://github.com/prometheus/prometheus/releases/download/v${PROM_VERSION}/prometheus-${PROM_VERSION}.linux-amd64.tar.gz"
  tar -xzf "${tmp}/prom.tar.gz" -C "${tmp}"
  mkdir -p "${PROM_DIR}"
  cp -r "${tmp}/prometheus-${PROM_VERSION}.linux-amd64/." "${PROM_DIR}/"
  echo "prometheus: $(${PROM_BIN} --version 2>&1 | head -1)"
}

install_grafana() {
  if command -v grafana-server >/dev/null 2>&1 || command -v grafana >/dev/null 2>&1; then
    echo "grafana: already installed"
    return
  fi
  echo "grafana: installing from apt.grafana.com"
  ensure_pkg curl
  ensure_pkg gnupg
  ensure_pkg ca-certificates
  install -d /etc/apt/keyrings
  if [[ ! -s /etc/apt/keyrings/grafana.gpg ]]; then
    curl -fsSL https://apt.grafana.com/gpg.key \
      | gpg --dearmor --yes -o /etc/apt/keyrings/grafana.gpg
  fi
  echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" \
    > /etc/apt/sources.list.d/grafana.list
  apt-get update -qq
  need_apt_update=1
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends grafana
}

install_prometheus
install_grafana

echo
echo "Done. Start the stack with: ./run_native.sh"
