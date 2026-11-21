#!/usr/bin/env bash
# CiaNet Self v1.0 — local ZIP installer for Amazon EC2 / Ubuntu / Debian
set -Eeuo pipefail
umask 077

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info(){ echo -e "${BLUE}▶ $*${NC}"; }
ok(){ echo -e "${GREEN}✓ $*${NC}"; }
warn(){ echo -e "${YELLOW}⚠ $*${NC}"; }
fail(){ echo -e "${RED}✗ $*${NC}" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "با root اجرا کن: sudo bash install.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/main.py" && -f "$SCRIPT_DIR/web_panel.py" ]] || fail "این اسکریپت باید از ریشه پروژه اجرا شود؛ main.py و web_panel.py پیدا نشدند."
[[ -f "$SCRIPT_DIR/BRAND.json" ]] || fail "فایل هویت برند BRAND.json پیدا نشد؛ بسته معتبر CiaNet Self نیست."
grep -q '"brand_id": "cianet-self"' "$SCRIPT_DIR/BRAND.json" || fail "شناسه برند بسته معتبر نیست."
grep -q '"product": "CiaNet Self"' "$SCRIPT_DIR/BRAND.json" || fail "نام محصول در BRAND.json معتبر نیست."

if [[ -r /etc/os-release ]]; then . /etc/os-release; else fail "تشخیص سیستم‌عامل ممکن نشد."; fi
case "${ID:-}" in ubuntu|debian) ;; *) fail "این نصب‌کننده برای Ubuntu و Debian ساخته شده است. روی ${PRETTY_NAME:-سیستم ناشناخته} اجرا نکن.";; esac

INSTALL_DIR="/opt/cianet"
SERVICE_USER="cianet"
ENV_FILE="/etc/cianet.env"

info "نصب وابستگی‌های سیستم..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv python3-pip python3-dev build-essential rsync git sqlite3 curl nginx ca-certificates

# GitHub updates are enabled only for the exact remote of the CiaNet Self clone
# from which this installer is being run. ZIP installs intentionally have no Git remote.
SOURCE_GIT_REMOTE=""
if git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  SOURCE_GIT_REMOTE="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null || true)"
fi

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi
mkdir -p "$INSTALL_DIR" /var/backups

# Keep runtime state and secrets outside source overlays. Back up existing code before replacing it.
if [[ -n "$(find "$INSTALL_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  BACKUP="/var/backups/cianet-self-code-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$BACKUP" --exclude='./.venv' --exclude='./sessions' --exclude='./data' \
    --exclude='./downloads' --exclude='./tracker_media' --exclude='./dedicated_bots' \
    --exclude='./*.db' --exclude='./*.session' -C "$INSTALL_DIR" . || fail "گرفتن پشتیبان کد فعلی شکست خورد؛ نصب متوقف شد."
  ok "پشتیبان کد قبلی: $BACKUP"
fi

info "کپی فایل‌های نسخه CiaNet Self 𝒗₁.₀..."
rsync -a \
  --exclude='.venv/' --exclude='venv/' --exclude='__pycache__/' \
  --exclude='*.pyc' --exclude='.env' --exclude='.env.*' --exclude='cianet.env' \
  --exclude='config.json' --exclude='config.json.bak' --exclude='sessions/' \
  --exclude='sessions_*/' --exclude='data/' --exclude='downloads/' \
  --exclude='tracker_media/' --exclude='dedicated_bots/' --exclude='*.db' \
  --exclude='*.session' --exclude='*.log' \
  "$SCRIPT_DIR/" "$INSTALL_DIR/"

# Never leave a stale Git remote behind after a ZIP-based installation.
if [[ -z "$SOURCE_GIT_REMOTE" ]]; then
  rm -rf "$INSTALL_DIR/.git"
fi

mkdir -p "$INSTALL_DIR/sessions" "$INSTALL_DIR/data" "$INSTALL_DIR/downloads" \
  "$INSTALL_DIR/tracker_media" "$INSTALL_DIR/dedicated_bots" "$INSTALL_DIR/versions"
if [[ ! -f "$INSTALL_DIR/config.json" ]]; then printf '{}\n' > "$INSTALL_DIR/config.json"; fi
chmod 600 "$INSTALL_DIR/config.json"
chmod 700 "$INSTALL_DIR/sessions" "$INSTALL_DIR/data" "$INSTALL_DIR/downloads" "$INSTALL_DIR/tracker_media" "$INSTALL_DIR/dedicated_bots"

info "ساخت محیط Python و نصب نیازمندی‌ها..."
if [[ ! -x "$INSTALL_DIR/.venv/bin/python" ]]; then python3 -m venv "$INSTALL_DIR/.venv"; fi
"$INSTALL_DIR/.venv/bin/python" -m pip install --upgrade pip
"$INSTALL_DIR/.venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"
"$INSTALL_DIR/.venv/bin/python" -m compileall -q "$INSTALL_DIR/main.py" "$INSTALL_DIR/web_panel.py" "$INSTALL_DIR/cianet" "$INSTALL_DIR/cianet_updater.py" || fail "بررسی syntax پایتون شکست خورد؛ سرویس‌ها ساخته نشدند."

if [[ ! -f "$ENV_FILE" ]]; then
  info "تنظیم اعتبارنامه‌ها (مقادیر واردشده در فایل خصوصی سرور ذخیره می‌شوند)."
  API_ID="${API_ID:-}"; API_HASH="${API_HASH:-}"; ADMIN_BOT_TOKEN="${ADMIN_BOT_TOKEN:-}"
  HELPER_BOT_TOKEN="${HELPER_BOT_TOKEN:-}"; ADMIN_ID="${ADMIN_ID:-52382185319}"
  SUPPORT_CONTACT="${CIANET_SUPPORT_CONTACT:-sadiq_AFG1}"
  [[ -n "$API_ID" ]] || read -r -p "Telegram API ID: " API_ID
  [[ -n "$API_HASH" ]] || { read -r -s -p "Telegram API Hash: " API_HASH; echo; }
  [[ -n "$ADMIN_BOT_TOKEN" ]] || { read -r -s -p "توکن ربات اصلی (BotFather): " ADMIN_BOT_TOKEN; echo; }
  [[ -n "$HELPER_BOT_TOKEN" ]] || { read -r -s -p "توکن ربات پشتیبانی (Enter برای خالی): " HELPER_BOT_TOKEN; echo; }
  [[ -n "$ADMIN_ID" ]] || read -r -p "Telegram numeric Admin ID: " ADMIN_ID
  [[ "$API_ID" =~ ^[0-9]+$ ]] || fail "API ID باید عددی باشد."
  [[ "$ADMIN_ID" =~ ^[0-9]+$ ]] || fail "Admin ID باید عددی باشد."
  [[ -n "$API_HASH" && -n "$ADMIN_BOT_TOKEN" ]] || fail "API Hash و توکن ربات اصلی الزامی هستند."

  PANEL_ADMIN_USER="${PANEL_ADMIN_USER:-Admin}"
  PANEL_ADMIN_PASS="${PANEL_ADMIN_PASS:-}"
  if [[ -z "$PANEL_ADMIN_PASS" ]]; then
    read -r -s -p "رمز اولیه پنل [پیش‌فرض Admin]: " PANEL_ADMIN_PASS; echo
    PANEL_ADMIN_PASS="${PANEL_ADMIN_PASS:-Admin}"
  fi
  [[ ${#PANEL_ADMIN_PASS} -ge 8 ]] || warn "رمز پنل کمتر از ۸ کاراکتر است؛ مقدار Admin فقط برای راه‌اندازی اولیه مناسب نیست و باید بلافاصله تعویض شود."

  PANEL_HASH="$(PANEL_PASS_ENV="$PANEL_ADMIN_PASS" "$INSTALL_DIR/.venv/bin/python" - <<'PY'
import os
from passlib.hash import bcrypt
print(bcrypt.hash(os.environ["PANEL_PASS_ENV"]))
PY
)" || fail "ساخت هش امن رمز پنل شکست خورد."
  SESSION_SECRET="$("$INSTALL_DIR/.venv/bin/python" -c 'import secrets; print(secrets.token_urlsafe(48))')"
  cat > "$ENV_FILE" <<EOF
# CiaNet Self v1.0 — private server environment; do not put this file in ZIP/Git.
API_ID=$API_ID
API_HASH=$API_HASH
ADMIN_BOT_TOKEN=$ADMIN_BOT_TOKEN
HELPER_BOT_TOKEN=$HELPER_BOT_TOKEN
HELPER_BOT_USERNAME=CiaNet_Self_Support_bot
ADMIN_ID=$ADMIN_ID
CIANET_CHANNEL=CiaNet_Self
CIANET_SUPPORT_CONTACT=$SUPPORT_CONTACT
PANEL_ADMIN_USER=$PANEL_ADMIN_USER
PANEL_ADMIN_PASS_HASH=$PANEL_HASH
PANEL_SESSION_SECRET=$SESSION_SECRET
PANEL_URL=https://cianet-self.duckdns.org
PANEL_CORS_ORIGINS=https://cianet-self.duckdns.org,http://localhost:8000
PANEL_COOKIE_SECURE=1
PANEL_DOCS_ENABLED=0
CIANET_AUTO_UPDATE=0
CIANET_UPDATE_REMOTE=$SOURCE_GIT_REMOTE
CIANET_BRANCH=main
CIANET_INSTALL_DIR=/opt/cianet
CIANET_SERVICE_NAME=selfbot
CIANET_PANEL_SERVICE_NAME=cianet-panel
CIANET_EMBED_PANEL=0
EOF
  chmod 600 "$ENV_FILE"
  chown "$SERVICE_USER:$SERVICE_USER" "$ENV_FILE"
  ok "اعتبارنامه‌ها در $ENV_FILE با دسترسی 600 ذخیره شدند."
else
  warn "$ENV_FILE از قبل وجود دارد؛ اعتبارنامه‌ها و رمز پنل حفظ می‌شوند."
  ENV_FILE="$ENV_FILE" SOURCE_GIT_REMOTE="$SOURCE_GIT_REMOTE" python3 - <<'PYENV'
import os
from pathlib import Path
p = Path(os.environ["ENV_FILE"])
remote = os.environ.get("SOURCE_GIT_REMOTE", "").strip()
lines = p.read_text(encoding="utf-8").splitlines()
values = {
    "CIANET_UPDATE_REMOTE": remote,
    "CIANET_AUTO_UPDATE": "0",
    "CIANET_BRANCH": "main",
    "CIANET_CHANNEL": "CiaNet_Self",
    "CIANET_SUPPORT_CONTACT": "sadiq_AFG1",
}
seen = set()
out = []
for line in lines:
    if "=" in line:
        key = line.split("=", 1)[0]
        if key in values:
            out.append(f"{key}={values[key]}")
            seen.add(key)
            continue
    out.append(line)
for key, value in values.items():
    if key not in seen:
        out.append(f"{key}={value}")
p.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
PYENV
  chmod 600 "$ENV_FILE"
fi

chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"
chmod 600 "$INSTALL_DIR/config.json"
find "$INSTALL_DIR/sessions" -type f -name '*.session*' -exec chmod 600 {} \; 2>/dev/null || true

info "ساخت سرویس‌های systemd..."
cat > /etc/systemd/system/selfbot.service <<EOF
[Unit]
Description=CiaNet Self Telegram Service
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=300
StartLimitBurst=10

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=HOME=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$INSTALL_DIR/.venv/bin/python -u main.py all
Restart=always
RestartSec=10
# sudo is intentionally available only for the exact service actions in
# /etc/sudoers.d/cianet-self (restart/start/stop selfbot and cianet-panel).
NoNewPrivileges=false
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR /var/log /tmp /run/sudo
UMask=0077
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cianet-self

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/cianet-panel.service <<EOF
[Unit]
Description=CiaNet Self Web Panel
After=network-online.target selfbot.service
Wants=network-online.target

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=HOME=$INSTALL_DIR
EnvironmentFile=$ENV_FILE
ExecStart=$INSTALL_DIR/.venv/bin/python -m uvicorn web_panel:app --host 127.0.0.1 --port 8000 --workers 1
Restart=always
RestartSec=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$INSTALL_DIR /var/log /tmp
UMask=0077
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
SyslogIdentifier=cianet-self-panel

[Install]
WantedBy=multi-user.target
EOF

SYSTEMCTL_BIN="$(command -v systemctl)"
printf '%s ALL=(root) NOPASSWD: %s restart selfbot, %s start selfbot, %s stop selfbot, %s restart cianet-panel, %s start cianet-panel, %s stop cianet-panel\n' \
  "$SERVICE_USER" "$SYSTEMCTL_BIN" "$SYSTEMCTL_BIN" "$SYSTEMCTL_BIN" "$SYSTEMCTL_BIN" "$SYSTEMCTL_BIN" "$SYSTEMCTL_BIN" \
  > /etc/sudoers.d/cianet-self
chmod 440 /etc/sudoers.d/cianet-self
visudo -cf /etc/sudoers.d/cianet-self >/dev/null || fail "فایل sudoers معتبر نیست."

systemctl daemon-reload
systemctl enable selfbot cianet-panel
systemctl restart selfbot cianet-panel || true
sleep 3

ok "فایل‌های CiaNet Self روی سرور در $INSTALL_DIR قرار گرفتند."
echo
echo "وضعیت ربات: $(systemctl is-active selfbot 2>/dev/null || true)"
echo "وضعیت پنل:  $(systemctl is-active cianet-panel 2>/dev/null || true)"
echo "پنل داخلی:  http://127.0.0.1:8000/app/login.html"
echo "دامنه هدف:  https://cianet-self.duckdns.org/app/login.html"
echo
echo "برای اتصال عمومی دامنه و SSL اجرا کن: sudo bash install_panel.sh"
echo "در AWS Security Group فقط پورت‌های 22 (محدود به IP خودت)، 80 و 443 را باز کن؛ 8000 عمومی نشود."
echo "لاگ‌ها: sudo journalctl -u selfbot -f  |  sudo journalctl -u cianet-panel -f"
echo
echo "رمز پیش‌فرض در صورت خالی گذاشتن ورودی: Admin — پیش از استفاده عمومی تغییرش بده."
