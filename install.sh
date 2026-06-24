#!/bin/bash
# ============================================
#   RMS UDP CUSTOM MANAGER - Installer v2.0
#   By Rodney Mwase Seth
# ============================================

RED='\e[1;31m'
GREEN='\e[1;32m'
YELLOW='\e[1;33m'
CYAN='\e[1;36m'
WHITE='\e[1;97m'
MAGENTA='\e[1;35m'
NC='\e[0m'

rms_banner() {
clear
echo -e "${CYAN}"
echo "  ██████╗ ███╗   ███╗███████╗"
echo "  ██╔══██╗████╗ ████║██╔════╝"
echo "  ██████╔╝██╔████╔██║███████╗"
echo "  ██╔══██╗██║╚██╔╝██║╚════██║"
echo "  ██║  ██║██║ ╚═╝ ██║███████║"
echo -e "${YELLOW}"
echo "  UDP CUSTOM MANAGER  v2.0"
echo -e "${WHITE}"
echo "  By Rodney Mwase Seth"
echo "  Tunnel App : HTTP Custom"
echo -e "${CYAN}"
echo "┌──────────────────────────────────────────────┐"
echo -e "${NC}"
}

step() {
  echo -e "${CYAN}[RMS]${NC} ${WHITE}$1${NC}"
}

ok() {
  echo -e "${GREEN}[✔]${NC} ${WHITE}$1${NC}"
}

fail() {
  echo -e "${RED}[✘]${NC} ${WHITE}$1${NC}"
  exit 1
}

rms_banner

# Check root
[[ $EUID -ne 0 ]] && fail "Run as root: sudo -i"

# Check OS
grep -qi ubuntu /etc/os-release || fail "Ubuntu required"

# Check arch
[[ $(uname -m) != "x86_64" ]] && fail "x86_64 architecture required"

echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}         STARTING INSTALLATION...               ${NC}"
echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}"
echo ""

# Dependencies
step "Installing dependencies..."
apt update -y &>/dev/null
apt install -y wget curl screen openssl dos2unix &>/dev/null
ok "Dependencies installed"

# Create directories
step "Setting up directories..."
mkdir -p /root/udp
mkdir -p /etc/UDPCustom
mkdir -p /etc/rms-users
ok "Directories created"

# Download UDP Custom binary
step "Downloading UDP Custom binary..."
wget -q "https://raw.github.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64" -O /root/udp/udp-custom
chmod +x /root/udp/udp-custom
ok "UDP Custom binary downloaded"

# Download UDPGW
step "Downloading UDPGW..."
wget -q "https://raw.github.com/http-custom/udp-custom/main/module/udpgw" -O /bin/udpgw
chmod +x /bin/udpgw
ok "UDPGW downloaded"

# Config file
step "Creating config..."
cat > /root/udp/config.json << 'CONF'
{
  "listen": ":36712",
  "stream_buffer": 33554432,
  "receive_buffer": 83886080,
  "auth": {
    "mode": "passwords"
  }
}
CONF
ok "Config created"

# UDP Custom service
step "Creating UDP Custom service..."
cat > /etc/systemd/system/udp-custom.service << 'SVC'
[Unit]
Description=RMS UDP Custom Manager Service
After=network.target

[Service]
User=root
Type=simple
ExecStart=/root/udp/udp-custom server
WorkingDirectory=/root/udp/
Restart=always
RestartSec=2s

[Install]
WantedBy=multi-user.target
SVC
ok "UDP Custom service created"

# UDPGW service
step "Creating UDPGW service..."
cat > /etc/systemd/system/udpgw.service << 'SVC'
[Unit]
Description=UDPGW Gateway Service - RMS
After=network.target

[Service]
Type=forking
ExecStart=/usr/bin/screen -dmS udpgw /bin/udpgw --listen-addr 127.0.0.1:7800 --max-clients 1000 --max-connections-for-client 100
Restart=always
User=root

[Install]
WantedBy=multi-user.target
SVC
ok "UDPGW service created"

# Expiry daemon
step "Creating RMS Auto-Expiry Daemon..."
cat > /etc/rms-expiry.sh << 'EXPIRY'
#!/bin/bash
expired_found=0
for user in $(cat /etc/passwd | grep 'home' | grep 'false' | grep -v 'syslog' | grep -v 'hwid' | grep -v 'token' | grep -v '::/' | awk -F ':' '{print $1}'); do
    expfile="/etc/rms-users/${user}.expiry"
    if [[ -f "$expfile" ]]; then
        exp_timestamp=$(cat "$expfile")
        now=$(date +%s)
        if [[ $now -ge $exp_timestamp ]]; then
            userdel --force "$user" 2>/dev/null
            rm -f "$expfile"
            expired_found=1
            echo "$(date): [RMS] Expired user $user auto-deleted" >> /var/log/rms-expiry.log
        fi
    else
        expiry=$(chage -l "$user" 2>/dev/null | grep "Account expires" | awk -F ': ' '{print $2}')
        if [[ "$expiry" != "never" ]] && [[ -n "$expiry" ]]; then
            if [[ $(date +%s) -gt $(date '+%s' -d "$expiry" 2>/dev/null) ]]; then
                userdel --force "$user" 2>/dev/null
                expired_found=1
                echo "$(date): [RMS] Expired user $user auto-deleted (chage)" >> /var/log/rms-expiry.log
            fi
        fi
    fi
done
if [[ $expired_found -eq 1 ]]; then
    systemctl restart udp-custom 2>/dev/null
    echo "$(date): [RMS] UDP-Custom restarted to kick expired sessions" >> /var/log/rms-expiry.log
fi
EXPIRY
chmod +x /etc/rms-expiry.sh
ok "Auto-Expiry Daemon created"

# Expiry systemd service
step "Creating Expiry Daemon service..."
cat > /etc/systemd/system/rms-expiry.service << 'SVC'
[Unit]
Description=RMS UDP Custom Manager - Auto Expiry Daemon
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'while true; do /etc/rms-expiry.sh; sleep 5; done'
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SVC
ok "Expiry Daemon service created"

# Download and install RMS Manager
step "Installing RMS UDP Custom Manager..."
wget -q "https://raw.githubusercontent.com/rseth2003/RMS-UDP-CUSTOM-MANAGER/master/udp" -O /usr/bin/udp
chmod +x /usr/bin/udp
ok "RMS Manager installed"

# Disable firewall
step "Disabling firewall..."
ufw disable &>/dev/null
apt remove --purge ufw firewalld -y &>/dev/null
ok "Firewall disabled"

# Enable and start all services
step "Starting services..."
systemctl daemon-reload

systemctl enable udpgw &>/dev/null
systemctl start udpgw &>/dev/null

systemctl enable udp-custom &>/dev/null
systemctl start udp-custom &>/dev/null

systemctl enable rms-expiry &>/dev/null
systemctl start rms-expiry &>/dev/null
ok "All services started"

# Verify
echo ""
echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}           SERVICE STATUS CHECK                 ${NC}"
echo -e "${CYAN}├──────────────────────────────────────────────┤${NC}"

if systemctl is-active udp-custom &>/dev/null; then
  echo -e " ${GREEN}●${NC} ${WHITE}UDP Custom   : ${GREEN}RUNNING${NC}"
else
  echo -e " ${RED}●${NC} ${WHITE}UDP Custom   : ${RED}STOPPED${NC}"
fi

if systemctl is-active udpgw &>/dev/null; then
  echo -e " ${GREEN}●${NC} ${WHITE}UDPGW        : ${GREEN}RUNNING${NC}"
else
  echo -e " ${RED}●${NC} ${WHITE}UDPGW        : ${RED}STOPPED${NC}"
fi

if systemctl is-active rms-expiry &>/dev/null; then
  echo -e " ${GREEN}●${NC} ${WHITE}RMS Expiry   : ${GREEN}RUNNING${NC}"
else
  echo -e " ${RED}●${NC} ${WHITE}RMS Expiry   : ${RED}STOPPED${NC}"
fi

echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${YELLOW}  Run: ${WHITE}udp${NC}"
echo ""
