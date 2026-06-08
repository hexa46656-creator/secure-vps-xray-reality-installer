#!/usr/bin/env bash
set -euo pipefail

GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RED="\033[31m"
NC="\033[0m"

XRAY_CONFIG="/usr/local/etc/xray/config.json"
CLIENT_INFO="/root/xray-reality-client.txt"
INSTALLER_STATE="/etc/xray-reality-installer.env"

section() {
  echo
  echo -e "${BLUE}========== $1 ==========${NC}"
}

ok() {
  echo -e "${GREEN}[OK]${NC} $1"
}

warn() {
  echo -e "${YELLOW}[WARN]${NC} $1"
}

fail() {
  echo -e "${RED}[FAIL]${NC} $1"
}

if [[ -f "${INSTALLER_STATE}" ]]; then
  # shellcheck disable=SC1090
  source "${INSTALLER_STATE}"
fi

XRAY_PORT="${XRAY_PORT:-8443}"

section "System"
if [[ -f /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  echo "OS: ${PRETTY_NAME:-unknown}"
fi
echo "Kernel: $(uname -r)"
echo "Hostname: $(hostname)"

section "Xray Version"
if command -v xray >/dev/null 2>&1; then
  xray version | head -n1
else
  fail "xray command not found"
fi

section "Xray Config"
if [[ -f "${XRAY_CONFIG}" ]]; then
  ok "Config exists: ${XRAY_CONFIG}"
  if command -v xray >/dev/null 2>&1; then
    xray run -test -config "${XRAY_CONFIG}" && ok "Config test passed" || fail "Config test failed"
  fi
else
  fail "Config not found: ${XRAY_CONFIG}"
fi

section "Xray Service"
if systemctl list-unit-files | grep -q '^xray.service'; then
  systemctl status xray --no-pager -l || true
else
  fail "xray.service not found"
fi

section "Listening Port"
if ss -tlnp | grep -q ":${XRAY_PORT} "; then
  ok "Port ${XRAY_PORT}/tcp is listening"
  ss -tlnp | grep ":${XRAY_PORT} " || true
else
  fail "Port ${XRAY_PORT}/tcp is not listening"
fi

section "Firewall"
if command -v ufw >/dev/null 2>&1; then
  ufw status verbose || true
else
  warn "ufw not installed"
fi

section "Fail2ban"
if command -v fail2ban-client >/dev/null 2>&1; then
  fail2ban-client status || true
  fail2ban-client status sshd || true
else
  warn "fail2ban not installed"
fi

section "Client Info"
if [[ -f "${CLIENT_INFO}" ]]; then
  ok "Client info exists: ${CLIENT_INFO}"
  echo "Use: sudo cat ${CLIENT_INFO}"
else
  warn "Client info not found: ${CLIENT_INFO}"
fi

echo
