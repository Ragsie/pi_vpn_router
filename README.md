

# Headless Raspberry Pi VPN Gateway
Transforms a Raspberry Pi into a fully automated, plug-and-play VPN gateway for a connected PC. It routes all traffic from the PC through an OpenVPN tunnel and features a strict hardware-level kill switch.

This setup is ideal for traveling, working from hotels, or maintaining a secure connection on untrusted networks without needing to interact with the Pi after the initial setup.

## ✨ Features
Strict Kill Switch (iptables): If the VPN tunnel drops, all internet traffic from the PC is immediately blocked. No data leaks.

Auto-Connect to Open WiFi: An optional background service automatically scans for and connects to the strongest open (unsecured) WiFi network available.

Dynamic Port Forwarding: Easily forward specific ports through the VPN tunnel to your connected PC.

OpenVPN Auto-Authentication: Securely generate and store your OpenVPN credentials (chmod 600) for seamless, unattended reboots.

Interactive Management: Includes a manage.sh script with a CLI menu to easily toggle features or update port forwarding rules on the fly.

## 🛠️ Prerequisites
Hardware: A Raspberry Pi or Equal other boards(with both WiFi and an Ethernet port) and an Ethernet cable connecting it to your PC.

OS: Debian Trixie (or a recent Raspberry Pi OS).

Network Topology:

wlan0 (WiFi): Connects to the internet.

eth0 (Ethernet): Connects to your PC (provides a local DHCP IP).

tun0 (VPN): The secure tunnel created by OpenVPN.

```
[ Public / Unsecure WiFi ] 
           (Hotel, Café)
                 │
                 ▼
          [ wlan0 ] (Pi's WiFi Receives unencrypted internet)
 ┌─────────────────────────────────────────────────────────────┐
 │                    RASPBERRY PI (VPN GATEWAY)               │
 │                                                             │
 │  [ OpenVPN Client (tun0) ] ◄══════ ENCRYPTED TUNNEL ════════╬══► [ YOUR VPN HOST]
 │             ▲                                               │             │
 │             │ (iptables Kill Switch & Port Forwarding)      │             ▼
 │             ▼                                               │    [If self-hosted VPN server ]
 |                                                             |      [Home/office & Internet ]
 │      [ eth0 (LAN) ]                                         │      (E.g Media server)
 │      IP: x.x.x.x                                            │
 └─────────────┬───────────────────────────────────────────────┘
               │ 
          (Lan Cable)
               │
               ▼
        [ Your Laptop / PC ]
        IP: x.x.x.x (Assigned by DHCP/dnsmasq)
````


# 🚀 Installation
### Step-by-Step Instructions

1. Clone this repository to your Raspberry Pi:
```
git clone https://github.com/Ragsie/pi_vpn_router.git
cd pi_vpn_router
```
2. Run to make the scripts executable:```sudo chmod +x vpn-gateway.sh``` 
3. Run the setup script as root: ```sudo ./vpn-gateway.sh```
4. follow instructions of the script.

# ⚙️ Post-Installation (Adding your VPN Profile)
Once the setup script finishes, you need to provide your OpenVPN configuration file (e.g., from your Asus router or VPN provider):

1. Copy your .ovpn file to the OpenVPN client directory and rename it to Your-VPN-File.conf: ```sudo cp your-profile.ovpn /etc/openvpn/client/Your-VPN-File.conf```
2. Do only this step If you chose to set up the auto-login file during setup.sh, edit the Your-VPN-File.conf file to point to it. Run ```sudo nano /etc/openvpn/client/Your-VPN-File.conf``` Find the auth-user-pass line and change it to:```auth-user-pass auth.txt``` save and exit (Ctr+O, Enter, Ctrl+X)
3. Enable and start the OpenVPN service: ```sudo systemctl enable --now openvpn-client@asus```

### example for step 2

```
client
dev
tun
remote
resolv-retry
infinite
nobind
persist-key
persist-tun
tls-auth
verb 1k
eepalive 10 120
port 1194
proto udp
cipher BF-CBC
remote-cert-tls server
auth-user-pass auth.txt  # add here
<ca>
-----BEGIN CERTIFICATE-----
```


# 🧰 The Management Menu
Need to change an open port or turn off the Auto-WiFi feature later? Simply run the management script:

```sudo ./manage.sh```
Menu Options:

1. Change Port Forwarding: Automatically detects your PC's IP and applies new iptables NAT rules.

2. Toggle OpenVPN Auto-login: Create or delete your auth.txt credentials file.

3. Toggle Auto-Connect to Open WiFi: Installs or completely removes the background systemd timer for WiFi hunting.


# ⚠️ Known Limitations: Captive Portals
The Auto-Connect to Open WiFi feature works perfectly on truly open networks. However, many hotels and cafes use "Captive Portals" (a webpage where you must click "Accept Terms" before getting internet access).

Because the strict Kill Switch drops all non-VPN traffic, your PC will not be able to load the Captive Portal page.

Workaround: Connect your smartphone to the hotel WiFi, accept the terms, and then clone your phone's MAC address to the Raspberry Pi's wlan0 interface.

### bug's
none knowen please report bugs if found


## ☕ Support The Project
If this project helped you or inspired your own build, consider buying me a cup of coffee. It would make my day and support me in developing more!
please note that this project is, and will always remain, **100% free and open-source** under the **GNU GPLv3 License** in accordance with the licenses of our upstream dependencies.

[![Buy Me A Coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&emoji=&slug=ragsie&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff)](https://buymeacoffee.com/ragsie)

| Coin | QR | Address |
| :-- | :--- | :---: |
| **Bitcoin Cash** | <img width="160" height="161" alt="qrcode" src="https://github.com/user-attachments/assets/254aece9-8957-4d34-812c-885ac2e839fa" /> | `bitcoincash:qzp4c7klef8q6gxycvc84dx0fnhnfxkkpy6xda56h3` |
| **Bitcoin** | <img width="160" height="162" alt="image" src="https://github.com/user-attachments/assets/e5b1cd3d-fd26-46fc-88db-2aa931b4f5d4" /> | `3QrAPVGC3aypf3LG5DYYRnjwjKuFMzkeJE` |
