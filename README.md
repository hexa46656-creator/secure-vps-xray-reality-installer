# Secure VPS Xray Reality Installer

Automated Ubuntu 24.04 VPS hardening and Xray-core VLESS + REALITY + Vision deployment script.

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

sudo -i 
apt update && apt install -y curl 
bash <(curl -Ls https://raw.githubusercontent.com/YOUR_USERNAME/secure-vps-xray-reality-installer/main/install.sh) 

## Custom Port

Default Xray inbound port is 8443.

You can customize it:

XRAY_PORT=443 bash <(curl -Ls https://raw.githubusercontent.com/YOUR_USERNAME/secure-vps-xray-reality-installer/main/install.sh) 

## Custom REALITY SNI

Default SNI is www.microsoft.com.

You can customize it:

REALITY_SERVER_NAME=www.apple.com REALITY_DEST=www.apple.com:443 bash <(curl -Ls https://raw.githubusercontent.com/YOUR_USERNAME/secure-vps-xray-reality-installer/main/install.sh) 

## Client Info

After installation, client information is saved at:

bash /root/xray-reality-client.txt 

View it:

cat /root/xray-reality-client.txt 

## Useful Commands

systemctl status xray journalctl -u xray -e --no-pager ufw status verbose fail2ban-client status sshd xray version 

## Security Notes

This script uses a conservative SSH hardening strategy:

- Root SSH login is disabled.
- Public key authentication is enabled.
- Password authentication is not forcibly disabled by default to avoid locking new users out.

After confirming your SSH key login works, you may manually disable SSH password login.

## License

MIT
