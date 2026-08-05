#!/bin/bash

# Sørg for at scriptet køres som root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root (sudo bash manage.sh)"
  exit
fi

while true; do
  clear
  echo "================================================="
  echo "           VPN GATEWAY MANAGER MENU              "
  echo "================================================="

  # --- Tjekker status for OpenVPN Auth ---
  if [ -f "/etc/openvpn/client/auth.txt" ]; then
      AUTH_TEXT="[AKTIV - Vælg for at slette]"
      AUTH_STATE=1
  else
      AUTH_TEXT="[INAKTIV - Vælg for at oprette]"
      AUTH_STATE=0
  fi

  # --- Tjekker status for Auto Open WiFi ---
  if systemctl is-active --quiet auto-open-wifi.timer 2>/dev/null; then
      WIFI_TEXT="[AKTIV - Vælg for at deaktivere/slette]"
      WIFI_STATE=1
  else
      WIFI_TEXT="[INAKTIV - Vælg for at installere]"
      WIFI_STATE=0
  fi

  echo "1) Ændre Port Forwarding (NAT regler)"
  echo "2) Slå OpenVPN Auto-login (auth.txt) til/fra $AUTH_TEXT"
  echo "3) Slå Auto-Connect til åbne WiFi til/fra    $WIFI_TEXT"
  echo "4) Afslut"
  echo "================================================="
  read -p "Vælg en mulighed [1-4]: " OPTION

  case $OPTION in
    1)
      echo ""
      read -p "Indtast nye porte (adskilt med komma, f.eks. 80,8080): " NEW_PORTS
      if [ -z "$NEW_PORTS" ]; then
          echo "Ingen porte indtastet. Annullerer..."
          sleep 2
          continue
      fi

      # Prøver at finde PC'ens IP fra dnsmasq automatisk
      PC_IP=$(grep '^dhcp-range=' /etc/dnsmasq.conf 2>/dev/null | awk -F'[=,]' '{print $2}')
      
      # Hvis den ikke kan finde IP'en, spørger den dig
      if [ -z "$PC_IP" ]; then
          read -p "Kunne ikke finde PC IP automatisk. Indtast PC IP: " PC_IP
      fi

      echo "Opdaterer firewall regler for porte: $NEW_PORTS (Sender til $PC_IP)..."
      
      # Nulstiller firewall
      iptables -F
      iptables -t nat -F
      iptables -P FORWARD DROP

      # Genskaber standard routing for VPN
      iptables -A FORWARD -i eth0 -o tun0 -j ACCEPT
      iptables -A FORWARD -i tun0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
      iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE

      # Opretter de nye port-regler
      IFS=',' read -ra PORT_ARRAY <<< "$NEW_PORTS"
      for PORT in "${PORT_ARRAY[@]}"; do
        PORT=$(echo "$PORT" | xargs)
        iptables -t nat -A PREROUTING -i tun0 -p tcp -m tcp --dport $PORT -j DNAT --to-destination $PC_IP:$PORT
      done

      # Giver tilladelse til de nye porte i filteret
      iptables -A FORWARD -d $PC_IP/32 -i tun0 -o eth0 -p tcp -m multiport --dports $NEW_PORTS -j ACCEPT

      # Gemmer reglerne permanent
      netfilter-persistent save >/dev/null 2>&1
      echo "Porte opdateret succesfuldt!"
      sleep 2
      ;;

    2)
      echo ""
      if [ $AUTH_STATE -eq 1 ]; then
          # Slet filen hvis den eksisterer
          rm -f /etc/openvpn/client/auth.txt
          echo "auth.txt er nu slettet!"
          echo "Husk evt. at fjerne 'auth-user-pass auth.txt' linjen i din .ovpn fil."
      else
          # Opret filen hvis den ikke eksisterer
          read -p "Indtast OpenVPN Brugernavn: " VPN_USER
          echo "(Note: Dit password skjules mens du taster)"
          read -s -p "Indtast OpenVPN Password: " VPN_PASS
          echo ""
          
          mkdir -p /etc/openvpn/client
          cat << EOF > /etc/openvpn/client/auth.txt
$VPN_USER
$VPN_PASS
EOF
          chmod 600 /etc/openvpn/client/auth.txt
          echo "auth.txt oprettet med strenge rettigheder (chmod 600)!"
      fi
      sleep 4
      ;;

    3)
      echo ""
      if [ $WIFI_STATE -eq 1 ]; then
          # Deaktiver og fjern hvis det allerede kører
          echo "Stopper og fjerner Auto-WiFi tjenester..."
          systemctl stop auto-open-wifi.timer auto-open-wifi.service 2>/dev/null
          systemctl disable auto-open-wifi.timer 2>/dev/null
          rm -f /etc/systemd/system/auto-open-wifi.timer
          rm -f /etc/systemd/system/auto-open-wifi.service
          rm -f /usr/local/bin/auto-open-wifi.sh
          systemctl daemon-reload
          echo "Auto Open WiFi er nu deaktiveret og slettet!"
      else
          # Installer hvis det ikke kører
          echo "Installerer Auto-WiFi..."
          
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
          echo "Auto Open WiFi er nu installeret og aktiveret!"
      fi
      sleep 3
      ;;

    4)
      echo "Afslutter Gateway Manager..."
      exit 0
      ;;

    *)
      echo "Ugyldigt valg. Prøv igen."
      sleep 2
      ;;
  esac
done
