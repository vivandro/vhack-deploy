#!/usr/bin/env bash
set -euo pipefail

# server-setup.sh — One-time server bootstrap for vhack-deploy
# Run this on the Lightsail instance: bash server-setup.sh

DEPLOY_DIR="/opt/vhack-deploy"
DOMAIN="vhackpad.com"
SERVER_BASE="/var/www"

echo "═══ vhack-deploy server setup ═══"
echo ""

# ─── 1. Install vhack-deploy ─────────────────────────────────────────────────

echo "▸ Installing vhack-deploy to ${DEPLOY_DIR}..."
if [[ -d "${DEPLOY_DIR}" ]]; then
    echo "  Already exists, updating..."
    cd "${DEPLOY_DIR}"
    git pull origin main 2>/dev/null || echo "  (not a git repo, skipping pull)"
else
    git clone https://github.com/vivandro/vhack-deploy.git "${DEPLOY_DIR}"
fi

chmod +x "${DEPLOY_DIR}/bin/"*

# Create registry if it doesn't exist
if [[ ! -f "${DEPLOY_DIR}/registry.json" ]]; then
    echo '{"sites": {}}' > "${DEPLOY_DIR}/registry.json"
fi

# ─── 2. Wildcard SSL cert ────────────────────────────────────────────────────

echo ""
echo "▸ Checking wildcard SSL cert..."
if [[ -d "/etc/letsencrypt/live/${DOMAIN}" ]]; then
    echo "  Wildcard cert already exists."
else
    echo "  Obtaining wildcard cert for *.${DOMAIN}..."
    echo "  This requires a DNS challenge. Choose your method:"
    echo ""
    echo "  Option A — Route 53 (automatic, needs AWS credentials):"
    echo "    pip3 install certbot-dns-route53"
    echo "    certbot certonly --dns-route53 -d '*.${DOMAIN}' -d '${DOMAIN}' --cert-name ${DOMAIN}"
    echo ""
    echo "  Option B — Manual DNS challenge:"
    echo "    certbot certonly --manual --preferred-challenges dns -d '*.${DOMAIN}' -d '${DOMAIN}' --cert-name ${DOMAIN}"
    echo ""
    read -rp "  Run Route 53 method now? (y/n) " choice
    if [[ "$choice" == "y" ]]; then
        pip3 install certbot-dns-route53
        certbot certonly --dns-route53 -d "*.${DOMAIN}" -d "${DOMAIN}" --cert-name "${DOMAIN}"
    else
        echo "  Skipping — run certbot manually before deploying."
    fi
fi

# ─── 3. Tune nginx for 100 sites ─────────────────────────────────────────────

echo ""
echo "▸ Tuning nginx..."
NGINX_CONF="/etc/nginx/nginx.conf"

# server_names_hash_bucket_size
if ! grep -q "server_names_hash_bucket_size" "${NGINX_CONF}"; then
    sed -i '/http {/a\    server_names_hash_bucket_size 128;' "${NGINX_CONF}"
    echo "  Added server_names_hash_bucket_size 128"
fi

# SSL session cache
if ! grep -q "ssl_session_cache" "${NGINX_CONF}"; then
    sed -i '/http {/a\    ssl_session_cache shared:SSL:10m;\n    ssl_session_timeout 10m;' "${NGINX_CONF}"
    echo "  Added SSL session cache"
fi

# Gzip
if ! grep -q "gzip on" "${NGINX_CONF}"; then
    sed -i '/http {/a\    gzip on;\n    gzip_types text/plain text/css application/json application/javascript text/xml application/xml image/svg+xml;\n    gzip_min_length 1000;' "${NGINX_CONF}"
    echo "  Added gzip compression"
fi

nginx -t && systemctl reload nginx
echo "  Nginx reloaded."

# ─── 4. Migrate existing sites ───────────────────────────────────────────────

echo ""
echo "▸ Migrating existing sites to release-based structure..."

migrate_site() {
    local site="$1"
    local type="$2"
    local port="${3:-}"
    local site_dir="${SERVER_BASE}/${site}"

    if [[ -L "${site_dir}/current" ]]; then
        echo "  ${site}: already migrated"
        return
    fi

    if [[ ! -d "${site_dir}" ]]; then
        echo "  ${site}: directory not found, skipping"
        return
    fi

    echo "  ${site}: migrating..."
    local release="migrated_$(date +%Y%m%d_%H%M%S)"
    local release_dir="${site_dir}/releases/${release}"

    mkdir -p "${site_dir}/releases" "${site_dir}/shared"

    # Move current files into a release directory
    mkdir -p "${release_dir}"
    # Move everything except releases/ and shared/ into the release
    find "${site_dir}" -maxdepth 1 -not -name releases -not -name shared -not -name "$(basename "${site_dir}")" -exec mv {} "${release_dir}/" \;

    # Create current symlink
    ln -sfn "${release_dir}" "${site_dir}/current"

    # Update nginx config to use wildcard cert and current symlink
    local nginx_conf="/etc/nginx/sites-available/${site}"
    if [[ -f "${nginx_conf}" ]]; then
        # Update root to use current symlink (for static sites)
        if [[ "$type" != "docker" ]]; then
            sed -i "s|root ${site_dir};|root ${site_dir}/current;|g" "${nginx_conf}"
            sed -i "s|root ${site_dir}/;|root ${site_dir}/current;|g" "${nginx_conf}"
        fi
        # Update SSL cert paths to wildcard
        sed -i "s|/etc/letsencrypt/live/[^/]*/fullchain.pem|/etc/letsencrypt/live/${DOMAIN}/fullchain.pem|g" "${nginx_conf}"
        sed -i "s|/etc/letsencrypt/live/[^/]*/privkey.pem|/etc/letsencrypt/live/${DOMAIN}/privkey.pem|g" "${nginx_conf}"
    fi

    # Register in registry
    ${DEPLOY_DIR}/bin/update-registry.py add "${site}" "${type}" "${port}"

    echo "  ${site}: done"
}

# Migrate the 4 existing sites
migrate_site "vhackpad" "static"
migrate_site "python-prep" "static"
migrate_site "maple-syrup" "flutter"
migrate_site "hackpad" "docker" "3001"

nginx -t && systemctl reload nginx

# ─── 5. Log rotation ─────────────────────────────────────────────────────────

echo ""
echo "▸ Setting up log rotation..."
cat > /etc/logrotate.d/vhackpad-sites <<'LOGROTATE'
/var/log/nginx/*.access.log
/var/log/nginx/*.error.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        [ -f /var/run/nginx.pid ] && kill -USR1 $(cat /var/run/nginx.pid)
    endscript
}
LOGROTATE
echo "  Log rotation configured (14 days, compressed)."

# ─── 6. Disk monitoring cron ─────────────────────────────────────────────────

echo ""
echo "▸ Setting up disk monitoring..."
cat > /opt/vhack-deploy/bin/check-disk.sh <<'DISKCHECK'
#!/usr/bin/env bash
USAGE=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
if [[ "$USAGE" -gt 80 ]]; then
    echo "WARNING: Disk usage at ${USAGE}% on $(hostname)" | \
        mail -s "vhackpad.com disk warning" root 2>/dev/null || \
        logger "vhack-deploy: disk usage at ${USAGE}%"
fi

# Auto-prune docker
if command -v docker &>/dev/null; then
    docker image prune -f --filter "until=72h" >/dev/null 2>&1
fi
DISKCHECK
chmod +x /opt/vhack-deploy/bin/check-disk.sh

# Add cron job if not already present
(crontab -l 2>/dev/null | grep -v check-disk; echo "0 */6 * * * /opt/vhack-deploy/bin/check-disk.sh") | crontab -
echo "  Disk check runs every 6 hours."

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "═══ Setup complete ═══"
echo ""
echo "Next steps:"
echo "  1. Obtain wildcard SSL cert if not done above"
echo "  2. Verify: vhack-deploy list"
echo "  3. Test: vhack-deploy init test-site && echo '<h1>hello</h1>' > /tmp/test/index.html && cd /tmp/test && vhack-deploy push test-site"
