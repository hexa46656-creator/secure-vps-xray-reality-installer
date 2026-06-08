#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
NC="\033[0m"

XRAY_CONFIG="/usr/local/etc/xray/config.json"

log() {
  echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
  echo -e "${RED}[ERROR]${NC} $1"
  exit 1
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "Please run this script as root. Example: sudo -i"
  fi
}

require_root

if [[ -f "${XRAY_CONFIG}" ]]; then
  BACKUP="${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  cp -a "${XRAY_CONFIG}" "${BACKUP}"
  log "Backed up config to: ${BACKUP}"
else
  warn "Xray config not found: ${XRAY_CONFIG}"
fi

log "Updating Xray-core using official installer..."
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install

if ! command -v xray >/dev/null 2>&1; then
  error "xray command not found after update."
fi

log "Current Xray version:"
xray version | head -n1

if [[ -f "${XRAY_CONFIG}" ]]; then
  log "Testing existing config..."
  xray run -test -config "${XRAY_CONFIG}" || error "Xray config test failed after update."
fi

log "Restarting Xray..."
systemctl restart xray

if systemctl is-active --quiet xray; then
  log "Xray updated and running."
else
  journalctl -u xray -e --no-pager || true
  error "Xray failed to start after update."
fi
