#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
NC="\033[0m"

XRAY_CONFIG="/usr/local/etc/xray/config.json"
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

require_tools() {
  command -v xray >/dev/null 2>&1 || error "xray command not found."
  command -v jq >/dev/null 2>&1 || error "jq not found. Install it with: apt install -y jq"
  command -v openssl >/dev/null 2>&1 || error "openssl not found."
}

load_state() {
  if [[ -f "${INSTALLER_STATE}" ]]; then
    # shellcheck disable=SC1090
    source "${INSTALLER_STATE}"
  fi

  XRAY_PORT="${XRAY_PORT:-8443}"
  REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.microsoft.com}"
  REALITY_DEST="${REALITY_DEST:-www.microsoft.com:443}"
  CLIENT_NAME="${CLIENT_NAME:-Ubuntu24-Xray-Reality}"
  SERVER_IP="${SERVER_IP:-}"
}

generate_values() {
  log "Generating new UUID, REALITY key pair, and shortId..."

  UUID="$(xray uuid)"
  KEY_PAIR="$(xray x25519)"
  PRIVATE_KEY="$(echo "${KEY_PAIR}" | awk '/Private key:/ {print $3}')"
  PUBLIC_KEY="$(echo "${KEY_PAIR}" | awk '/Public key:/ {print $3}')"
  SHORT_ID="$(openssl rand -hex 8)"

  if [[ -z "${SERVER_IP}" ]]; then
    SERVER_IP="$(curl -4 -s --max-time 10 https://api.ipify.org || true)"
  fi

  if [[ -z "${SERVER_IP}" ]]; then
    SERVER_IP="$(hostname -I | awk '{print $1}')"
  fi

  if [[ -z "${UUID}" || -z "${PRIVATE_KEY}" || -z "${PUBLIC_KEY}" || -z "${SHORT_ID}" || -z "${SERVER_IP}" ]]; then
    error "Failed to generate required values."
  fi
}

update_config() {
  [[ -f "${XRAY_CONFIG}" ]] || error "Xray config not found: ${XRAY_CONFIG}"

  local backup tmp
  backup="${XRAY_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"
  tmp="$(mktemp)"

  cp -a "${XRAY_CONFIG}" "${backup}"
  log "Backed up config to: ${backup}"

  jq \
    --arg uuid "${UUID}" \
    --arg private_key "${PRIVATE_KEY}" \
    --arg short_id "${SHORT_ID}" \
    '.inbounds[0].settings.clients[0].id = $uuid
     | .inbounds[0].settings.clients[0].flow = "xtls-rprx-vision"
     | .inbounds[0].streamSettings.realitySettings.privateKey = $private_key
     | .inbounds[0].streamSettings.realitySettings.shortIds = [$short_id]' \
    "${XRAY_CONFIG}" > "${tmp}"

  mv "${tmp}" "${XRAY_CONFIG}"

  xray run -test -config "${XRAY_CONFIG}" || {
    warn "New config failed. Restoring backup."
    cp -a "${backup}" "${XRAY_CONFIG}"
    error "Reset failed."
  }
}

save_state() {
  cat > "${INSTALLER_STATE}" <<EOF
XRAY_PORT="${XRAY_PORT}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME}"
REALITY_DEST="${REALITY_DEST}"
CLIENT_NAME="${CLIENT_NAME}"
SERVER_IP="${SERVER_IP}"
EOF

  chmod 600 "${INSTALLER_STATE}"
}

write_client_info() {
  local encoded_name
  encoded_name="$(echo "${CLIENT_NAME}" | sed 's/ /%20/g')"

  VLESS_LINK="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none#${encoded_name}"

  cat > "${CLIENT_INFO}" <<EOF
============================================================
Xray-core VLESS + REALITY + Vision Client Info
============================================================

Server IP:
${SERVER_IP}

Port:
${XRAY_PORT}

UUID:
${UUID}

Flow:
xtls-rprx-vision

Network:
tcp

Security:
reality

SNI / Server Name:
${REALITY_SERVER_NAME}

REALITY Public Key:
${PUBLIC_KEY}

Short ID:
${SHORT_ID}

Fingerprint:
chrome

VLESS Link:
${VLESS_LINK}

Config file:
${XRAY_CONFIG}

Useful commands:
systemctl status xray
journalctl -u xray -e --no-pager
ufw status verbose
fail2ban-client status sshd
xray version

============================================================
EOF

  chmod 600 "${CLIENT_INFO}"

  echo
  echo -e "${BLUE}================= NEW CLIENT INFO =================${NC}"
  cat "${CLIENT_INFO}"
  echo -e "${BLUE}====================================================${NC}"
}

restart_xray() {
  log "Restarting Xray..."
  systemctl restart xray

  if systemctl is-active --quiet xray; then
    log "Xray is running with the new client config."
  else
    journalctl -u xray -e --no-pager || true
    error "Xray failed to start after reset."
  fi
}

main() {
  require_root
  require_tools
  load_state
  generate_values
  update_config
  save_state
  restart_xray
  write_client_info

  log "Client reset completed successfully."
}

main "$@"
