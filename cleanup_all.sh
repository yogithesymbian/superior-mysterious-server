#!/bin/bash
# cleanup_all.sh
# Remove all Nginx sites and SSL certificates (full cleanup)

ok() { printf '\e[32m✓ %s\e[m\n' "$1"; }
info() { printf '\e[36mℹ %s\e[m\n' "$1"; }
warn() { printf '\e[33m⚠ %s\e[m\n' "$1"; }
die() { printf '\e[1;31m✗ %s\e[m\n' "$1"; exit 1; }

[ $(id -g) != "0" ] && die "Script must be running as root. Use: sudo $0"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ⚠️  FULL CLEANUP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
warn "This will remove ALL Nginx sites and SSL certificates!"
echo ""
echo "Will remove:"
echo "  • /etc/nginx/sites-available/*"
echo "  • /etc/nginx/sites-enabled/*"
echo "  • /etc/letsencrypt/*"
echo "  • /var/lib/letsencrypt/*"
echo "  • /var/log/letsencrypt/*"
echo "  • Optionally: /var/www subdirectories"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "⚠️  Proceed? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && die "Cleanup cancelled"

echo ""
ok "Stopping Nginx..."
systemctl stop nginx

ok "Removing Nginx sites..."
rm -rf /etc/nginx/sites-available/*
rm -rf /etc/nginx/sites-enabled/*

ok "Removing certbot certificates..."
certbot delete --non-interactive 2>/dev/null || true

ok "Removing Let's Encrypt data..."
rm -rf /etc/letsencrypt
rm -rf /var/lib/letsencrypt
rm -rf /var/log/letsencrypt

# Ask if user wants to remove /var/www data
echo ""
read -p "Remove /var/www data? (y/n): " REMOVE_WWW
if [ "$REMOVE_WWW" = "y" ]; then
    ok "Removing /var/www..."
    rm -rf /var/www/*
fi

ok "Starting Nginx..."
systemctl start nginx

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Cleanup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
ok "Server is clean and ready for new setup"
echo ""
