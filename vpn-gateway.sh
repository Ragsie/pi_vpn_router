#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run the script as root (sudo bash vpn-gateway.sh)"
  exit
fi

# ==========================================
# FUNCTION: FULL INITIAL SETUP
# ==========================================
function initial_setup() {
  clear
  echo "================================================="
  echo "           FULL INSTALLATION & SETUP             "
  echo "================================================="
  read -p "Enter Gateway IP (Pi's IP) [Default: 192.168.50.1]: " GATEWAY_IP
  GATEWAY_IP=${GATEWAY_IP:-192.168.50.1}

  read -p "Enter PC IP (DHCP assignment) [Default: 192.168.50.10]: " PC_IP
  PC_IP=${PC_IP:-192.168.50.10} 

  read -p "Enter ports to forward (comma separated) [Default: 80,8080]: " FORWARD_PORTS
  FORWARD_PORTS=${FORWARD_PORTS:-80,8080}

  echo "---------------------------------"
  echo "Updating system and installing packages..."
  export DEBIAN_FRONTEND=noninteractive
  apt update
  apt install -y openvpn dnsmasq network-manager iptables-persistent netfilter-persistent resolvconf

  echo "Configuring Ethernet (eth0) with NetworkManager..."
  nmcli con delete eth0-local 2>/dev/null || true
  nmcli con add type ethernet ifname eth0 ipv4.method manual ipv4.addresses $GATEWAY_IP/24 ipv4.gateway "" ipv4.dns "" connection.id "eth0-local"
  nmcli con up eth0-local

  echo "Enabling IP Forwarding..."
  echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-vpn-forward.conf
  sysctl -p /etc/sysctl.d/99-vpn-forward.conf

  echo "Configuring DHCP (dnsmasq)..."
  cat <<EOF > /etc/dnsmasq.conf
interface=eth0
dhcp-range=$PC_IP,$PC_IP,255.255.255.0,24h
dhcp-option=3,$GATEWAY_IP
dhcp-option=6,$GATEWAY_IP
EOF
  systemctl restart dnsmasq
  systemctl enable dnsmasq

  echo "Configuring Firewall & Kill Switch..."
  iptables -F
  iptables -t nat -F
  iptables -P FORWARD DROP
  iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
  iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

  IFS=',' read -ra PORT_ARRAY <<< "$FORWARD_PORTS"
  for PORT in "${PORT_ARRAY[@]}"; do
    PORT=$(echo "$PORT" | xargs)
    iptables -t nat -A PREROUTING -i tun0 -p tcp -m tcp --dport $PORT -j DNAT --to-destination $PC_IP:$PORT
  done
  iptables -A FORWARD -d $PC_IP/32 -i tun0 -o eth0 -p tcp -m multiport --dports $FORWARD_PORTS -j ACCEPT

  netfilter-persistent save >/dev/null 2>&1
  
  echo "================================================="
  echo "Initial setup complete! You can now use the menu"
  echo "to enable Auto-WiFi and VPN Auto-login."
  echo "================================================="
  read -p "Press Enter to return to the menu..."
}

# ==========================================
# FUNCTION: MANAGE PORTS                   
# ==========================================
function manage_ports() {
  clear
  echo "================================================="
  echo "           CHANGE PORT FORWARDING                "
  echo "================================================="
  read -p "Enter new ports (comma separated, e.g., 80,8080): " NEW_PORTS
  if [ -z "$NEW_PORTS" ]; then
      echo "No ports entered. Canceling..."
      sleep 2
      return
  fi

  PC_IP=$(grep '^dhcp-range=' /etc/dnsmasq.conf 2>/dev/null | awk -F'[=,]' '{print $2}')
  if [ -z "$PC_IP" ]; then
      read -p "Could not find PC IP automatically. Enter PC IP: " PC_IP
  fi

  echo "Updating firewall rules for ports: $NEW_PORTS (Forwarding to $PC_IP)..."
  iptables -F
  iptables -t nat -F
  iptables -P FORWARD DROP
  iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
  iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

  IFS=',' read -ra PORT_ARRAY <<< "$NEW_PORTS"
  for PORT in "${PORT_ARRAY[@]}"; do
    PORT=$(echo "$PORT" | xargs)
    iptables -t nat -A PREROUTING -i tun0 -p tcp -m tcp --dport $PORT -j DNAT --to-destination $PC_IP:$PORT
  done
  iptables -A FORWARD -d $PC_IP/32 -i tun0 -o eth0 -p tcp -m multiport --dports $NEW_PORTS -j ACCEPT

  netfilter-persistent save >/dev/null 2>&1
  echo "Ports updated successfully!"
  sleep 2
}

# ==========================================
# FUNCTION: OPENVPN AUTH MANAGEMENT
# ==========================================
function toggle_auth() {
  clear
  echo "================================================="
  echo "           OPENVPN AUTO-LOGIN                    "
  echo "================================================="
  if [ -f "/etc/openvpn/client/auth.txt" ]; then
      rm -f /etc/openvpn/client/auth.txt
      echo "auth.txt is now deleted! Auto-login is DISABLED."
  else
      read -p "Enter OpenVPN Username: " VPN_USER
      echo "(Note: Your password is hidden as you type)"
      read -s -p "Enter OpenVPN Password: " VPN_PASS
      echo ""
      
      mkdir -p /etc/openvpn/client
      cat << EOF > /etc/openvpn/client/auth.txt
$VPN_USER
$VPN_PASS
EOF
      chmod 600 /etc/openvpn/client/auth.txt
      echo "auth.txt created with strict permissions! Auto-login is ENABLED."
  fi
  sleep 3
}

# ==========================================
# FUNCTION: AUTO WIFI MANAGEMENT
# ==========================================
function toggle_wifi() {
  clear
  echo "================================================="
  echo "           AUTO-CONNECT TO OPEN WIFI             "
  echo "================================================="
  if systemctl is-active --quiet auto-open-wifi.timer 2>/dev/null; then
      echo "Stopping and removing Auto-WiFi services..."
      systemctl stop auto-open-wifi.timer auto-open-wifi.service 2>/dev/null
      systemctl disable auto-open-wifi.timer 2>/dev/null
      rm -f /etc/systemd/system/auto-open-wifi.timer
      rm -f /etc/systemd/system/auto-open-wifi.service
      rm -f /usr/local/bin/auto-open-wifi.sh
      systemctl daemon-reload
      echo "Auto Open WiFi is now DISABLED and removed!"
  else
      echo "Installing Auto-WiFi script and timer..."
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
      systemctl enable auto-open-wifi.timer >/dev/null 2>&1
      systemctl start auto-open-wifi.timer
      echo "Auto Open WiFi is now INSTALLED and ENABLED!"
  fi
  sleep 3
}

# ==========================================
# MAIN MENU LOOP
# ==========================================
while true; do
  clear
  echo "================================================="
  echo "        VPN GATEWAY MANAGER (All-in-One)         "
  echo "================================================="

  # Status checks for menu text
  if [ -f "/etc/openvpn/client/auth.txt" ]; then
      AUTH_TEXT="[ACTIVE - Select to remove]"
  else
      AUTH_TEXT="[INACTIVE - Select to create]"
  fi

  if systemctl is-active --quiet auto-open-wifi.timer 2>/dev/null; then
      WIFI_TEXT="[ACTIVE - Select to remove]"
  else
      WIFI_TEXT="[INACTIVE - Select to install]"
  fi

  echo "1) Run full initial setup (First time)"
  echo "2) Change Port Forwarding (NAT rules)"
  echo "3) Toggle OpenVPN Auto-login (auth.txt)   $AUTH_TEXT"
  echo "4) Toggle Auto-Connect to open WiFi       $WIFI_TEXT"
  echo "5) Show finalization instructions (.ovpn)"
  echo "6) Exit"
  echo "================================================="
  read -p "Choose an option [1-6]: " OPTION

  case $OPTION in
    1) initial_setup ;;
    2) manage_ports ;;
    3) toggle_auth ;;
    4) toggle_wifi ;;
    5)
      clear
      echo "================================================="
      echo "              FINAL MANUAL STEPS                 "
      echo "================================================="
      echo "Once you have run the initial setup (Option 1), you need to:"
      echo "1. Copy your router's .ovpn file to the directory:"
      echo "   /etc/openvpn/client/asus.conf"
      echo ""
      echo "2. If you enabled Auto-login (Option 3), you must"
      echo "   edit asus.conf (nano /etc/openvpn/client/asus.conf)"
      echo "   and ensure this line is present:"
      echo "   auth-user-pass auth.txt"
      echo ""
      echo "3. Start the service with the command:"
      echo "   sudo systemctl enable --now openvpn-client@asus"
      echo "================================================="
      read -p "Press Enter to return to the menu..."
      ;;
    6)
      echo "Exiting..."
      exit 0
      ;;
    *)
      echo "Invalid option. Please try again."
      sleep 2
      ;;
  esac
done
