# pi_vpn_router

## The script automates the complex network configuration required to turn a Raspberry pi into a routing gateway. Here is the step-by-step process:

Installs the Core Tools: It downloads and installs the necessary software: openvpn (for the VPN connection), dnsmasq (to act as a DHCP server), network-manager (to handle network interfaces), and iptables-persistent (to save your firewall rules so they survive a reboot).

Configures the Ethernet Port (eth0): It detaches the physical Ethernet port from its default automatic settings and assigns it a static, permanent IP address (192.168.50.1). This makes the Pi act as the "router" for that specific cable connection.

Sets up a Local Network (DHCP): It configures dnsmasq to listen on the Ethernet port. When you plug your PC into the Pi, dnsmasq automatically assigns the PC the IP address 192.168.50.10 and tells the PC to use the Pi as its gateway and DNS server.

Enables Kernel IP Forwarding: By default, Linux devices only care about network traffic destined for themselves. The script changes a core kernel setting (net.ipv4.ip_forward=1) that allows the Pi to act as a middleman, passing traffic from one network interface to another.

Builds the Firewall (iptables): This is the most critical part of the script. It creates strict traffic rules:

The Kill Switch: It explicitly allows traffic from your PC (eth0) to go out through the VPN tunnel (tun0), but actively blocks (drops) any traffic trying to go directly out through the WiFi (wlan0). If the VPN drops, the PC loses internet entirely, preventing accidental data leaks.

NAT (Masquerade): It hides the PC's local IP address (192.168.50.10) behind the Pi's VPN IP address. The Asus router and the internet will only see the Pi's IP.

Port Forwarding: It creates a set of rules stating: "If anyone on the VPN network tries to access port 80 or 8080 on the Pi, immediately forward that request through the Ethernet cable to the PC on 192.168.50.10."


# The Final Result:

Once the script has run and your OpenVPN configuration is active, you will have a highly secure, automated Headless VPN Gateway.

## Here is how the final architecture works in practice:

Plug-and-Play Security: You power on the Raspberry Pi. It automatically connects to the local WiFi and establishes a secure OpenVPN tunnel to your Asus router at home.

Isolated PC Environment: When you plug your PC into the Pi's RJ45 Ethernet port, the PC instantly gets an internet connection. However, this connection is 100% tunneled through your home network. The PC has no direct access to the local WiFi network the Pi is connected to.

Leak Protection: Because of the kill switch and the update-resolv-conf DNS settings, neither the PC nor the Pi will leak your DNS requests or real IP address to the local WiFi provider.

Two-Way Accessibility:

Your PC can browse the internet and access all devices on your home network just as if it were physically plugged into the Asus router.

You (or any device on your home network) can type the Pi's VPN IP address into a browser, and the Pi will seamlessly forward you to the web server/services running on ports 80 and 8080 on your connected PC.

Resilience: Because it is designed to run headless, if the WiFi drops or the Pi loses power, it will automatically try to re-establish the WiFi connection and rebuild the VPN tunnel without requiring a monitor, keyboard, or any user input.


# Installation Guide
### Step-by-Step Instructions

1. Create the file on your Pi, for example with nano ```sudo nano vpn-router-setup.sh``` copy the script and insert it save and exit (CTRL+O, Enter CTRL+X)
2. Make the script executable and run it: ```chmod +x vpn-router-setup.sh```, ```sudo ./vpn-router-setup.sh```.
3. follow instructions of the script
4. Add your Openvpn config file. the extension must be .conf here ```sudo nano /etc/openvpn/client/openvpn-config-file.conf``` (```openvpn-config-file```can be changed to your own file name ```.conf``` must stay).

# Options
use mangager.sh to:

### change port(s)
### open wifi logon

### auto vpnlogon
Adjust openvpn-config-file.conf File:

```sudo nano /etc/openvpn/client/openvpn-config-file.conf```
Add  ```auth-user-pass auth.txt``` see example below
## example

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
Save and Exit (CTRL+O Enter CTRL+X)
