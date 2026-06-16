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
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-www.microsoft.com}"
REALITY_DEST="${REALITY_DEST:-www.microsoft.com:443}"
CLIENT_NAME="${CLIENT_NAME:-VLESS-Reality}"
DEPLOY_USER="${DEPLOY_USER:-alex}"
DEPLOY_USER_PASSWORD="${DEPLOY_USER_PASSWORD:-}"

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

check_os() {
  if [[ ! -f /etc/os-release ]]; then
    error "Cannot detect operating system."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  if [[ "${ID:-}" != "ubuntu" ]]; then
    error "This installer only supports Ubuntu. Detected: ${ID:-unknown}"
  fi

  if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    warn "This script is designed for Ubuntu 24.04. Detected: ${VERSION_ID:-unknown}"
    read -rp "Continue anyway? [y/N]: " confirm
    if [[ ! "${confirm}" =~ ^[Yy]$ ]]; then
      exit 0
    fi
  fi
}

detect_ssh_port() {
  SSH_PORT="$(ss -tlnp 2>/dev/null | awk '/sshd/ {print $4}' | awk -F: '{print $NF}' | head -n1 || true)"

  if [[ -z "${SSH_PORT}" ]]; then
    SSH_PORT="$(grep -Ei '^\s*Port\s+' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null | awk '{print $NF}' | tail -n1 || true)"
  fi

  SSH_PORT="${SSH_PORT:-22}"
  log "Detected SSH port: ${SSH_PORT}"
}

install_packages() {
  log "Updating system and installing dependencies..."
  apt update
  DEBIAN_FRONTEND=noninteractive apt upgrade -y
  DEBIAN_FRONTEND=noninteractive apt install -y \
    curl wget unzip jq socat ufw fail2ban ca-certificates gnupg lsb-release openssl iproute2 sudo
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
  encoded_name="$(echo "${CLIENT_NAME}-${SERVER_IP}" | sed 's/ /%20/g')"

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

============================================================
EOF

  chmod 600 "${CLIENT_INFO}"
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
