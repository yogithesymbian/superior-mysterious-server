#!/bin/bash
#
# Enhanced Bash script for creating subdomain with Nginx config and SSL setup
# Uses Gum for beautiful interactive prompts (requires gum to be installed)
# Usage: sudo ./setup_subdomain_gum.sh              (production)
#        ./setup_subdomain_gum.sh --dry-run         (debug/preview mode)
#
# Install gum:
#   macOS: brew install gum
#   Ubuntu/Debian: sudo apt install gum

# Check if gum is installed
if ! command -v gum &> /dev/null; then
  echo "❌ Gum is not installed!"
  echo ""
  echo "Install it with:"
  echo "   macOS: brew install gum"
  echo "   Ubuntu/Debian: sudo apt install gum"
  echo ""
  exit 1
fi

# Colors for output
ok() { printf '\e[32m✓ %s\e[m\n' "$1"; }
info() { printf '\e[36mℹ %s\e[m\n' "$1"; }
warn() { printf '\e[33m⚠ %s\e[m\n' "$1"; }
die() { printf '\e[1;31m✗ %s\e[m\n' "$1"; exit 1; }

# Loading spinner
show_spinner() {
  local pid=$1
  local delay=0.1
  local spinner=( '⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏' )
  while kill -0 $pid 2>/dev/null; do
    for i in "${spinner[@]}"; do
      echo -ne "\r  $i $2"
      sleep $delay
    done
  done
  wait $pid
}

# Parse arguments
DRY_RUN=false
if [[ "$1" == "--dry-run" ]]; then
  DRY_RUN=true
fi

# Variables
NGINX_AVAILABLE='/etc/nginx/sites-available'
NGINX_ENABLED='/etc/nginx/sites-enabled'
WEB_DIR='/var/www'
YEAR=$(date +%Y)

# Sanity check (skip root check in dry-run mode)
if [ "$DRY_RUN" = false ]; then
  [ $(id -g) != "0" ] && die "Script must be running as root. Use: sudo $0"
fi

# ============================================
# SECTION 1: Get User Input (with Gum!)
# ============================================
echo ""
if [ "$DRY_RUN" = true ]; then
  gum style --foreground 39 --bold "🧪 DEBUG MODE (Dry-Run)"
else
  gum style --foreground 39 --bold "✨ Smart Subdomain Setup"
fi
echo ""

# Get main domain
MAIN_DOMAIN=$(gum input --placeholder "Main domain (e.g., yogiveloper.com)" --prompt "📝 ")
[[ -z "$MAIN_DOMAIN" ]] && die "Main domain cannot be empty"

# Get subdomain
SUBDOMAIN=$(gum input --placeholder "Subdomain name (e.g., api, apps, foo)" --prompt "📝 ")
[[ -z "$SUBDOMAIN" ]] && die "Subdomain cannot be empty"

FULL_DOMAIN="$SUBDOMAIN.$MAIN_DOMAIN"

# Get service type
SERVICE_CHOICE=$(gum choose \
  "🎨 Frontend (Static HTML/CSS/JS files)" \
  "🔄 Reverse Proxy Backend (Node.js/Express/Go/Rust/etc)")

case "$SERVICE_CHOICE" in
  *Frontend*)
    SERVICE="frontend"
    ;;
  *Reverse*)
    SERVICE="proxy"
    PORT=$(gum input --placeholder "3000" --prompt "🔌 Backend Port (default 3000): " --value "3000")
    ;;
  *)
    die "Invalid option"
    ;;
esac

# Confirm SSL setup
if gum confirm "🔒 Setup SSL with certbot now?"; then
  SETUP_SSL="y"
else
  SETUP_SSL="n"
fi

# ============================================
# SECTION 2: Validate & Show Summary
# ============================================
echo ""
gum style --foreground 39 --bold "📋 Setup Summary"
echo ""
echo "Domain:       $FULL_DOMAIN"
echo "Root Dir:     $WEB_DIR/$SUBDOMAIN"
echo "Service Type: $SERVICE"
[ "$SERVICE" = "proxy" ] && echo "Backend Port: $PORT"
echo "SSL Setup:    $([ "$SETUP_SSL" = "y" ] && echo "Yes" || echo "No")"
echo ""

if gum confirm "✓ Proceed with setup?"; then
  true
else
  die "Setup cancelled"
fi

# ============================================
# SECTION 2.5: Check Nginx Status
# ============================================
if [ "$DRY_RUN" = false ]; then
  ok "Checking Nginx status..."
  
  if ! systemctl is-active --quiet nginx; then
    warn "Nginx is not running"
    if gum confirm "Would you like to start Nginx now?"; then
      ok "Starting Nginx..."
      sudo systemctl start nginx
      
      if [ $? -ne 0 ]; then
        die "Failed to start Nginx. Please check your Nginx configuration and try again manually."
      fi
      
      ok "Nginx started successfully!"
    else
      die "Nginx must be running to proceed. Please start Nginx manually and run this script again."
    fi
  else
    ok "Nginx is running"
  fi
fi

# ============================================
# SECTION 3: Create Directories
# ============================================
if [ "$DRY_RUN" = true ]; then
  ok "Creating directories... [DRY-RUN]"
  info "Would create: $WEB_DIR/$SUBDOMAIN/{public_html,logs}"
else
  ok "Creating directories..."
  mkdir -p $WEB_DIR/$SUBDOMAIN/{public_html,logs}
fi

# ============================================
# SECTION 4: Generate Nginx Config
# ============================================
if [ "$DRY_RUN" = true ]; then
  ok "Generating Nginx configuration... [DRY-RUN]"
  info "Would create: $NGINX_AVAILABLE/$SUBDOMAIN"
else
  ok "Generating Nginx configuration..."
fi

if [ "$SERVICE" = "frontend" ]; then
  if [ "$DRY_RUN" = false ]; then
    cat > $NGINX_AVAILABLE/$SUBDOMAIN <<EOF
server {
    server_name $FULL_DOMAIN www.$FULL_DOMAIN;
    root $WEB_DIR/$SUBDOMAIN/public_html;

    # Security Headers
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    # Logs
    access_log $WEB_DIR/$SUBDOMAIN/logs/access.log;
    error_log $WEB_DIR/$SUBDOMAIN/logs/error.log;

    index index.html index.htm;
    charset utf-8;

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
  fi

elif [ "$SERVICE" = "proxy" ]; then
  if [ "$DRY_RUN" = false ]; then
    cat > $NGINX_AVAILABLE/$SUBDOMAIN <<EOF
server {
    server_name $FULL_DOMAIN www.$FULL_DOMAIN;
    root $WEB_DIR/$SUBDOMAIN/public_html;

    # API Headers - CORS enabled
    add_header Access-Control-Allow-Origin *;
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";

    # Logs
    access_log $WEB_DIR/$SUBDOMAIN/logs/access.log;
    error_log $WEB_DIR/$SUBDOMAIN/logs/error.log;

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt { access_log off; log_not_found off; }

    # Proxy to backend service
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

fi

# ============================================
# SECTION 5: Create Welcome Page
# ============================================
if [ "$DRY_RUN" = true ]; then
  ok "Creating welcome page... [DRY-RUN]"
  info "Would create: $WEB_DIR/$SUBDOMAIN/public_html/index.html"
else
  ok "Creating welcome page..."
  cat > $WEB_DIR/$SUBDOMAIN/public_html/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <title>Subdomain $FULL_DOMAIN</title>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1" />
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; margin: 0; padding: 20px; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; }
        .container { max-width: 600px; margin: 50px auto; text-align: center; }
        h1 { margin: 0; font-size: 2em; }
        .badge { display: inline-block; background: rgba(255,255,255,0.2); padding: 5px 10px; border-radius: 4px; margin: 10px 0; font-size: 0.9em; }
        footer { margin-top: 30px; opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 $FULL_DOMAIN</h1>
        <div class="badge">Service: $SERVICE</div>
        <p>Subdomain is active and ready!</p>
        <footer>© $YEAR</footer>
    </div>
</body>
</html>
EOF
fi

# ============================================
# SECTION 6: Set Permissions
# ============================================
if [ "$DRY_RUN" = true ]; then
  ok "Setting permissions... [DRY-RUN]"
  info "Would set: $WEB_DIR/$SUBDOMAIN (owner: www-data)"
else
  ok "Setting permissions..."
  WEB_USER=${SUDO_USER:-www-data}
  chown -R $WEB_USER:$WEB_USER $WEB_DIR/$SUBDOMAIN
  chmod 755 $WEB_DIR/$SUBDOMAIN
fi

# ============================================
# SECTION 7: Enable Site
# ============================================
if [ "$DRY_RUN" = true ]; then
  ok "Enabling site... [DRY-RUN]"
  info "Would create symlink: $NGINX_ENABLED/$SUBDOMAIN"
  info "Would test Nginx config"
  info "Would reload Nginx"
else
  ok "Enabling site..."
  if [ ! -L $NGINX_ENABLED/$SUBDOMAIN ]; then
    ln -s $NGINX_AVAILABLE/$SUBDOMAIN $NGINX_ENABLED/$SUBDOMAIN
  fi

  # Test Nginx config
  if ! nginx -t &>/dev/null; then
    die "Nginx config test failed! Rollback and check manually."
  fi

  ok "Reloading Nginx..."
  systemctl reload nginx
fi

# ============================================
# SECTION 8: SSL Setup (Optional)
# ============================================
if [[ "$SETUP_SSL" == "y" || "$SETUP_SSL" == "Y" ]]; then
  echo ""
  if [ "$DRY_RUN" = true ]; then
    ok "Setting up SSL... [DRY-RUN]"
    info "Would run certbot for: $FULL_DOMAIN"
  else
    # Check if certbot is installed
    if ! command -v certbot &> /dev/null; then
      warn "Certbot is not installed"
      if gum confirm "Would you like to install certbot now?"; then
        ok "Installing certbot and python3-certbot-nginx..."
        if [ "$DRY_RUN" = false ]; then
          sudo apt install -y certbot python3-certbot-nginx
          if [ $? -ne 0 ]; then
            die "Certbot installation failed!"
          fi
          ok "Certbot installed successfully!"
        fi
      else
        warn "Skipping SSL setup - certbot not installed"
        SETUP_SSL="n"
      fi
    fi
    
    # Run certbot if it's available
    if [[ "$SETUP_SSL" == "y" || "$SETUP_SSL" == "Y" ]]; then
      ok "Setting up SSL..."
      if command -v certbot &> /dev/null; then
        certbot --nginx -d $FULL_DOMAIN -d www.$FULL_DOMAIN --non-interactive --agree-tos --email admin@$MAIN_DOMAIN
        
        if [ $? -eq 0 ]; then
          ok "SSL setup completed!"
          ok "Testing renewal..."
          certbot renew --dry-run
        else
          warn "SSL setup had issues, check certbot logs"
        fi
      fi
    fi
  fi
fi

# ============================================
# SECTION 9: Summary & Next Steps
# ============================================
echo ""
gum style --foreground 40 --bold "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$DRY_RUN" = true ]; then
  gum style --foreground 39 --bold "  🧪 Preview Complete (Dry-Run)"
else
  gum style --foreground 40 --bold "  ✓ Setup Complete!"
fi
gum style --foreground 40 --bold "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📍 Config File:   $NGINX_AVAILABLE/$SUBDOMAIN"
echo "📁 Root Directory: $WEB_DIR/$SUBDOMAIN"
echo ""

# Make URL clickable with OSC 8 protocol (works in modern terminals)
printf "🌐 Access:       \033]8;;https://$FULL_DOMAIN\033\\https://$FULL_DOMAIN\033]8;;\033\\\n"

echo ""
gum style --foreground 35 --bold "📚 Next Steps:"
[ "$SERVICE" = "frontend" ] && echo "  → Upload your HTML/CSS/JS files to $WEB_DIR/$SUBDOMAIN/public_html"
[ "$SERVICE" = "proxy" ] && echo "  → Deploy your backend app to port $PORT"
[ "$SERVICE" = "proxy" ] && echo "  → Make sure your backend service is running on 127.0.0.1:$PORT"

echo ""
gum style --foreground 35 --bold "🧪 Quick Test Commands:"
printf "  → \033[1mcurl -I https://$FULL_DOMAIN\033[0m\n"
printf "  → \033[1mcurl -v https://$FULL_DOMAIN\033[0m\n"
[ "$SERVICE" = "proxy" ] && printf "  → \033[1mcurl -I http://127.0.0.1:$PORT\033[0m\n"

echo ""

if [ "$DRY_RUN" = true ]; then
  echo "🚀 Ready to deploy? Run:"
  echo "   sudo ./setup_subdomain_gum.sh"
  echo ""
fi

ok "Done!"
