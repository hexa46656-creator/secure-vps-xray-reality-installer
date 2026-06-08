# Secure VPS Xray Reality Installer

Automated Ubuntu 24.04 VPS hardening and Xray-core VLESS + REALITY + Vision deployment script.

适用于 Ubuntu 24.04 VPS 的安全加固与 Xray-core VLESS + Reality + Vision 自动部署脚本。

## Features

- Ubuntu 24.04 VPS security hardening
- UFW firewall configuration
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
- Fresh VPS recommended

## Quick Start

```bash
sudo -i
apt update && apt install -y curl
bash <(curl -Ls https://raw.githubusercontent.com/hexa46656-creator/secure-vps-xray-reality-installer/main/install.sh)
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

This script uses a conservative SSH hardening strategy:

- Root SSH login is disabled.
- Public key authentication is enabled.
- Password authentication is not forcibly disabled by default to avoid locking new users out.

After confirming your SSH key login works, you may manually disable SSH password login.

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
