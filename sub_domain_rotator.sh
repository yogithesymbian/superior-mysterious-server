#!/bin/bash

# List Subdomain
subdomains=(presiden.yogiarifwidodo.com directur.yogiarifwidodo.com bravo.yogiarifwidodo.com)

# Loop rotasi
for sub in "${subdomains[@]}"; do
    echo "Testing $sub ..."
    response=$(curl -s --max-time 5 --head https://$sub | head -n 1)

    if echo "$response" | grep -q "200\|301\|302"; then
        echo "✅ Available: $sub"
        echo "$sub" > active_subdomain.txt
        break
    else
        echo "❌ Down or Blocked: $sub"
    fi
done
