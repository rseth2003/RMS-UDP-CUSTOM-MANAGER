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

step() { echo -e "${CYAN}[RMS]${NC} ${WHITE}$1${NC}"; }
ok()   { echo -e "${GREEN}[✔]${NC} ${WHITE}$1${NC}"; }
fail() { echo -e "${RED}[✘]${NC} ${WHITE}$1${NC}"; exit 1; }

rms_banner

[[ $EUID -ne 0 ]] && fail "Run as root: sudo -i"
grep -qi ubuntu /etc/os-release || fail "Ubuntu required"
[[ $(uname -m) != "x86_64" ]] && fail "x86_64 required"

echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}         STARTING INSTALLATION...               ${NC}"
echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}"
echo ""

step "Installing dependencies..."
apt update -y &>/dev/null
apt install -y wget curl screen openssl iptables-persistent &>/dev/null
ok "Dependencies installed"

step "Setting up directories..."
mkdir -p /root/udp
mkdir -p /etc/UDPCustom
mkdir -p /etc/rms-users
ok "Directories created"

step "Downloading UDP Custom binary..."
wget -q "https://raw.github.com/http-custom/udp-custom/main/bin/udp-custom-linux-amd64" -O /root/udp/udp-custom
chmod +x /root/udp/udp-custom
ok "UDP Custom binary downloaded"

step "Downloading UDPGW..."
wget -q "https://raw.github.com/http-custom/udp-custom/main/module/udpgw" -O /bin/udpgw
chmod +x /bin/udpgw
ok "UDPGW downloaded"

step "Downloading module file..."
wget -q "https://raw.github.com/http-custom/udp-custom/main/module/module" -O /etc/UDPCustom/module
ok "Module file downloaded"

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
ok "Config created (port: 36712)"

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

step "Creating Auto-Expiry Daemon..."
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

step "Installing RMS Manager..."
wget -q "https://raw.githubusercontent.com/rseth2003/RMS-UDP-CUSTOM-MANAGER/master/udp" -O /usr/bin/udp
chmod +x /usr/bin/udp
ok "RMS Manager installed"

step "Disabling firewall..."
ufw disable &>/dev/null
ok "Firewall disabled"

step "Setting up full port range 1-65535..."
iptables -t nat -A PREROUTING -p udp --dport 1:65535 -j DNAT --to-destination :36712
iptables-save > /etc/iptables/rules.v4
ok "Port range 1-65535 forwarding to 36712 set"

step "Starting services..."
systemctl daemon-reload
systemctl enable udpgw &>/dev/null && systemctl start udpgw &>/dev/null
systemctl enable udp-custom &>/dev/null && systemctl start udp-custom &>/dev/null
systemctl enable rms-expiry &>/dev/null && systemctl start rms-expiry &>/dev/null
systemctl enable netfilter-persistent &>/dev/null
ok "All services started"

echo ""
echo -e "${CYAN}┌──────────────────────────────────────────────┐${NC}"
echo -e "${YELLOW}           SERVICE STATUS CHECK                 ${NC}"
echo -e "${CYAN}├──────────────────────────────────────────────┤${NC}"
systemctl is-active udp-custom &>/dev/null && echo -e " ${GREEN}●${NC} UDP Custom   : ${GREEN}RUNNING${NC}" || echo -e " ${RED}●${NC} UDP Custom   : ${RED}STOPPED${NC}"
systemctl is-active udpgw &>/dev/null && echo -e " ${GREEN}●${NC} UDPGW        : ${GREEN}RUNNING${NC}" || echo -e " ${RED}●${NC} UDPGW        : ${RED}STOPPED${NC}"
systemctl is-active rms-expiry &>/dev/null && echo -e " ${GREEN}●${NC} RMS Expiry   : ${GREEN}RUNNING${NC}" || echo -e " ${RED}●${NC} RMS Expiry   : ${RED}STOPPED${NC}"
echo -e "${CYAN}└──────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${GREEN}  Installation Complete! Run: ${WHITE}udp${NC}"
echo ""
