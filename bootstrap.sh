#!/usr/bin/env bash
set -euo pipefail

# =========================================================
# Secure VPS Xray Reality Bootstrap Installer
# 真正一键部署入口：安装基础工具、克隆仓库、授权脚本、执行 install.sh
# =========================================================

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
BOLD="\033[1m"
NC="\033[0m"

REPO_URL="${REPO_URL:-https://github.com/hexa46656-creator/secure-vps-xray-reality-installer.git}"
INSTALL_DIR="${INSTALL_DIR:-/root/secure-vps-xray-reality-installer}"
CLIENT_INFO="/root/xray-reality-client.txt"

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
    error "请使用 root 用户运行。示例：sudo -i"
  fi
}

install_basic_tools() {
  log "安装基础工具：git curl wget..."
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y git curl wget
}

prepare_repo() {
  log "准备安装仓库：${INSTALL_DIR}"

  cd /root

  if [[ -d "${INSTALL_DIR}/.git" ]]; then
    log "检测到已有仓库，正在更新..."
    git -C "${INSTALL_DIR}" reset --hard
    git -C "${INSTALL_DIR}" pull --ff-only
  else
    rm -rf "${INSTALL_DIR}"
    git clone "${REPO_URL}" "${INSTALL_DIR}"
  fi

  cd "${INSTALL_DIR}"
  chmod +x install.sh status.sh update.sh uninstall.sh reset-client.sh bootstrap.sh 2>/dev/null || true
}

run_installer() {
  log "开始执行 Xray + VLESS + REALITY 一键部署..."
  cd "${INSTALL_DIR}"
  bash install.sh
}

extract_value() {
  local label="$1"
  awk -v label="$label" '
    $0 == label {getline; print; exit}
  ' "${CLIENT_INFO}" 2>/dev/null || true
}

print_final_summary() {
  if [[ ! -f "${CLIENT_INFO}" ]]; then
    warn "未找到客户端信息文件：${CLIENT_INFO}"
    return 0
  fi

  local ssh_command uuid vless_link
  ssh_command="$(extract_value "SSH Login Command:")"
  uuid="$(extract_value "UUID:")"
  vless_link="$(extract_value "VLESS Link:")"

  echo
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo -e "${BLUE}${BOLD}                 安装完成：请保存以下 3 项                  ${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo
  echo -e "${YELLOW}${BOLD}1、SSH Login Command（以后在终端用这条命令登录 VPS，需要本地 SSH 私钥）${NC}"
  echo -e "${GREEN}${BOLD}${ssh_command:-未找到，请查看 ${CLIENT_INFO}}${NC}"
  echo
  echo -e "${YELLOW}${BOLD}2、UUID（VLESS 客户端 UUID，用于手动配置或核对节点）${NC}"
  echo -e "${GREEN}${BOLD}${uuid:-未找到，请查看 ${CLIENT_INFO}}${NC}"
  echo
  echo -e "${YELLOW}${BOLD}3、VLESS Link（复制整行 vless:// 导入 Shadowrocket / v2rayNG）${NC}"
  echo -e "${GREEN}${BOLD}${vless_link:-未找到，请查看 ${CLIENT_INFO}}${NC}"
  echo
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo -e "${YELLOW}${BOLD}中文提示：root 远程登录和密码登录均已禁用，只能用 SSH Key 登录。${NC}"
  echo -e "${YELLOW}${BOLD}关闭当前会话前，请先用新终端测试一次上面的 SSH Login Command。${NC}"
  echo -e "${YELLOW}${BOLD}完整信息也已保存到：${CLIENT_INFO}${NC}"
  echo -e "${BLUE}${BOLD}============================================================${NC}"
  echo
}

main() {
  require_root
  install_basic_tools
  prepare_repo
  run_installer
  print_final_summary
}

main "$@"
