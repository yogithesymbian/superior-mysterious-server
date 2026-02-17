#! /bin/bash
# 1. SWAP 2GB (Biar makin tenang)
if [ ! -f /swapfile ]; then
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# 2. CORE TOOLS
apt-get update
apt-get install -y nginx curl git certbot python3-certbot-nginx

# 3. NODE & PM2
if ! command -v node &> /dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi
npm install -g pm2
