#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo bash setup.sh)"
  exit
fi

# ==========================================
# INTERACTIVE CONFIGURATION
# ==========================================
echo "--- VPN Gateway Configuration ---"
read -p "Enter Gateway IP (Pi's IP) [Default: 192.168.50.1]: " GATEWAY_IP
GATEWAY_IP=${GATEWAY_IP:-192.168.50.1}

read -p "Enter PC IP (DHCP assignment) [Default: 192.168.50.10]: " PC_IP
PC_IP=${PC_IP:-192.168.50.10}

read -p "Enter ports to forward (comma separated, e.g. 80,8080) [Default: 80,8080]: " FORWARD_PORTS
FORWARD_PORTS=${FORWARD_PORTS:-80,8080}

read -p "Auto-connect to OPEN (unsecured) WiFi networks? (y/n) [Default: n]: " AUTO_WIFI
AUTO_WIFI=${AUTO_WIFI:-n}

read -p "Create OpenVPN auto-login file (auth.txt)? (y/n) [Default: n]: " SETUP_VPN_AUTH
SETUP_VPN_AUTH=${SETUP_VPN_AUTH:-n}

if [[ "$SETUP_VPN_AUTH" =~ ^[Yy] ]]; then
  read -p "  -> Enter OpenVPN Username: " VPN_USER
  echo "  -> (Note: Your password will be hidden as you type for security)"
  read -s -p "  -> Enter OpenVPN Password: " VPN_PASS
  echo "" # Adds a newline after the hidden password input
fi

echo "---------------------------------"
echo "Using Gateway IP: $GATEWAY_IP"
echo "Using PC IP: $PC_IP"
echo "Forwarding Ports: $FORWARD_PORTS"
echo "Starting setup in 3 seconds..."
sleep 3

# ==========================================
# INSTALLATION & NETWORK CONFIG
# ==========================================
echo "Updating system and installing dependencies..."
export DEBIAN_FRONTEND=noninteractive
apt update
apt install -y openvpn dnsmasq network-manager iptables-persistent netfilter-persistent resolvconf

echo "Configuring Ethernet Interface (eth0) with NetworkManager..."
nmcli con delete eth0-local 2>/dev/null || true
nmcli con add type ethernet ifname eth0 ipv4.method manual ipv4.addresses $GATEWAY_IP/24 ipv4.gateway "" ipv4.dns "" connection.id "eth0-local"
nmcli con up eth0-local

echo "Enabling IP Forwarding..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-vpn-forward.conf
sysctl -p /etc/sysctl.d/99-vpn-forward.conf

echo "Configuring DHCP Server (dnsmasq)..."
cat <<EOF > /etc/dnsmasq.conf
interface=eth0
dhcp-range=$PC_IP,$PC_IP,255.255.255.0,24h
dhcp-option=3,$GATEWAY_IP
dhcp-option=6,$GATEWAY_IP
EOF
systemctl restart dnsmasq
systemctl enable dnsmasq

# ==========================================
# FIREWALL & ROUTING CONFIG
# ==========================================
echo "Configuring iptables Firewall & Kill Switch..."
iptables -F
iptables -t nat -F

# Default Policies (Kill Switch foundation)
iptables -P FORWARD DROP

# Allow traffic from eth0 to tun0 (VPN)
iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
# Allow established returning traffic
iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT

# NAT - Masquerade PC's IP behind the VPN IP
iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

# Port Forwarding (NAT PREROUTING)
IFS=',' read -ra PORT_ARRAY <<< "$FORWARD_PORTS"
for PORT in "${PORT_ARRAY[@]}"; do
  PORT=$(echo "$PORT" | xargs)
  iptables -t nat -A PREROUTING -i tun0 -p tcp -m tcp --dport $PORT -j DNAT --to-destination $PC_IP:$PORT
done

# Port Forwarding (Filter Rules)
iptables -A FORWARD -d $PC_IP/32 -i tun0 -o eth0 -p tcp -m multiport --dports $FORWARD_PORTS -j ACCEPT

echo "Saving firewall rules..."
netfilter-persistent save

# ==========================================
# OPENVPN AUTH CONFIGURATION
# ==========================================
if [[ "$SETUP_VPN_AUTH" =~ ^[Yy] ]]; then
  echo "Configuring OpenVPN credentials..."
  mkdir -p /etc/openvpn/client
  
  # Create the auth.txt file securely
  cat << EOF > /etc/openvpn/client/auth.txt
$VPN_USER
$VPN_PASS
EOF
  
  # Set strict permissions so only root can read it
  chmod 600 /etc/openvpn/client/auth.txt
  echo "Credentials saved securely to /etc/openvpn/client/auth.txt"
fi

# ==========================================
# AUTO-WIFI CONFIGURATION
# ==========================================
if [[ "$AUTO_WIFI" =~ ^[Yy] ]]; then
  echo "Configuring Automatic Open WiFi connection..."
  
  cat << 'EOF' > /usr/local/bin/auto-open-wifi.sh
#!/bin/bash
WIFI_DEV=$(nmcli -t -f DEVICE,TYPE dev status | grep ":wifi$" | cut -d: -f1 | head -n 1)
[ -z "$WIFI_DEV" ] && exit 1

if nmcli -t -f DEVICE,STATE dev status | grep "^${WIFI_DEV}:connected" > /dev/null; then
    exit 0
fi

nmcli dev wifi rescan 2>/dev/null
sleep 5

OPEN_SSID=$(nmcli -t -f SSID,SECURITY dev wifi list | grep ':--$' | head -n 1 | sed 's/:--$//')

if [ -n "$OPEN_SSID" ]; then
    nmcli dev wifi connect "$OPEN_SSID" ifname "$WIFI_DEV"
fi
EOF
  chmod +x /usr/local/bin/auto-open-wifi.sh

  cat << 'EOF' > /etc/systemd/system/auto-open-wifi.service
[Unit]
Description=Auto connect to open WiFi networks
After=network.target NetworkManager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/auto-open-wifi.sh
EOF

  cat << 'EOF' > /etc/systemd/system/auto-open-wifi.timer
[Unit]
Description=Run auto open WiFi connector every minute

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable auto-open-wifi.timer
  systemctl start auto-open-wifi.timer
  echo "Auto Open WiFi feature installed and activated."
fi

echo "========================================="
echo "Setup almost complete! Final steps:"
echo "1. Copy your router's .ovpn file to /etc/openvpn/client/asus.conf"
echo "2. Edit it (nano /etc/openvpn/client/asus.conf) and ensure it has:"
echo "   auth-user-pass auth.txt"
echo "3. Run: sudo systemctl enable --now openvpn-client@asus"
echo "========================================="
