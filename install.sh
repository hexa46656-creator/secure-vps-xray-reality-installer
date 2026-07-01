#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Secure VPS Xray Reality Installer
# Ubuntu 24.04 hardening + Xray-core VLESS REALITY Vision
# =========================================================

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m"

XRAY_CONFIG="/usr/local/etc/xray/config.json"
CLIENT_INFO="/root/xray-reality-client.txt"
INSTALLER_STATE="/etc/xray-reality-installer.env"
SHADOWROCKET_CONF_SRC="default.conf"
SHADOWROCKET_CONF_DST="/root/shadowrocket-default.conf"
SSHD_DROPIN="/etc/ssh/sshd_config.d/99-xray-reality-vpsguard.conf"

XRAY_PORT="${XRAY_PORT:-8443}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-speed.cloudflare.com}"
REALITY_DEST="${REALITY_DEST:-speed.cloudflare.com:443}"
REALITY_DNS_STRICT="${REALITY_DNS_STRICT:-warn}"
CLIENT_NAME="${CLIENT_NAME:-VLESS-Reality}"
DEPLOY_USER="${DEPLOY_USER:-alex}"
DEPLOY_USER_PASSWORD="${DEPLOY_USER_PASSWORD:-}"
INSTALLER_CORE_DIR="${INSTALLER_CORE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../vps-installer-core" 2>/dev/null && pwd || true)}"

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

if [[ -n "${INSTALLER_CORE_DIR}" && -f "${INSTALLER_CORE_DIR}/installer_core.sh" ]]; then
  # shellcheck source=/dev/null
  source "${INSTALLER_CORE_DIR}/installer_core.sh"
fi

if ! declare -F installer_core_detect_os >/dev/null 2>&1; then
  installer_core_detect_os() {
    local os_id
    local os_name
    local os_pretty_name
    local init_comm

    if [[ ! -r /etc/os-release ]]; then
      error "Unable to read /etc/os-release."
    fi

    # shellcheck disable=SC1091
    . /etc/os-release

    os_id="${ID:-unknown}"
    os_name="${NAME:-${ID:-unknown}}"
    os_pretty_name="${PRETTY_NAME:-${os_name}}"

    case "${os_id}" in
      ubuntu|debian) ;;
      *) error "Unsupported OS: ${os_pretty_name}. This installer only supports Ubuntu or Debian." ;;
    esac

    init_comm="$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "${init_comm}" != "systemd" && ! -d /run/systemd/system ]]; then
      error "systemd is required but not available on this system."
    fi

    # shellcheck disable=SC2034
    INSTALLER_OS_ID="${os_id}"
    # shellcheck disable=SC2034
    INSTALLER_OS_NAME="${os_name}"
    # shellcheck disable=SC2034
    INSTALLER_OS_VERSION_ID="${VERSION_ID:-unknown}"
    # shellcheck disable=SC2034
    INSTALLER_OS_PRETTY_NAME="${os_pretty_name}"
  }
fi

if ! declare -F installer_core_install_packages >/dev/null 2>&1; then
  installer_core_install_packages() {
    local packages=("$@")

    if [[ "${#packages[@]}" -eq 0 ]]; then
      return 0
    fi

    export DEBIAN_FRONTEND=noninteractive

    if command -v apt-get >/dev/null 2>&1; then
      apt-get update
      apt-get install -y "${packages[@]}"
    else
      apt update
      apt install -y "${packages[@]}"
    fi
  }
fi

if ! declare -F installer_core_subscription_protocol_defaults >/dev/null 2>&1; then
  installer_core_subscription_protocol_defaults() {
    SUBSCRIPTION_ACCESS_URL="${SUBSCRIPTION_ACCESS_URL:-${VLESS_LINK:-}}"
  }
fi

if ! declare -F installer_core_publish_subscription >/dev/null 2>&1; then
  installer_core_publish_subscription() {
    SUBSCRIPTION_ACCESS_URL="${SUBSCRIPTION_ACCESS_URL:-${VLESS_LINK:-}}"
  }
fi

if ! declare -F installer_core_mode_label >/dev/null 2>&1; then
  installer_core_mode_label() {
    printf '%s\n' "standalone"
  }
fi

if ! declare -F installer_core_print_completion_block >/dev/null 2>&1; then
  installer_core_print_completion_block() {
    local mode="${1:-standalone}"
    local access_url="${2:-${SUBSCRIPTION_ACCESS_URL:-${VLESS_LINK:-${HY2_URI:-${TROJAN_URI:-}}}}}"
    local clients="${3:-}"

    echo
    echo "========== Completion =========="
    echo "[MODE] ${mode}"
    if [[ -n "${access_url}" ]]; then
      echo "[LINK] ${access_url}"
    fi
    if [[ -n "${clients}" ]]; then
      echo "[CLIENTS] ${clients}"
    fi
    echo "================================"
  }
fi

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    error "Please run this script as root. Example: sudo -i"
  fi
}

check_os() {
  installer_core_detect_os
  log "Detected supported OS: ${INSTALLER_OS_PRETTY_NAME}"
}

detect_ssh_port() {
  SSH_PORT="$(ss -tlnp 2>/dev/null | awk '/sshd/ {print $4}' | awk -F: '{print $NF}' | head -n1 || true)"

  if [[ -z "${SSH_PORT}" ]]; then
    SSH_PORT="$(grep -Ei '^\s*Port\s+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $NF}' | tail -n1 || true)"
  fi

  SSH_PORT="${SSH_PORT:-22}"
  log "Detected SSH port: ${SSH_PORT}"
}

extract_reality_dest_host() {
  local dest="${1:-${REALITY_DEST}}"

  if [[ "${dest}" =~ ^\[([0-9A-Fa-f:.]+)\]:(.+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "${dest}" == *:* ]]; then
    printf '%s\n' "${dest%:*}"
    return 0
  fi

  printf '%s\n' "${dest}"
}

check_reality_dns_health() {
  local dest_host
  local system_dns
  local cloudflare_dns
  local google_dns
  local mismatch=0

  dest_host="$(extract_reality_dest_host "${REALITY_DEST}")"
  system_dns="$(dig +short A "${dest_host}" 2>/dev/null | awk 'NR==1 {print $1}')"
  cloudflare_dns="$(dig +short A "${dest_host}" @1.1.1.1 2>/dev/null | awk 'NR==1 {print $1}')"
  google_dns="$(dig +short A "${dest_host}" @8.8.8.8 2>/dev/null | awk 'NR==1 {print $1}')"

  log "Reality DNS health for ${dest_host}"
  log "  system DNS: ${system_dns:-<empty>}"
  log "  1.1.1.1: ${cloudflare_dns:-<empty>}"
  log "  8.8.8.8: ${google_dns:-<empty>}"

  if [[ -z "${system_dns}" || -z "${cloudflare_dns}" || -z "${google_dns}" ]]; then
    warn "One or more Reality DNS lookups returned no A record."
    mismatch=1
  fi

  if [[ -n "${system_dns}" && -n "${cloudflare_dns}" && -n "${google_dns}" ]]; then
    if [[ "$({ printf '%s
' "${system_dns}" "${cloudflare_dns}" "${google_dns}" | awk 'NF' | sort -u | wc -l | tr -d ' '; })" -gt 1 ]]; then
      warn "Reality DNS lookups returned different A records across resolvers."
      mismatch=1
    fi
  fi

  if [[ "${dest_host}" != "${REALITY_SERVER_NAME}" ]]; then
    warn "REALITY_DEST host (${dest_host}) differs from REALITY_SERVER_NAME (${REALITY_SERVER_NAME})."
    mismatch=1
  fi

  if [[ "${mismatch}" -ne 0 && "${REALITY_DNS_STRICT}" == "fail" ]]; then
    error "Reality DNS health check failed under REALITY_DNS_STRICT=fail."
  fi
}

install_packages() {
  installer_core_install_packages \
    curl wget unzip jq socat ufw fail2ban ca-certificates gnupg lsb-release openssl iproute2 sudo dnsutils qrencode
}

print_client_qr() {
  local client_url="${1:-}"
  local output_file="${2:-}"

  if [[ -z "${client_url}" ]]; then
    echo "[WARN] Client URL is empty, skip QR code generation."
    return 0
  fi

  if [[ -z "${output_file}" ]]; then
    output_file="/root/secure-vps-xray-reality-qr.png"
  fi

  if ! command -v qrencode >/dev/null 2>&1; then
    echo "[INFO] Installing qrencode..."
    if command -v apt >/dev/null 2>&1; then
      apt update >/dev/null 2>&1 || true
      apt install -y qrencode >/dev/null 2>&1 || true
    elif command -v apt-get >/dev/null 2>&1; then
      apt-get update >/dev/null 2>&1 || true
      apt-get install -y qrencode >/dev/null 2>&1 || true
    fi
  fi

  if ! command -v qrencode >/dev/null 2>&1; then
    echo "[WARN] qrencode is not available, skip QR code generation."
    echo "[INFO] Client URL:"
    echo "${client_url}"
    return 0
  fi

  echo
  echo "========== Client QR Code =========="
  if ! qrencode -t ANSIUTF8 "${client_url}"; then
    echo "[WARN] Failed to render QR code in terminal."
  fi

  if qrencode -o "${output_file}" "${client_url}"; then
    chmod 600 "${output_file}"
    echo
    echo "[OK] QR code saved to: ${output_file}"
  else
    echo "[WARN] Failed to save QR code PNG."
  fi

  echo
  echo "Mobile import:"
  echo "1. Open Shadowrocket / v2rayNG / Hiddify / NekoBox"
  echo "2. Tap scan QR code"
  echo "3. Scan the QR code above"
  echo "4. Save and test the node"
}

backup_file() {
  local file="$1"
  if [[ -f "${file}" ]]; then
    cp -a "${file}" "${file}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

create_deploy_user() {
  log "Preparing deploy user: ${DEPLOY_USER}"

  if [[ ! "${DEPLOY_USER}" =~ ^[a-z_][a-z0-9_-]*[$]?$ ]]; then
    error "Invalid DEPLOY_USER: ${DEPLOY_USER}"
  fi

  if ! id "${DEPLOY_USER}" >/dev/null 2>&1; then
    log "User ${DEPLOY_USER} does not exist. Creating it without password login."
    adduser --disabled-password --gecos "" "${DEPLOY_USER}"
  else
    log "User ${DEPLOY_USER} already exists. Reusing it."
  fi

  usermod -aG sudo "${DEPLOY_USER}"

  if [[ -n "${DEPLOY_USER_PASSWORD}" ]]; then
    echo "${DEPLOY_USER}:${DEPLOY_USER_PASSWORD}" | chpasswd
    warn "A password was set for ${DEPLOY_USER}, but SSH password login remains disabled by default."
  fi

  mkdir -p "/home/${DEPLOY_USER}/.ssh"
  chmod 700 "/home/${DEPLOY_USER}/.ssh"

  if [[ -f /root/.ssh/authorized_keys && ! -e "/home/${DEPLOY_USER}/.ssh/authorized_keys" ]]; then
    cp /root/.ssh/authorized_keys "/home/${DEPLOY_USER}/.ssh/authorized_keys"
    chmod 600 "/home/${DEPLOY_USER}/.ssh/authorized_keys"
    log "Copied root authorized_keys to /home/${DEPLOY_USER}/.ssh/authorized_keys."
  elif [[ -e "/home/${DEPLOY_USER}/.ssh/authorized_keys" ]]; then
    log "Keeping existing /home/${DEPLOY_USER}/.ssh/authorized_keys unchanged."
  else
    warn "No SSH key was copied for ${DEPLOY_USER}. Confirm key access before closing this session."
  fi

  chown -R "${DEPLOY_USER}:${DEPLOY_USER}" "/home/${DEPLOY_USER}/.ssh"

  log "Deploy user is ready: ${DEPLOY_USER}"
}

harden_ssh_safe() {
  log "Applying VPSGuard-compatible SSH hardening..."

  backup_file /etc/ssh/sshd_config
  backup_file "${SSHD_DROPIN}"

  mkdir -p /etc/ssh/sshd_config.d

  cat > "${SSHD_DROPIN}" <<EOF
# Managed by secure-vps-xray-reality-installer.
# Compatible with VPSGuard-style SSH hardening.
PermitRootLogin no
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
EOF

  sshd -t || error "SSH config test failed. Check /etc/ssh/sshd_config"
  verify_effective_ssh_config

  reload_ssh_service
  verify_ssh_listening

  log "SSH hardening completed: root login disabled, public key auth enabled, password and keyboard-interactive auth disabled."
}

verify_effective_ssh_config() {
  local effective_config
  effective_config="$(sshd -T)"

  echo "${effective_config}" | grep -qi '^permitrootlogin no$' || error "Effective SSH config must keep PermitRootLogin no."
  echo "${effective_config}" | grep -qi '^pubkeyauthentication yes$' || error "Effective SSH config must keep PubkeyAuthentication yes."
  echo "${effective_config}" | grep -qi '^passwordauthentication no$' || error "Effective SSH config must keep PasswordAuthentication no."
  echo "${effective_config}" | grep -qi '^kbdinteractiveauthentication no$' || error "Effective SSH config must keep KbdInteractiveAuthentication no."
}

reload_ssh_service() {
  if systemctl is-active --quiet ssh.service; then
    systemctl reload ssh.service 2>/dev/null || systemctl restart ssh.service
  elif systemctl is-active --quiet ssh.socket; then
    systemctl start ssh.service 2>/dev/null || systemctl restart ssh.service
  else
    systemctl reload ssh 2>/dev/null || systemctl restart ssh 2>/dev/null || systemctl restart sshd
  fi
}

verify_ssh_listening() {
  local ssh_active="no"
  local ssh_listening="no"

  if systemctl is-active --quiet ssh.service; then
    ssh_active="yes"
  fi

  if ss -tulpn 2>/dev/null | awk -v port="${SSH_PORT}" '{split($5, local_addr, ":")} local_addr[length(local_addr)] == port {found=1} END {exit found ? 0 : 1}'; then
    ssh_listening="yes"
  fi

  if [[ "${ssh_active}" != "yes" && "${ssh_listening}" != "yes" ]]; then
    error "SSH service is not active and port ${SSH_PORT}/tcp is not listening after SSH reload."
  fi
}

configure_ufw() {
  log "Configuring UFW firewall..."

  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing

  ufw allow "${SSH_PORT}/tcp" comment "SSH"
  ufw allow "${XRAY_PORT}/tcp" comment "Xray Reality"

  ufw --force enable
  ufw status verbose
}

configure_fail2ban() {
  log "Configuring Fail2ban for sshd..."

  mkdir -p /etc/fail2ban/jail.d

  cat > /etc/fail2ban/jail.d/sshd.local <<EOF
[sshd]
enabled = true
port = ${SSH_PORT}
filter = sshd
backend = systemd
maxretry = 5
findtime = 10m
bantime = 1h
EOF

  systemctl enable fail2ban || warn "Failed to enable fail2ban. Xray installation will continue."
  systemctl restart fail2ban || warn "Failed to restart fail2ban. Xray installation will continue."
  sleep 3
  fail2ban-client status sshd || warn "Fail2ban sshd jail is not ready. Xray installation will continue."
}

install_xray() {
  local tmp_installer=""
  local installer_url="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

  if [[ -x /usr/local/bin/xray ]]; then
    log "Xray already installed. Reusing existing binary."
    log "Xray binary is ready. Continuing Reality configuration..."
    log "Installed Xray version:"
    /usr/local/bin/xray version | head -n1
    return
  fi

  log "Installing Xray-core with official installer..."

  tmp_installer="$(mktemp)"

  if ! curl -fsSL -o "${tmp_installer}" "${installer_url}"; then
    rm -f "${tmp_installer}"
    if [[ -x /usr/local/bin/xray ]]; then
      warn "Failed to download official installer, but /usr/local/bin/xray exists. Reusing existing binary."
    else
      error "Failed to download official Xray installer and /usr/local/bin/xray does not exist."
    fi
  elif ! bash "${tmp_installer}" install; then
    rm -f "${tmp_installer}"
    if [[ -x /usr/local/bin/xray ]]; then
      warn "Official installer failed, but /usr/local/bin/xray exists. Reusing existing binary."
    else
      error "Official Xray installer failed and /usr/local/bin/xray does not exist."
    fi
  else
    rm -f "${tmp_installer}"
  fi

  if [[ ! -x /usr/local/bin/xray ]] && ! command -v xray >/dev/null 2>&1; then
    error "Xray command not found after install/reuse step."
  fi

  log "Xray binary is ready. Continuing Reality configuration..."
  log "Installed Xray version:"
  if [[ -x /usr/local/bin/xray ]]; then
    /usr/local/bin/xray version | head -n1
  else
    xray version | head -n1
  fi
}

generate_values() {
  log "Generating UUID, REALITY key pair, and shortId..."

  local xray_bin
  xray_bin="$(command -v xray || true)"

  if [[ -z "${xray_bin}" && -x /usr/local/bin/xray ]]; then
    xray_bin="/usr/local/bin/xray"
  fi

  if [[ -z "${xray_bin}" ]]; then
    error "Xray binary not found."
  fi

  UUID="$(${xray_bin} uuid 2>/dev/null || true)"
  KEY_PAIR="$(${xray_bin} x25519 2>/dev/null || true)"

  # Xray output format changed in newer versions.
  # Old examples may use:
  #   Private key: xxx
  #   Public key: xxx
  # Xray 26.x may output:
  #   PrivateKey: xxx
  #   Password (PublicKey): xxx
  PRIVATE_KEY="$(echo "${KEY_PAIR}" | awk -F': ' '
    /^PrivateKey:/ {print $2}
    /^Private key:/ {print $2}
    /^Private Key:/ {print $2}
  ' | head -n1)"

  PUBLIC_KEY="$(echo "${KEY_PAIR}" | awk -F': ' '
    /^Password \(PublicKey\):/ {print $2}
    /^PublicKey:/ {print $2}
    /^Public key:/ {print $2}
    /^Public Key:/ {print $2}
  ' | head -n1)"

  SHORT_ID="$(openssl rand -hex 8 2>/dev/null || true)"
  SERVER_IP="$(curl -4 -s --max-time 10 https://api.ipify.org || true)"

  if [[ -z "${SERVER_IP}" ]]; then
    SERVER_IP="$(hostname -I | awk '{print $1}')"
  fi

  if [[ -z "${UUID}" || -z "${PRIVATE_KEY}" || -z "${PUBLIC_KEY}" || -z "${SHORT_ID}" || -z "${SERVER_IP}" ]]; then
    echo -e "${RED}[ERROR]${NC} Failed to generate required values."
    echo "UUID=${UUID}"
    echo "PRIVATE_KEY=${PRIVATE_KEY}"
    echo "PUBLIC_KEY=${PUBLIC_KEY}"
    echo "SHORT_ID=${SHORT_ID}"
    echo "SERVER_IP=${SERVER_IP}"
    echo "xray x25519 output:"
    echo "${KEY_PAIR}"
    exit 1
  fi
}

write_xray_config() {
  log "Writing Xray config: ${XRAY_CONFIG}"

  mkdir -p /usr/local/etc/xray
  backup_file "${XRAY_CONFIG}"

  cat > "${XRAY_CONFIG}" <<EOF
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "vless-reality-vision",
      "listen": "0.0.0.0",
      "port": ${XRAY_PORT},
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "${UUID}",
            "flow": "xtls-rprx-vision",
            "email": "default@xray"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${REALITY_DEST}",
          "xver": 0,
          "serverNames": [
            "${REALITY_SERVER_NAME}"
          ],
          "privateKey": "${PRIVATE_KEY}",
          "shortIds": [
            "${SHORT_ID}"
          ]
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls",
          "quic"
        ]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "blocked",
      "protocol": "blackhole"
    }
  ]
}
EOF

  if [[ "$(tr -d '[:space:]' < "${XRAY_CONFIG}")" == "{}" ]]; then
    error "Refusing to continue because ${XRAY_CONFIG} is empty JSON."
  fi

  xray run -test -config "${XRAY_CONFIG}" || error "Xray config test failed."
}

install_shadowrocket_config() {
  log "Preparing Shadowrocket local config..."

  if [[ -f "${SHADOWROCKET_CONF_SRC}" ]]; then
    cp "${SHADOWROCKET_CONF_SRC}" "${SHADOWROCKET_CONF_DST}"
    chmod 600 "${SHADOWROCKET_CONF_DST}"
    log "Shadowrocket config copied to ${SHADOWROCKET_CONF_DST}"
  else
    warn "${SHADOWROCKET_CONF_SRC} not found in installer directory. Skipping Shadowrocket local config copy."
  fi
}

save_state() {
  log "Saving installer state: ${INSTALLER_STATE}"

  cat > "${INSTALLER_STATE}" <<EOF
XRAY_PORT="${XRAY_PORT}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME}"
REALITY_DEST="${REALITY_DEST}"
CLIENT_NAME="${CLIENT_NAME}"
DEPLOY_USER="${DEPLOY_USER}"
SSH_PORT="${SSH_PORT}"
SERVER_IP="${SERVER_IP}"
SHADOWROCKET_CONF_DST="${SHADOWROCKET_CONF_DST}"
EOF

  chmod 600 "${INSTALLER_STATE}"
}

write_client_info() {
  log "Writing client info: ${CLIENT_INFO}"

  local encoded_name
  encoded_name="${CLIENT_NAME}-${SERVER_IP}"
  encoded_name="${encoded_name// /%20}"

  VLESS_LINK="vless://${UUID}@${SERVER_IP}:${XRAY_PORT}?encryption=none&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&flow=xtls-rprx-vision#${encoded_name}"

  cat > "${CLIENT_INFO}" <<EOF
============================================================
Xray-core VLESS + REALITY + Vision Client Info
============================================================

SSH Login User:
${DEPLOY_USER}

SSH Login Command:
ssh ${DEPLOY_USER}@${SERVER_IP}

Important:
Root SSH login and SSH password login are disabled for safety.
Use the SSH login user above with your existing SSH key for future server management.

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

SNI / serverName:
${REALITY_SERVER_NAME}

SNI / Server Name:
${REALITY_SERVER_NAME}

Public Key:
${PUBLIC_KEY}

Short ID:
${SHORT_ID}

Fingerprint:
chrome

VLESS Reality URI:
${VLESS_LINK}

Shadowrocket Local Config:
${SHADOWROCKET_CONF_DST}

GitHub default.conf Raw URL:
https://raw.githubusercontent.com/hexa46656-creator/secure-vps-xray-reality-installer/main/default.conf

Config file:
${XRAY_CONFIG}

Useful commands:
systemctl status xray
journalctl -u xray -e --no-pager
ufw status verbose
fail2ban-client status sshd
xray version
dig ${REALITY_SERVER_NAME} @1.1.1.1
dig ${REALITY_SERVER_NAME} @8.8.8.8
dig ${REALITY_SERVER_NAME}

============================================================
EOF

  chmod 600 "${CLIENT_INFO}"

  export SUBSCRIPTION_PROTOCOL="vless-reality"
  export SUBSCRIPTION_DIR="/sub/${UUID}"
  export SUBSCRIPTION_SERVER="${SERVER_IP}"
  export SUBSCRIPTION_UUID="${UUID}"
  export SUBSCRIPTION_CLIENT_NAME="${CLIENT_NAME}"
  export SUBSCRIPTION_PUBLIC_KEY="${PUBLIC_KEY}"
  export SUBSCRIPTION_SHORT_ID="${SHORT_ID}"
  export SUBSCRIPTION_SNI="${REALITY_SERVER_NAME}"
  export SUBSCRIPTION_PORT="${XRAY_PORT}"
  export SUBSCRIPTION_FLOW="xtls-rprx-vision"
  installer_core_subscription_protocol_defaults
  installer_core_publish_subscription
  : "${SUBSCRIPTION_ACCESS_URL:=${VLESS_LINK:-}}"

  print_client_qr "${SUBSCRIPTION_ACCESS_URL:-${VLESS_LINK:-}}" "/root/secure-vps-xray-reality-qr.png"
}

print_final_result() {
  echo
  echo -e "${BLUE}================= FINAL RESULT =================${NC}"
  echo -e "${GREEN}Xray status:${NC} $(systemctl is-active xray 2>/dev/null || echo unknown)"
  echo -e "${GREEN}Server IP:${NC} ${SERVER_IP}"
  echo -e "${GREEN}Port:${NC} ${XRAY_PORT}"
  echo -e "${GREEN}Client file path:${NC} ${CLIENT_INFO}"
  echo -e "${GREEN}VLESS Reality URI:${NC} ${VLESS_LINK}"
  echo -e "${BLUE}================================================${NC}"
  echo "${VLESS_LINK}"
  installer_core_print_completion_block "$(installer_core_mode_label)" "${SUBSCRIPTION_ACCESS_URL}" "Shadowrocket, v2rayNG, Clash, sing-box"
}

start_services() {
  log "Starting Xray service..."

  systemctl daemon-reload
  systemctl enable xray
  systemctl restart xray

  if systemctl is-active --quiet xray; then
    log "Xray is running."
  else
    journalctl -u xray -e --no-pager || true
    error "Xray failed to start. Troubleshoot with: journalctl -u xray -e --no-pager"
  fi
}

final_self_check() {
  log "Running final self-check..."

  if [[ "$(tr -d '[:space:]' < "${XRAY_CONFIG}")" == "{}" ]]; then
    error "${XRAY_CONFIG} is {}. Refusing to report success."
  fi

  systemctl is-active --quiet xray || error "xray.service is not active."

  if ! ss -tulpn 2>/dev/null | awk -v port="${XRAY_PORT}" '{split($5, local_addr, ":")} local_addr[length(local_addr)] == port {found=1} END {exit found ? 0 : 1}'; then
    error "Port ${XRAY_PORT}/tcp is not listening."
  fi

  if [[ ! -s "${CLIENT_INFO}" ]]; then
    error "${CLIENT_INFO} is missing or empty."
  fi

  log "Final self-check passed."
}

main() {
  require_root
  check_os
  detect_ssh_port
  install_packages
  create_deploy_user
  harden_ssh_safe
  configure_ufw
  configure_fail2ban
  install_xray
  check_reality_dns_health
  generate_values
  write_xray_config
  install_shadowrocket_config
  save_state
  start_services
  write_client_info
  final_self_check

  log "Deployment completed successfully."
  print_final_result
}

main "$@"
