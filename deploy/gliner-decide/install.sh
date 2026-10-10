#!/usr/bin/env bash
# One-shot installer for the GLiNER2.5-Decide API on a fresh Ubuntu/Debian VPS (e.g. Hostinger KVM).
#
#   curl -fsSL https://raw.githubusercontent.com/pirazor/ML-agents/refs/heads/claude/peaceful-gauss-cexx9v/deploy/gliner-decide/install.sh | sudo bash
#
# Optional settings (pass as env vars, e.g. `... | sudo DOMAIN=api.example.com bash`):
#   DOMAIN   hostname whose DNS A record points at this server. Default: <ip>.sslip.io (works with no domain).
#   API_KEY  key clients must send. Default: random, generated once and kept across re-runs.
# Re-running the script updates the code and keeps the existing key and domain.
set -euo pipefail

REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/pirazor/ML-agents/refs/heads/claude/peaceful-gauss-cexx9v/deploy/gliner-decide}"
INSTALL_DIR="${INSTALL_DIR:-/opt/gliner-decide}"
FILES="app.py requirements.txt Dockerfile docker-compose.yml Caddyfile"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31mError: %s\033[0m\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root (prefix with sudo)"

total_mem_kb=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
if [ "$total_mem_kb" -lt 3500000 ]; then
  die "this server has $((total_mem_kb / 1024)) MB RAM; the model needs at least 4 GB (Hostinger KVM 1 or larger)"
fi

if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker"
  curl -fsSL https://get.docker.com | sh
fi
docker compose version >/dev/null 2>&1 || die "docker compose plugin missing; install docker-compose-plugin"
systemctl enable --now docker >/dev/null 2>&1 || true

log "Downloading app files to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
for f in $FILES; do
  curl -fsSL "$REPO_RAW/$f" -o "$f.tmp" || die "could not download $f from $REPO_RAW"
  mv "$f.tmp" "$f"
done

# Keep settings from a previous run unless overridden on the command line
want_domain="${DOMAIN:-}"
want_key="${API_KEY:-}"
if [ -f .env ]; then
  # shellcheck source=/dev/null
  . ./.env
fi
DOMAIN="${want_domain:-${DOMAIN:-}}"
API_KEY="${want_key:-${API_KEY:-}}"

if [ -z "${DOMAIN:-}" ]; then
  ip=$(curl -4fsS https://api.ipify.org || curl -4fsS https://ifconfig.me) || die "could not detect public IP; set DOMAIN"
  DOMAIN="${ip//./-}.sslip.io"
fi
API_KEY="${API_KEY:-$(openssl rand -hex 24)}"

umask 077
printf 'DOMAIN=%s\nAPI_KEY=%s\n' "$DOMAIN" "$API_KEY" > .env
umask 022

if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
  log "Opening ports 80 and 443 in ufw"
  ufw allow 80/tcp >/dev/null
  ufw allow 443/tcp >/dev/null
fi

log "Building and starting (first build downloads ~2.5 GB, allow 5-10 minutes)"
docker compose up -d --build

log "Waiting for the model to load"
for _ in $(seq 1 90); do
  if curl -fsS "https://$DOMAIN/" >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 5
done
[ "${ready:-0}" = 1 ] || die "API not reachable at https://$DOMAIN/ yet. Check: cd $INSTALL_DIR && docker compose logs --tail 50
  Also check that ports 80/443 are open in the Hostinger firewall (hPanel > VPS > Security > Firewall)."

cat <<EOF

========================================================================
 GLiNER2.5-Decide API is live

   URL:      https://$DOMAIN
   API key:  $API_KEY        (also saved in $INSTALL_DIR/.env)
   Docs:     https://$DOMAIN/docs

 Test it:
   curl -X POST https://$DOMAIN/classify \\
     -H "x-api-key: $API_KEY" -H "content-type: application/json" \\
     -d '{"text": "Can I get a refund for last month?", "tasks": {"intent": ["refund_request", "cancel_subscription", "other"]}}'
========================================================================
EOF
