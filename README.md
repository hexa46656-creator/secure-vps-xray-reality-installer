# Secure VPS Xray Reality Installer

Automated Ubuntu 24.04 VPS Xray-core VLESS + REALITY + Vision deployment script designed to run safely after VPSGuard.

适用于 Ubuntu 24.04 VPS 的 Xray-core VLESS + Reality + Vision 自动部署脚本，推荐接在 VPSGuard 之后运行。

## Features

- VPSGuard-compatible SSH hardening
- UFW firewall configuration for SSH and Xray Reality
- Fail2ban SSH protection
- Xray-core installation
- VLESS + REALITY + Vision configuration
- Automatic UUID generation
- Automatic REALITY key pair generation
- Automatic shortId generation
- Shadowrocket / v2rayN compatible VLESS link output
- One-command deployment

## Supported System

- Ubuntu 24.04 LTS x64
- DigitalOcean Ubuntu 24.04 VPS
- Recommended flow: run VPSGuard first, then run this installer

## Quick Start

Recommended:

1. Run VPSGuard first and create/keep your secure SSH user.
2. Run this Xray Reality installer.

The default deploy user is `alex`, matching the VPSGuard default user. If `alex` already exists, this script reuses it and keeps `/home/alex/.ssh/authorized_keys` unchanged. If `DEPLOY_USER` does not exist, the script creates it.

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

Default SNI is `www.microsoft.com`.

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

Ports `80/tcp` and `443/tcp` are not opened by default because this Reality setup does not use them. Open them manually only if another service needs HTTP/HTTPS.

## Useful Commands

```bash
systemctl status xray
journalctl -u xray -e --no-pager
ufw status verbose
fail2ban-client status sshd
xray version
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

Before closing your current SSH session, confirm that your VPSGuard user can log in with SSH keys.

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
