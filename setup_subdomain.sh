#!/bin/bash
# setup_subdomain.sh
# Creates subdomain matching main.domain manual SSL setup

ok() { printf '\e[32m✓ %s\e[m\n' "$1"; }
info() { printf '\e[36mℹ %s\e[m\n' "$1"; }
warn() { printf '\e[33m⚠ %s\e[m\n' "$1"; }
die() { printf '\e[1;31m✗ %s\e[m\n' "$1"; exit 1; }

[ $(id -g) != "0" ] && die "Script must be running as root. Use: sudo $0"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Subdomain Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

read -p "📝 Main domain (e.g., sysyaw.space): " MAIN_DOMAIN
[[ -z "$MAIN_DOMAIN" ]] && die "Main domain cannot be empty"

read -p "📝 Subdomain (e.g., foo, api, apps): " SUBDOMAIN
[[ -z "$SUBDOMAIN" ]] && die "Subdomain cannot be empty"

FULL_DOMAIN="$SUBDOMAIN.$MAIN_DOMAIN"

echo ""
echo "Choose service type:"
echo "  1) Frontend (Static HTML/CSS/JS)"
echo "  2) Reverse Proxy (Node.js/Express/etc)"
read -p "Select (1 or 2): " SERVICE_TYPE

case $SERVICE_TYPE in
  1) SERVICE="frontend" ;;
  2)
    SERVICE="proxy"
    PORT=3000
    read -p "Backend port (default 3000): " PORT_INPUT
    [ ! -z "$PORT_INPUT" ] && PORT=$PORT_INPUT
    ;;
  *) die "Invalid option" ;;
esac

read -p "📧 Email for Let's Encrypt: " CERT_EMAIL
[[ -z "$CERT_EMAIL" ]] && die "Email cannot be empty"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Domain:       $FULL_DOMAIN"
echo "Service Type: $SERVICE"
[ "$SERVICE" = "proxy" ] && echo "Backend Port: $PORT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
read -p "Proceed? (y/n): " CONFIRM
[ "$CONFIRM" != "y" ] && die "Setup cancelled"

# Create directories
ok "Creating directories..."
mkdir -p /var/www/$SUBDOMAIN/{public_html,logs}

# Create welcome page
ok "Creating welcome page..."
cat > /var/www/$SUBDOMAIN/public_html/index.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>$FULL_DOMAIN</title>
    <style>
        body { font-family: sans-serif; text-align: center; margin: 50px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
        h1 { margin: 0; }
    </style>
</head>
<body>
    <h1>🚀 $FULL_DOMAIN</h1>
    <p>Service: $SERVICE</p>
</body>
</html>
EOF

# Create Nginx config (NO SSL YET - will add after certbot)
ok "Creating Nginx configuration..."
if [ "$SERVICE" = "frontend" ]; then
    cat > /etc/nginx/sites-available/$SUBDOMAIN <<EOF
server {
    server_name $FULL_DOMAIN www.$FULL_DOMAIN;
    root /var/www/$SUBDOMAIN/public_html;

    access_log /var/www/$SUBDOMAIN/logs/access.log;
    error_log /var/www/$SUBDOMAIN/logs/error.log;

    index index.html index.htm;
    charset utf-8;

    location /.well-known/acme-challenge/ {
        root /var/www;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt { access_log off; log_not_found off; }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

elif [ "$SERVICE" = "proxy" ]; then
    cat > /etc/nginx/sites-available/$SUBDOMAIN <<EOF
server {
    server_name $FULL_DOMAIN www.$FULL_DOMAIN;
    root /var/www/$SUBDOMAIN/public_html;

    access_log /var/www/$SUBDOMAIN/logs/access.log;
    error_log /var/www/$SUBDOMAIN/logs/error.log;

    add_header Access-Control-Allow-Origin *;
    add_header X-Frame-Options "SAMEORIGIN";

    location /.well-known/acme-challenge/ {
        root /var/www;
    }

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF
fi

# Enable site
ok "Enabling site..."
if [ ! -L /etc/nginx/sites-enabled/$SUBDOMAIN ]; then
    ln -s /etc/nginx/sites-available/$SUBDOMAIN /etc/nginx/sites-enabled/$SUBDOMAIN
fi

# Test and reload
ok "Testing Nginx configuration..."
nginx -t &>/dev/null || die "Nginx config test failed"

ok "Reloading Nginx..."
systemctl reload nginx

# Setup SSL
ok "Setting up SSL..."
if ! command -v certbot &> /dev/null; then
    apt install -y certbot python3-certbot-nginx
fi

# Generate DH params if missing (needed for both main and subdomains)
if [ ! -f /etc/letsencrypt/ssl-dhparams.pem ]; then
    ok "Generating DH parameters (this may take a moment)..."
    mkdir -p /etc/letsencrypt
    openssl dhparam -out /etc/letsencrypt/ssl-dhparams.pem 2048
fi

certbot certonly --webroot -w /var/www -d $FULL_DOMAIN -d www.$FULL_DOMAIN \
    --non-interactive --agree-tos --email "$CERT_EMAIL"

if [ $? -ne 0 ]; then
    warn "Certbot setup failed - continuing without SSL"
    info "Run later: sudo certbot certonly --webroot -w /var/www -d $FULL_DOMAIN"
else
    ok "Adding SSL to Nginx configuration..."
    
    # Create final config with SSL
    if [ "$SERVICE" = "frontend" ]; then
        cat > /etc/nginx/sites-available/$SUBDOMAIN <<EOF
server {
    server_name $FULL_DOMAIN www.$FULL_DOMAIN;
    root /var/www/$SUBDOMAIN/public_html;

    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    ssl_certificate /etc/letsencrypt/live/$FULL_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$FULL_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    access_log /var/www/$SUBDOMAIN/logs/access.log;
    error_log /var/www/$SUBDOMAIN/logs/error.log;

    index index.html index.htm;
    charset utf-8;

    location /.well-known/acme-challenge/ {
        root /var/www;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt { access_log off; log_not_found off; }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}

# HTTP redirect
server {
    listen 80;
    listen [::]:80;
    server_name $FULL_DOMAIN www.$FULL_DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF

    elif [ "$SERVICE" = "proxy" ]; then
        cat > /etc/nginx/sites-available/$SUBDOMAIN <<EOF
server {
    server_name $FULL_DOMAIN www.$FULL_DOMAIN;
    root /var/www/$SUBDOMAIN/public_html;

    listen 443 ssl http2;
    listen [::]:443 ssl http2;

    ssl_certificate /etc/letsencrypt/live/$FULL_DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$FULL_DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    access_log /var/www/$SUBDOMAIN/logs/access.log;
    error_log /var/www/$SUBDOMAIN/logs/error.log;

    add_header Access-Control-Allow-Origin *;
    add_header X-Frame-Options "SAMEORIGIN";

    location /.well-known/acme-challenge/ {
        root /var/www;
    }

    location / {
        proxy_pass http://127.0.0.1:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}

# HTTP redirect
server {
    listen 80;
    listen [::]:80;
    server_name $FULL_DOMAIN www.$FULL_DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}
EOF
    fi

    ok "Reloading Nginx with SSL..."
    nginx -t &>/dev/null || die "Final Nginx config test failed"
    systemctl reload nginx

    ok "Testing renewal..."
    certbot renew --dry-run
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ Subdomain Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
printf "🌐 Access:       https://$FULL_DOMAIN\n"
echo "📍 Config:       /etc/nginx/sites-available/$SUBDOMAIN"
echo "📁 Root Dir:     /var/www/$SUBDOMAIN/public_html"
echo ""
ok "Done!"
