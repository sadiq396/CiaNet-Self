#!/usr/bin/env bash
# CiaNet Self v1.0 — Nginx + Let's Encrypt for DuckDNS/Amazon EC2
set -Eeuo pipefail
umask 077
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
fail(){ echo -e "${RED}✗ $*${NC}" >&2; exit 1; }
ok(){ echo -e "${GREEN}✓ $*${NC}"; }
[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "با root اجرا کن: sudo bash install_panel.sh"
ENV_FILE="/etc/cianet.env"
[[ -f "$ENV_FILE" ]] || fail "ابتدا نصب اصلی را اجرا کن: sudo bash install.sh"
DOMAIN="${1:-cianet-self.duckdns.org}"
[[ "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]] || fail "دامنه نامعتبر است."

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx certbot python3-certbot-nginx curl dnsutils

mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
cat > /etc/nginx/sites-available/cianet-self <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    client_max_body_size 25m;

    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 120s;
    }
}
EOF
ln -sfn /etc/nginx/sites-available/cianet-self /etc/nginx/sites-enabled/cianet-self
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx
systemctl reload nginx

DNS_IP="$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}')"
PUBLIC_IP="$(curl -fsS --max-time 8 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]' || true)"
echo "دامنه: $DOMAIN"
echo "IP ثبت‌شده در DNS: ${DNS_IP:-پیدا نشد}"
echo "IP عمومی این سرور: ${PUBLIC_IP:-قابل تشخیص نیست}"
if [[ -z "$DNS_IP" || -z "$PUBLIC_IP" || "$DNS_IP" != "$PUBLIC_IP" ]]; then
  echo -e "${YELLOW}⚠ دامنه هنوز به IP عمومی این سرور اشاره نمی‌کند؛ رکورد DuckDNS را اصلاح کن و دوباره اجرا کن.${NC}"
  echo "پیکربندی HTTP ساخته شد؛ دریافت SSL تا اصلاح DNS انجام نمی‌شود."
  exit 0
fi

read -r -p "ایمیل برای تمدید/هشدار گواهی Let's Encrypt: " CERT_EMAIL
[[ "$CERT_EMAIL" == *@*.* ]] || fail "ایمیل معتبر وارد کن."
if certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --redirect -m "$CERT_EMAIL"; then
  ok "HTTPS با موفقیت فعال شد."
else
  echo -e "${YELLOW}⚠ دریافت گواهی SSL انجام نشد. DNS و ورودی پورت 80 در AWS را بررسی کن و دوباره اجرا کن.${NC}"
  exit 1
fi

# Keep panel's public origin and secure-cookie policy in sync with the HTTPS domain.
if grep -q '^PANEL_URL=' "$ENV_FILE"; then
  sed -i "s|^PANEL_URL=.*|PANEL_URL=https://$DOMAIN|" "$ENV_FILE"
else
  echo "PANEL_URL=https://$DOMAIN" >> "$ENV_FILE"
fi
if grep -q '^PANEL_CORS_ORIGINS=' "$ENV_FILE"; then
  sed -i "s|^PANEL_CORS_ORIGINS=.*|PANEL_CORS_ORIGINS=https://$DOMAIN,http://localhost:8000|" "$ENV_FILE"
else
  echo "PANEL_CORS_ORIGINS=https://$DOMAIN,http://localhost:8000" >> "$ENV_FILE"
fi
if grep -q '^PANEL_COOKIE_SECURE=' "$ENV_FILE"; then
  sed -i 's/^PANEL_COOKIE_SECURE=.*/PANEL_COOKIE_SECURE=1/' "$ENV_FILE"
else
  echo 'PANEL_COOKIE_SECURE=1' >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
systemctl restart selfbot cianet-panel
ok "پنل در https://$DOMAIN/app/login.html و پنل کاربر در https://$DOMAIN/u/login.html در دسترس است."
