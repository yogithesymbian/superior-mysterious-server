#!/bin/bash
# cleanup_maindomain.sh
# Remove main domain, its SSL certificate, and data

ok() { printf '\e[32m✓ %s\e[m\n' "$1"; }
info() { printf '\e[36mℹ %s\e[m\n' "$1"; }
warn() { printf '\e[33m⚠ %s\e[m\n' "$1"; }
die() { printf '\e[1;31m✗ %s\e[m\n' "$1"; exit 1; }

[ $(id -g) != "0" ] && die "Script must be running as root. Use: sudo $0"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Remove Main Domain"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "📝 Main domain to remove (e.g., salpalaran.com): " MAIN_DOMAIN
[[ -z "$MAIN_DOMAIN" ]] && die "Main domain cannot be empty"

echo ""
echo "Will remove:"
echo "  • Nginx config: /etc/nginx/sites-available/default"
echo "  • Nginx enabled: /etc/nginx/sites-enabled/default"
echo "  • SSL cert: /etc/letsencrypt/live/$MAIN_DOMAIN"
echo "  • Data: /var/www/html"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "⚠️  Proceed? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && die "Removal cancelled"

echo ""

# Disable site
if [ -L /etc/nginx/sites-enabled/default ]; then
    ok "Disabling Nginx site..."
    rm /etc/nginx/sites-enabled/default
fi

# Remove Nginx config
if [ -f /etc/nginx/sites-available/default ]; then
    ok "Removing Nginx config..."
    rm /etc/nginx/sites-available/default
fi

# Test and reload Nginx
ok "Testing Nginx configuration..."
nginx -t &>/dev/null || die "Nginx config test failed"

ok "Reloading Nginx..."
systemctl reload nginx

# Remove SSL certificate
if [ -d /etc/letsencrypt/live/$MAIN_DOMAIN ]; then
    ok "Removing SSL certificate..."
    certbot delete --cert-name $MAIN_DOMAIN --non-interactive 2>/dev/null || warn "Certbot deletion had issues"
fi

# Ask if user wants to remove /var/www/html data
echo ""
read -p "Remove /var/www/html data? (y/n): " REMOVE_DATA
if [ "$REMOVE_DATA" = "y" ]; then
    ok "Removing /var/www/html..."
    rm -rf /var/www/html/*
    ok "Directory /var/www/html is now empty"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Main Domain Removal Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
ok "Main domain $MAIN_DOMAIN has been removed"
echo ""
