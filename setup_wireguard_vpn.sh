#!/bin/bash

WG_DIR="/etc/wireguard"
CLIENT_DIR="$WG_DIR/clients"
WG_IF="wg0"
WG_PORT=51820

WG_IPV4_NET="10.8.0.0/24"
WG_IPV4_SERVER="10.8.0.1"

WG_IPV6_NET="fd86:ea04:1111::/64"
WG_IPV6_SERVER="fd86:ea04:1111::1"

SERVER_PRIV_KEY="$WG_DIR/server_private.key"
SERVER_PUB_KEY="$WG_DIR/server_public.key"

mkdir -p $CLIENT_DIR

get_public_ip() {
  curl -s ifconfig.me
}

enable_forwarding() {
  sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
  sed -i 's/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/' /etc/sysctl.conf
  sysctl -p
}

install_wireguard() {
  echo "== Installing WireGuard (IPv4 + IPv6) =="

  apt update -y
  apt install wireguard qrencode iptables ip6tables -y

  enable_forwarding

  cd $WG_DIR || exit
  umask 077

  wg genkey | tee server_private.key | wg pubkey > server_public.key

  cat > $WG_IF.conf <<EOF
[Interface]
Address = $WG_IPV4_SERVER/24, $WG_IPV6_SERVER/64
ListenPort = $WG_PORT
PrivateKey = $(cat server_private.key)

PostUp = \
iptables -A FORWARD -i $WG_IF -j ACCEPT; \
iptables -A FORWARD -o $WG_IF -j ACCEPT; \
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; \
ip6tables -A FORWARD -i $WG_IF -j ACCEPT; \
ip6tables -A FORWARD -o $WG_IF -j ACCEPT

PostDown = \
iptables -D FORWARD -i $WG_IF -j ACCEPT; \
iptables -D FORWARD -o $WG_IF -j ACCEPT; \
iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; \
ip6tables -D FORWARD -i $WG_IF -j ACCEPT; \
ip6tables -D FORWARD -o $WG_IF -j ACCEPT
EOF

  systemctl enable wg-quick@$WG_IF
  systemctl start wg-quick@$WG_IF

  echo "✅ WireGuard dual-stack ready"
}

next_ip() {
  LAST=$(grep AllowedIPs $WG_DIR/$WG_IF.conf | grep 10.8.0 | awk -F'[./]' '{print $4}' | sort -n | tail -1)
  [ -z "$LAST" ] && echo "2" || echo $((LAST + 1))
}

add_client() {
  read -p "Client name: " CLIENT
  IP_LAST=$(next_ip)

  IPV4="10.8.0.$IP_LAST"
  IPV6="fd86:ea04:1111::$IP_LAST"

  wg genkey | tee $CLIENT_DIR/${CLIENT}_private.key | wg pubkey > $CLIENT_DIR/${CLIENT}_public.key

  cat >> $WG_DIR/$WG_IF.conf <<EOF

[Peer]
PublicKey = $(cat $CLIENT_DIR/${CLIENT}_public.key)
AllowedIPs = $IPV4/32, $IPV6/128
EOF

  systemctl restart wg-quick@$WG_IF

  cat > $CLIENT_DIR/${CLIENT}.conf <<EOF
[Interface]
PrivateKey = $(cat $CLIENT_DIR/${CLIENT}_private.key)
Address = $IPV4/24, $IPV6/64
DNS = 1.1.1.1, 2606:4700:4700::1111

[Peer]
PublicKey = $(cat $SERVER_PUB_KEY)
Endpoint = $(get_public_ip):$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

  echo
  echo "📱 QR Code ($CLIENT)"
  qrencode -t ansiutf8 < $CLIENT_DIR/${CLIENT}.conf
  echo
  echo "Config: $CLIENT_DIR/${CLIENT}.conf"
}

list_clients() {
  grep -n "\[Peer\]" $WG_DIR/$WG_IF.conf
}

remove_client() {
  read -p "Client name to remove: " CLIENT
  PUB=$(cat $CLIENT_DIR/${CLIENT}_public.key 2>/dev/null)

  [ -z "$PUB" ] && echo "❌ Client not found" && return

  sed -i "/$PUB/,+2d" $WG_DIR/$WG_IF.conf
  systemctl restart wg-quick@$WG_IF
  rm -f $CLIENT_DIR/${CLIENT}*

  echo "🗑️ Client removed"
}

menu() {
  clear
  echo "====== WireGuard Manager (IPv4 + IPv6) ======"
  echo "1) Install WireGuard"
  echo "2) Add client"
  echo "3) List clients"
  echo "4) Remove client"
  echo "5) Exit"
  echo "============================================"
  read -p "Choose: " C

  case $C in
    1) install_wireguard ;;
    2) add_client ;;
    3) list_clients ;;
    4) remove_client ;;
    5) exit ;;
  esac
}

while true; do
  menu
  read -p "Press enter to continue..."
done
