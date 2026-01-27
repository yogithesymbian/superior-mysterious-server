#!/bin/bash
# setup_main_domain.sh
# Initialize main domain with Nginx and SSL (one-time setup)

ok() { printf '\e[32m✓ %s\e[m\n' "$1"; }
info() { printf '\e[36mℹ %s\e[m\n' "$1"; }
warn() { printf '\e[33m⚠ %s\e[m\n' "$1"; }
die() { printf '\e[1;31m✗ %s\e[m\n' "$1"; exit 1; }

[ $(id -g) != "0" ] && die "Script must be running as root. Use: sudo $0"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Main Domain Setup (Fresh Install)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "📝 Main domain (e.g., sysyaw.space): " MAIN_DOMAIN
[[ -z "$MAIN_DOMAIN" ]] && die "Domain cannot be empty"

read -p "📧 Email for Let's Encrypt: " CERT_EMAIL
[[ -z "$CERT_EMAIL" ]] && die "Email cannot be empty"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Domain:      $MAIN_DOMAIN"
echo "Email:       $CERT_EMAIL"
echo "⚠️  This will remove ALL existing nginx sites & SSL certs"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "Proceed? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && die "Setup cancelled"

# Fresh install - remove everything
ok "Stopping Nginx..."
systemctl stop nginx

ok "Removing all existing sites..."
rm -rf /etc/nginx/sites-available/*
rm -rf /etc/nginx/sites-enabled/*

ok "Removing all certbot certificates..."
certbot delete --non-interactive 2>/dev/null || true

ok "Cleaning certbot..."
rm -rf /etc/letsencrypt
rm -rf /var/lib/letsencrypt
rm -rf /var/log/letsencrypt

ok "Starting Nginx..."
systemctl start nginx

# Create directories
ok "Creating directories..."
mkdir -p /var/www/html
mkdir -p /var/www/.well-known/acme-challenge

# Create index file
ok "Creating index page..."
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
<head><title>Main Domain</title></head>
<body><h1>Main domain is active ✓</h1></body>
</html>
EOF

# Create Nginx config (HTTP only - for ACME challenge)
ok "Creating Nginx configuration..."
cat > /etc/nginx/sites-available/default <<EOF
# HTTP - for ACME challenge
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;

    location /.well-known/acme-challenge/ {
        root /var/www;
    }

    location / {
        if (\$host != "") {
            return 301 https://\$host\$request_uri;
        }
        return 404;
    }
}
EOF

# Enable site
ok "Enabling site..."
ln -sf /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

# Test and reload nginx
ok "Testing Nginx configuration..."
if ! nginx -t 2>&1; then
    die "Nginx config test failed - check /var/log/nginx/error.log"
fi

ok "Reloading Nginx..."
systemctl reload nginx
sleep 2

# Check if nginx is actually running
ok "Verifying Nginx service..."
if ! systemctl is-active --quiet nginx; then
    die "Nginx service is not running"
fi
ok "Nginx service is running ✓"

# Test DNS resolution
ok "Testing DNS resolution..."
DNS_IP=$(dig +short $MAIN_DOMAIN @8.8.8.8 | tail -1)
if [ -z "$DNS_IP" ]; then
    die "DNS resolution failed for $MAIN_DOMAIN"
fi
ok "DNS resolves to: $DNS_IP"

# Get current server IP
SERVER_IP=$(hostname -I | awk '{print $1}')
ok "Server IP: $SERVER_IP"

if [ "$DNS_IP" != "$SERVER_IP" ]; then
    warn "DNS IP ($DNS_IP) doesn't match server IP ($SERVER_IP)"
    info "Update your DNS A record to point to: $SERVER_IP"
fi

# Install certbot if needed
if ! command -v certbot &> /dev/null; then
    ok "Installing certbot..."
    apt install -y certbot python3-certbot-nginx
fi

# Run certbot with manual SSL setup (matches main.domain approach)
ok "Setting up SSL with certbot..."
certbot certonly --webroot -w /var/www -d $MAIN_DOMAIN -d www.$MAIN_DOMAIN \
    --non-interactive --agree-tos --email "$CERT_EMAIL"

if [ $? -ne 0 ]; then
    die "Certbot setup failed. Check DNS records."
fi

# Generate SSL options if missing
if [ ! -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
    ok "Generating SSL configuration..."
    mkdir -p /etc/letsencrypt
    cat > /etc/letsencrypt/options-ssl-nginx.conf <<'SSLEOF'
ssl_protocols TLSv1.2 TLSv1.3;
ssl_prefer_server_ciphers on;
ssl_ciphers HIGH:!aNULL:!MD5;
SSLEOF
fi

# Generate DH params if missing
if [ ! -f /etc/letsencrypt/ssl-dhparams.pem ]; then
    ok "Generating DH parameters (this may take a moment)..."
    openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
fi

# Update Nginx config with SSL certificates
ok "Updating Nginx configuration with SSL..."
cat > /etc/nginx/sites-available/default <<EOF
# HTTP redirect
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;

    location /.well-known/acme-challenge/ {
        root /var/www;
    }

    location / {
        if (\$host != "") {
            return 301 https://\$host\$request_uri;
        }
        return 404;
    }
}

# HTTPS - www redirect
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name www.$MAIN_DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    location / {
        return 301 https://$MAIN_DOMAIN\$request_uri;
    }
}

# HTTPS - main domain
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $MAIN_DOMAIN;
    root /var/www/html;

    ssl_certificate /etc/letsencrypt/live/$MAIN_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$MAIN_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

ok "Testing Nginx configuration..."
nginx -t || die "Final Nginx config test failed"

ok "Reloading Nginx..."
systemctl reload nginx

ok "Testing renewal..."
certbot renew --dry-run

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Main Domain Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "🌐 Access: https://$MAIN_DOMAIN\n"
echo ""

ok "Testing SSL..."
curl -I https://$MAIN_DOMAIN

echo ""
ok "Done! Now run: sudo ./setup_subdomain.sh"
