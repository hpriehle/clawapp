#!/usr/bin/env bash
# Show TalkClaw connection QR code for scanning with a new device.
# Run from anywhere: ~/talkclaw/scripts/qr.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# ── Find API token ──────────────────────────────────────────────────────────

token=""

if [[ -f "$REPO_DIR/.env" ]]; then
    token=$(grep '^API_TOKEN=' "$REPO_DIR/.env" 2>/dev/null | cut -d= -f2- || true)
fi

if [[ -z "$token" ]]; then
    token=$(docker compose -f "$REPO_DIR/docker-compose.yml" exec -T talkclaw cat /data/.talkclaw-token 2>/dev/null || true)
fi

if [[ -z "$token" ]]; then
    echo -e "${RED}[✗]${NC} Could not find API token. Is the server running?" >&2
    echo "  Check: cd $REPO_DIR && docker compose logs talkclaw"
    exit 1
fi

# ── Find server URL ────────────────────────────────────────────────────────

server=""

# Cloudflare tunnel
if [[ -f "$HOME/.cloudflared/config.yml" ]]; then
    hostname=$(grep 'hostname:' "$HOME/.cloudflared/config.yml" 2>/dev/null | head -1 | awk '{print $NF}' || true)
    if [[ -n "$hostname" ]]; then
        server="https://$hostname"
    fi
fi

# Tailscale
if [[ -z "$server" ]] && command -v tailscale &>/dev/null; then
    ts_ip=$(tailscale ip -4 2>/dev/null || true)
    if [[ -n "$ts_ip" ]]; then
        server="http://${ts_ip}:8080"
    fi
fi

# Local IP
if [[ -z "$server" ]]; then
    case "$(uname -s)" in
        Darwin) ip=$(ipconfig getifaddr en0 2>/dev/null || echo "localhost") ;;
        Linux)  ip=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost") ;;
        *)      ip="localhost" ;;
    esac
    server="http://${ip}:8080"
fi

# ── Print QR ───────────────────────────────────────────────────────────────

echo ""
echo -e "${BOLD}TalkClaw Connection${NC}"
echo ""
echo -e "  ${GREEN}Server:${NC}  $server"
echo -e "  ${GREEN}Token:${NC}   $token"

config_b64=$(echo -n "{\"server\":\"${server}\",\"token\":\"${token}\"}" | base64 | tr -d '\n')
setup_url="talkclaw://setup?config=${config_b64}"

echo ""
echo -e "${BOLD}Scan with TalkClaw app:${NC}"
echo ""

if command -v qrencode &>/dev/null; then
    qrencode -t ANSIUTF8 -m 2 "$setup_url"
else
    echo "  Install qrencode for QR display: brew install qrencode / apt install qrencode"
    echo ""
    echo "  Setup URL: $setup_url"
fi
echo ""
