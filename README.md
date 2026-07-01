# Secure VPS Xray Reality Installer

Automated Ubuntu 24.04 VPS Xray-core VLESS + REALITY + Vision deployment script designed to run safely after VPSGuard.

适用于 Ubuntu 24.04 VPS 的 Xray-core VLESS + Reality + Vision 自动部署脚本，推荐接在 VPSGuard 之后运行。

## Features

- VPSGuard-compatible SSH hardening
- UFW firewall configuration for SSH and Xray Reality without wiping unrelated existing rules
- Fail2ban SSH protection
- Xray-core installation
- VLESS + REALITY + Vision configuration
- Automatic UUID generation
- Automatic REALITY key pair generation
- Automatic shortId generation
- Shadowrocket / v2rayN compatible VLESS link output
- BBR network acceleration enabled by default when supported by the kernel
- One-command deployment

## Supported System

- Ubuntu 24.04 LTS x64
- DigitalOcean Ubuntu 24.04 VPS
- Recommended flow: run VPSGuard first, then run this installer

## Quick Start

Recommended:

1. Run VPSGuard first and make sure at least one SSH key is already working.
2. Run this Xray Reality installer.

The installer disables root SSH login and SSH password login, so do not run it unless key-based access is already confirmed. The default deploy user is `alex`, matching the VPSGuard default user. If `alex` already exists, this script reuses it and keeps `/home/alex/.ssh/authorized_keys` unchanged. If `DEPLOY_USER` does not exist, the script creates it. The deploy user is configured with passwordless `sudo -i` for ongoing server management.

```bash
sudo -i
apt update && apt install -y curl
bash <(curl -Ls https://raw.githubusercontent.com/hexa46656-creator/secure-vps-xray-reality-installer/main/install.sh)
```

Use a different existing deploy user only when needed:

```bash
DEPLOY_USER=youruser bash <(curl -Ls https://raw.githubusercontent.com/hexa46656-creator/secure-vps-xray-reality-installer/main/install.sh)
```

## Custom Port

Default Xray inbound port is `8443`.

```bash
XRAY_PORT=8443 bash <(curl -Ls https://raw.githubusercontent.com/hexa46656-creator/secure-vps-xray-reality-installer/main/install.sh)
```

## Custom REALITY SNI

Default SNI is `speed.cloudflare.com`.

```bash
REALITY_SERVER_NAME=www.apple.com REALITY_DEST=www.apple.com:443 bash <(curl -Ls https://raw.githubusercontent.com/hexa46656-creator/secure-vps-xray-reality-installer/main/install.sh)
```

## Client Info

After installation, client information is saved at:

```bash
/root/xray-reality-client.txt
```

View it:

```bash
cat /root/xray-reality-client.txt
```

The file includes the Server IP, port, UUID, Reality public key, short ID, fingerprint, and a Shadowrocket / v2rayN compatible VLESS Reality URI.

The installer also prints the VLESS Reality URI at the end of the install output.

## Firewall

By default, UFW only allows:

- Current SSH port, usually `22/tcp`
- Xray Reality port, default `8443/tcp`

Ports `80/tcp` and `443/tcp` are not opened by default because this Reality setup does not use them. Open them manually only if another service needs HTTP/HTTPS. The installer does not wipe unrelated existing UFW rules; it only adds the SSH and Xray rules it needs.

## Useful Commands

```bash
systemctl status xray
journalctl -u xray -e --no-pager
ufw status verbose
fail2ban-client status sshd
xray version
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc
lsmod | grep bbr
```

## Project Structure

```text
secure-vps-xray-reality-installer/
├── README.md
├── LICENSE
├── .gitignore
├── install.sh
├── uninstall.sh
├── update.sh
├── status.sh
├── reset-client.sh
└── docs/
    ├── shadowrocket.md
    └── troubleshooting.md
```

## Installation Output

After successful installation, the script will generate:

- Server IP
- Port
- UUID
- REALITY public key
- REALITY shortId
- VLESS import link

The client information will be saved to:

```bash
/root/xray-reality-client.txt
```

## Security Notes

This script uses a VPSGuard-compatible SSH hardening strategy:

- Root SSH login is disabled.
- Public key authentication is enabled.
- Password authentication is disabled.
- Keyboard-interactive authentication is disabled.
- Existing VPSGuard SSH keys for `alex` are preserved.
- The deploy user can run `sudo -i` without a password.

Before closing your current SSH session, confirm that your VPSGuard user can log in with SSH keys and can run `sudo -i` without a password. If the SSH port cannot be detected automatically, set `SSH_PORT=<your_port>` explicitly before running the installer.

## Common Commands

Check Xray:

```bash
systemctl status xray
```

View Xray logs:

```bash
journalctl -u xray -e --no-pager
```

Check firewall:

```bash
ufw status verbose
```

Check Fail2ban:

```bash
fail2ban-client status sshd
```

## Update

```bash
bash update.sh
```

## Uninstall

```bash
bash uninstall.sh
```

## License

MIT

## 中文说明

### 项目简介

本项目用于在 Ubuntu 24.04 VPS 上自动部署 Xray-core VLESS + REALITY + Vision，并带有 VPSGuard 兼容的 SSH 加固流程。安装完成后会输出客户端链接和本地保存的客户端信息。

### 支持系统

- Ubuntu 24.04 LTS x64
- 推荐先完成 VPSGuard 或其他基础加固，再运行本安装脚本

### 一键安装命令

运行前请确认 VPS 上已经有可用的 SSH Key，否则脚本会在关闭密码登录前直接退出。

```bash
sudo -i
apt update && apt install -y curl
bash <(curl -Ls https://raw.githubusercontent.com/hexa46656-creator/secure-vps-xray-reality-installer/main/install.sh)
```

### 默认端口

- 默认 Xray 入站端口：`8443/tcp`

### 默认 SNI

- 默认 `REALITY_SERVER_NAME`：`speed.cloudflare.com`
- 默认 `REALITY_DEST`：`speed.cloudflare.com:443`
- 如果你手动指定参数，脚本会保留你的自定义值

### 安装完成后的客户端链接

- 客户端信息保存到：`/root/xray-reality-client.txt`
- 安装完成后，终端会显示原始 VLESS Reality 链接
- 你可以先复制链接，再按需要导入客户端

### 二维码扫码导入

安装完成后，脚本会在终端显示二维码，并把 PNG 文件保存到本机。

- 二维码内容优先使用脚本最终生成的订阅链接
- 如果订阅链接不可用，会回退到原始 `vless://` 链接
- PNG 文件保存路径：`/root/secure-vps-xray-reality-qr.png`

常用客户端：

- Shadowrocket
- v2rayNG
- Hiddify
- NekoBox
- Clash / Clash Verge

### 状态检查命令

```bash
bash status.sh
```

### 卸载命令

```bash
bash uninstall.sh
```

### 安全提示

- 该脚本会禁用 root SSH 登录，并关闭密码登录
- 该脚本会在内核支持时默认开启 BBR 加速
- 请确认你的 SSH Key 可以正常登录后，再结束当前会话
- 建议先备份 `/root/xray-reality-client.txt`

### 故障排查

1. 先执行 `bash status.sh` 查看 Xray、SSH 和防火墙状态
2. 确认 `8443/tcp` 已在 VPS 防火墙和云安全组中放行
3. 确认 `speed.cloudflare.com` 的 DNS 解析正常
4. 如果二维码无法显示，直接复制 `/root/xray-reality-client.txt` 里的原始链接手动导入
5. 如果安装后无法连接，先查看 `journalctl -u xray -e --no-pager`
