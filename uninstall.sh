#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
NC="\033[0m"

XRAY_CONFIG_DIR="/usr/local/etc/xray"
XRAY_LOG_DIR="/var/log/xray"
CLIENT_INFO="/root/xray-reality-client.txt"
INSTALLER_STATE="/etc/xray-reality-installer.env"

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

confirm() {
  local prompt="$1"
  read -rp "${prompt} [y/N]: " ans
  [[ "${ans}" =~ ^[Yy]$ ]]
}

load_installer_state() {
  XRAY_PORT=""
  if [[ -f "${INSTALLER_STATE}" ]]; then
    # shellcheck disable=SC1090
    source "${INSTALLER_STATE}"
  fi
  XRAY_PORT="${XRAY_PORT:-8443}"

  if ! [[ "${XRAY_PORT}" =~ ^[0-9]+$ ]]; then
    warn "Invalid XRAY_PORT '${XRAY_PORT}' in installer state. Falling back to 8443."
    XRAY_PORT=8443
  fi
}

require_root
load_installer_state

echo "This will uninstall Xray-core and remove Xray configuration files."
echo "It will NOT modify SSH, UFW, or Fail2ban settings by default."
echo

if ! confirm "Continue uninstalling Xray"; then
  log "Uninstall cancelled."
  exit 0
fi

log "Stopping Xray service..."
systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true

log "Running official Xray remove command if available..."
TMP_INSTALLER="$(mktemp)"
if curl -fsSL -o "${TMP_INSTALLER}" "https://github.com/XTLS/Xray-install/raw/main/install-release.sh"; then
  bash "${TMP_INSTALLER}" remove || warn "Official Xray remove command failed. Continuing with manual cleanup."
else
  warn "Failed to download official Xray installer for removal. Continuing with manual cleanup."
fi
rm -f "${TMP_INSTALLER}"

if [[ -d "${XRAY_CONFIG_DIR}" ]]; then
  BACKUP="/root/xray-config-backup-$(date +%Y%m%d%H%M%S).tar.gz"
  tar -czf "${BACKUP}" "${XRAY_CONFIG_DIR}" 2>/dev/null || true
  log "Backed up Xray config dir to: ${BACKUP}"
  rm -rf "${XRAY_CONFIG_DIR}"
fi

if [[ -d "${XRAY_LOG_DIR}" ]]; then
  rm -rf "${XRAY_LOG_DIR}"
fi

if [[ -f "${INSTALLER_STATE}" ]]; then
  rm -f "${INSTALLER_STATE}"
fi

if [[ -f "${CLIENT_INFO}" ]]; then
  if confirm "Remove client info file ${CLIENT_INFO}"; then
    rm -f "${CLIENT_INFO}"
    log "Removed client info file."
  else
    warn "Kept client info file: ${CLIENT_INFO}"
  fi
fi

if confirm "Remove Xray firewall rule for port ${XRAY_PORT}/tcp"; then
  if command -v ufw >/dev/null 2>&1; then
    ufw delete allow "${XRAY_PORT}/tcp" 2>/dev/null || true
  else
    warn "ufw command not found. Skipping firewall cleanup."
  fi
  log "Attempted to remove UFW rule for port ${XRAY_PORT}/tcp."
fi

log "Uninstall completed."
