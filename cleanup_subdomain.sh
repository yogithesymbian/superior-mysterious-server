#!/bin/bash
# cleanup_subdomain.sh
# Remove a specific subdomain, its SSL certificate, and data

ok() { printf '\e[32m✓ %s\e[m\n' "$1"; }
info() { printf '\e[36mℹ %s\e[m\e[m\n' "$1"; }
warn() { printf '\e[33m⚠ %s\e[m\n' "$1"; }
die() { printf '\e[1;31m✗ %s\e[m\n' "$1"; exit 1; }

[ $(id -g) != "0" ] && die "Script must be running as root. Use: sudo $0"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Remove Specific Subdomain"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "📝 Main domain (e.g., sysyaw.space): " MAIN_DOMAIN
[[ -z "$MAIN_DOMAIN" ]] && die "Main domain cannot be empty"

read -p "📝 Subdomain to remove (e.g., wa, api, foo): " SUBDOMAIN
[[ -z "$SUBDOMAIN" ]] && die "Subdomain cannot be empty"

FULL_DOMAIN="$SUBDOMAIN.$MAIN_DOMAIN"

echo ""
echo "Will remove:"
echo "  • Nginx config: /etc/nginx/sites-available/$SUBDOMAIN"
echo "  • Nginx enabled: /etc/nginx/sites-enabled/$SUBDOMAIN"
echo "  • SSL cert: /etc/letsencrypt/live/$FULL_DOMAIN"
echo "  • Data: /var/www/$SUBDOMAIN"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "⚠️  Proceed? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && die "Removal cancelled"

echo ""

# Disable site
if [ -L /etc/nginx/sites-enabled/$SUBDOMAIN ]; then
    ok "Disabling Nginx site..."
    rm /etc/nginx/sites-enabled/$SUBDOMAIN
fi

# Remove Nginx config
if [ -f /etc/nginx/sites-available/$SUBDOMAIN ]; then
    ok "Removing Nginx config..."
    rm /etc/nginx/sites-available/$SUBDOMAIN
fi

# Test and reload Nginx
ok "Testing Nginx configuration..."
nginx -t &>/dev/null || die "Nginx config test failed"

ok "Reloading Nginx..."
systemctl reload nginx

# Remove SSL certificate
if [ -d /etc/letsencrypt/live/$FULL_DOMAIN ]; then
    ok "Removing SSL certificate..."
    certbot delete --cert-name $FULL_DOMAIN --non-interactive 2>/dev/null || warn "Certbot deletion had issues"
fi

# Ask if user wants to remove /var/www data
echo ""
read -p "Remove /var/www/$SUBDOMAIN data? (y/n): " REMOVE_DATA
if [ "$REMOVE_DATA" = "y" ]; then
    ok "Removing /var/www/$SUBDOMAIN..."
    rm -rf /var/www/$SUBDOMAIN
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Subdomain Removal Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
ok "Subdomain $FULL_DOMAIN has been removed"
echo ""
