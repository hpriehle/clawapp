#!/usr/bin/env bash
set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[✗]${NC} $1" >&2; }
ask()  { echo -en "${BLUE}[?]${NC} $1"; }

TALKCLAW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── OS Detection ────────────────────────────────────────────────────────────

detect_os() {
    case "$(uname -s)" in
        Darwin)  OS="macos" ;;
        Linux)   OS="linux" ;;
        MINGW*|MSYS*|CYGWIN*)  OS="windows" ;;
        *)       OS="unknown" ;;
    esac
    log "OS: $(uname -s) ($(uname -m))"
}

get_local_ip() {
    case "$OS" in
        macos)   ipconfig getifaddr en0 2>/dev/null || echo "localhost" ;;
        linux)   hostname -I 2>/dev/null | awk '{print $1}' || echo "localhost" ;;
        *)       echo "localhost" ;;
    esac
}

# ── Step 1: Prerequisites ──────────────────────────────────────────────────

install_docker() {
    if command -v docker &>/dev/null; then
        log "Docker already installed: $(docker --version | head -1)"
        return
    fi

    case "$OS" in
        macos)
            err "Docker is not installed."
            echo "  Install Docker Desktop from: https://www.docker.com/products/docker-desktop/"
            echo "  Then re-run this script."
            exit 1
            ;;
        linux)
            log "Installing Docker..."
            if command -v apt-get &>/dev/null; then
                sudo apt-get update -qq
                sudo apt-get install -y -qq docker.io docker-compose-plugin >/dev/null 2>&1
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y docker docker-compose-plugin >/dev/null 2>&1
                sudo systemctl start docker
                sudo systemctl enable docker
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm docker docker-compose >/dev/null 2>&1
                sudo systemctl start docker
                sudo systemctl enable docker
            else
                err "Could not detect package manager. Install Docker manually:"
                echo "  https://docs.docker.com/engine/install/"
                exit 1
            fi
            sudo usermod -aG docker "$USER" 2>/dev/null || true
            warn "Added $USER to docker group. You may need to log out and back in."
            log "Docker installed"
            ;;
        windows)
            err "Docker is not installed."
            echo "  Install Docker Desktop from: https://www.docker.com/products/docker-desktop/"
            echo "  Make sure WSL 2 backend is enabled."
            echo "  Then re-run this script from WSL."
            exit 1
            ;;
        *)
            err "Install Docker manually: https://docs.docker.com/engine/install/"
            exit 1
            ;;
    esac
}

check_ports() {
    local port_in_use=0
    case "$OS" in
        macos)
            if lsof -iTCP:8080 -sTCP:LISTEN >/dev/null 2>&1; then port_in_use=1; fi
            ;;
        *)
            if ss -tlnp 2>/dev/null | grep -q ":8080 "; then port_in_use=1; fi
            ;;
    esac

    if [[ $port_in_use -eq 1 ]]; then
        warn "Port 8080 is already in use"
        ask "Continue anyway? (y/N) "
        read -r reply
        [[ "$reply" =~ ^[Yy] ]] || exit 1
    fi
}

# ── Step 2: OpenClaw Connection Details ──────────────────────────────────

ask_openclaw_details() {
    echo ""
    echo -e "${BOLD}OpenClaw Gateway Connection${NC}"
    echo "TalkClaw connects to your existing OpenClaw gateway."
    echo "You need the gateway URL and auth token from your OpenClaw setup."
    echo ""

    # Gateway URL
    ask "OpenClaw gateway URL [http://localhost:18789]: "
    read -r OPENCLAW_URL
    if [[ -z "$OPENCLAW_URL" ]]; then
        OPENCLAW_URL="http://localhost:18789"
    fi

    # Gateway token
    echo ""
    echo "Your gateway token is in ~/.openclaw/openclaw.json under gateway.auth.token"
    ask "OpenClaw gateway auth token: "
    read -r GATEWAY_TOKEN

    if [[ -z "$GATEWAY_TOKEN" ]]; then
        err "Gateway token is required."
        exit 1
    fi

    # Quick connectivity check
    echo ""
    log "OpenClaw URL: $OPENCLAW_URL"
    log "Gateway token: ${GATEWAY_TOKEN:0:12}..."

    if curl -sf --max-time 5 "$OPENCLAW_URL" >/dev/null 2>&1; then
        log "OpenClaw gateway is reachable"
    else
        warn "Could not reach $OPENCLAW_URL — TalkClaw will retry on startup"
    fi
}

# ── Step 3: TalkClaw Server ───────────────────────────────────────────────

deploy_talkclaw() {
    cd "$TALKCLAW_DIR"

    # Check for required files
    if [[ ! -f "Dockerfile" || ! -d "TalkClawServer" ]]; then
        err "Missing Dockerfile or TalkClawServer directory."
        err "Run this script from the talkclaw repository root."
        exit 1
    fi

    # Determine OpenClaw URL for Docker container
    # If pointing to localhost, rewrite to host.docker.internal so the container can reach it
    DOCKER_OPENCLAW_URL="$OPENCLAW_URL"
    if [[ "$OPENCLAW_URL" == *"localhost"* || "$OPENCLAW_URL" == *"127.0.0.1"* ]]; then
        DOCKER_OPENCLAW_URL=$(echo "$OPENCLAW_URL" | sed 's/localhost/host.docker.internal/; s/127\.0\.0\.1/host.docker.internal/')
        log "Rewriting localhost → host.docker.internal for Docker networking"
    fi

    # Generate docker-compose.yml
    cat > docker-compose.yml << DCEOF
services:
  talkclaw:
    build: .
    ports:
      - "8080:8080"
    extra_hosts:
      - "host.docker.internal:host-gateway"
    environment:
      - DATABASE_URL=postgres://talkclaw:talkclaw@db:5432/talkclaw
      - OPENCLAW_URL=${DOCKER_OPENCLAW_URL}
      - OPENCLAW_TOKEN=${GATEWAY_TOKEN}
      - DATA_DIR=/data
    volumes:
      - app_data:/data
    depends_on:
      db:
        condition: service_healthy
    restart: unless-stopped

  db:
    image: postgres:16-alpine
    environment:
      - POSTGRES_DB=talkclaw
      - POSTGRES_USER=talkclaw
      - POSTGRES_PASSWORD=talkclaw
    volumes:
      - pg_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U talkclaw"]
      interval: 5s
      timeout: 5s
      retries: 5

volumes:
  pg_data:
  app_data:
DCEOF

    log "docker-compose.yml generated"

    # Build and start
    echo ""
    log "Building TalkClaw server (this takes ~8 minutes on first run)..."
    docker compose up -d --build 2>&1 | tail -5

    # Wait for server to be healthy
    log "Waiting for server to start..."
    local retries=30
    while [[ $retries -gt 0 ]]; do
        if curl -sf http://localhost:8080/api/v1/health >/dev/null 2>&1; then
            log "TalkClaw server is running"
            break
        fi
        sleep 2
        retries=$((retries - 1))
    done

    if [[ $retries -eq 0 ]]; then
        err "Server did not start. Check: docker compose logs talkclaw"
        exit 1
    fi

    # Extract API token from logs (compatible with macOS grep — no -P flag)
    API_TOKEN=$(docker compose logs talkclaw 2>&1 | grep -o 'clw_[a-f0-9]*' | head -1)
    if [[ -z "$API_TOKEN" ]]; then
        # Try reading from the volume
        API_TOKEN=$(docker compose exec talkclaw cat /data/.talkclaw-token 2>/dev/null || echo "")
    fi

    if [[ -z "$API_TOKEN" ]]; then
        warn "Could not extract API token. Check: docker compose logs talkclaw"
    else
        log "API token: ${API_TOKEN:0:20}..."
    fi
}

# ── Step 4: Cloudflare Tunnel ─────────────────────────────────────────────

setup_tunnel() {
    echo ""
    echo -e "${BOLD}Public URL Setup${NC}"
    echo "To access TalkClaw from anywhere, you can set up a Cloudflare Tunnel."
    echo "This gives you a public HTTPS URL (e.g., talkclaw.yourdomain.com)."
    echo ""
    ask "Set up a Cloudflare Tunnel? (y/N) "
    read -r reply

    if [[ ! "$reply" =~ ^[Yy] ]]; then
        LOCAL_IP=$(get_local_ip)
        SERVER_URL="http://${LOCAL_IP}:8080"
        warn "Skipping tunnel. Server available at $SERVER_URL (local network only)."
        echo "  For remote access, consider Tailscale: https://tailscale.com"
        return
    fi

    # Install cloudflared if needed
    if ! command -v cloudflared &>/dev/null; then
        case "$OS" in
            macos)
                if command -v brew &>/dev/null; then
                    log "Installing cloudflared via Homebrew..."
                    brew install cloudflared >/dev/null 2>&1
                else
                    err "Install cloudflared manually: brew install cloudflared"
                    err "Or download from: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
                    exit 1
                fi
                ;;
            linux)
                log "Installing cloudflared..."
                if [[ "$(uname -m)" == "x86_64" ]]; then
                    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb -o /tmp/cloudflared.deb
                else
                    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64.deb -o /tmp/cloudflared.deb
                fi
                sudo dpkg -i /tmp/cloudflared.deb >/dev/null 2>&1
                rm /tmp/cloudflared.deb
                ;;
            *)
                err "Install cloudflared manually: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/downloads/"
                exit 1
                ;;
        esac
        log "cloudflared installed"
    else
        log "cloudflared already installed"
    fi

    # Login to Cloudflare (opens browser)
    if [[ ! -f "$HOME/.cloudflared/cert.pem" ]]; then
        echo ""
        echo "A browser window will open to authenticate with Cloudflare."
        echo "If you're on a headless server, copy the URL and open it on any device."
        echo ""
        cloudflared tunnel login
    fi

    # Create tunnel
    TUNNEL_NAME="talkclaw-$(hostname -s)"
    if cloudflared tunnel list 2>/dev/null | grep -q "$TUNNEL_NAME"; then
        log "Tunnel '$TUNNEL_NAME' already exists"
        TUNNEL_ID=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    else
        log "Creating tunnel '$TUNNEL_NAME'..."
        cloudflared tunnel create "$TUNNEL_NAME"
        TUNNEL_ID=$(cloudflared tunnel list 2>/dev/null | grep "$TUNNEL_NAME" | awk '{print $1}')
    fi

    # Get domain from user
    echo ""
    ask "Enter the hostname for your server (e.g., talkclaw.yourdomain.com): "
    read -r TALKCLAW_HOSTNAME

    if [[ -z "$TALKCLAW_HOSTNAME" ]]; then
        warn "No hostname provided. Skipping DNS routing."
        LOCAL_IP=$(get_local_ip)
        SERVER_URL="http://${LOCAL_IP}:8080"
        return
    fi

    # Route DNS
    cloudflared tunnel route dns "$TUNNEL_NAME" "$TALKCLAW_HOSTNAME" 2>/dev/null || \
        cloudflared tunnel route dns -f "$TUNNEL_NAME" "$TALKCLAW_HOSTNAME" 2>/dev/null || true
    log "DNS routed: $TALKCLAW_HOSTNAME -> tunnel"

    SERVER_URL="https://$TALKCLAW_HOSTNAME"

    # Find credentials file
    CREDS_FILE=$(find "$HOME/.cloudflared" -name "${TUNNEL_ID}.json" 2>/dev/null | head -1)
    if [[ -z "$CREDS_FILE" ]]; then
        CREDS_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"
    fi

    # Generate cloudflared config and start as service
    case "$OS" in
        linux)
            sudo mkdir -p /etc/cloudflared
            sudo tee /etc/cloudflared/config.yml > /dev/null << CFEOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CREDS_FILE}

ingress:
  - hostname: ${TALKCLAW_HOSTNAME}
    service: http://localhost:8080
  - service: http_status:404
CFEOF
            if [[ -f "$CREDS_FILE" ]]; then
                sudo cp "$CREDS_FILE" /etc/cloudflared/ 2>/dev/null || true
            fi
            sudo cloudflared service install 2>/dev/null || true
            sudo systemctl enable cloudflared 2>/dev/null || true
            sudo systemctl restart cloudflared 2>/dev/null || true
            ;;
        macos)
            mkdir -p "$HOME/.cloudflared"
            cat > "$HOME/.cloudflared/config.yml" << CFEOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CREDS_FILE}

ingress:
  - hostname: ${TALKCLAW_HOSTNAME}
    service: http://localhost:8080
  - service: http_status:404
CFEOF
            cloudflared service install 2>/dev/null || true
            ;;
        *)
            warn "Automatic service setup not supported on this OS."
            warn "Run manually: cloudflared tunnel run $TUNNEL_NAME"
            ;;
    esac

    log "Cloudflare Tunnel running: $SERVER_URL"
}

# ── Step 5: Install OpenClaw Skill ────────────────────────────────────────

install_openclaw_skill() {
    echo ""
    echo -e "${BOLD}OpenClaw Agent Knowledge${NC}"
    echo "TalkClaw includes a skill file that teaches your OpenClaw agent about the app"
    echo "— what it can do, how messages arrive, and what the user sees on their phone."
    echo ""

    # Find the OpenClaw workspace
    local openclaw_workspace=""

    # Check common locations
    if [[ -f "$HOME/.openclaw/openclaw.json" ]]; then
        # Try to read workspace from config
        local config_workspace
        config_workspace=$(grep -o '"workspace"[[:space:]]*:[[:space:]]*"[^"]*"' "$HOME/.openclaw/openclaw.json" 2>/dev/null | head -1 | sed 's/.*"workspace"[[:space:]]*:[[:space:]]*"//; s/"//')
        if [[ -n "$config_workspace" && -d "$config_workspace" ]]; then
            openclaw_workspace="$config_workspace"
        fi
    fi

    # If not found from config, look for AGENTS.md in common places
    if [[ -z "$openclaw_workspace" ]]; then
        for dir in "$HOME/openclaw" "$HOME/dev/openclaw" "$HOME/.openclaw/workspace"; do
            if [[ -f "$dir/AGENTS.md" ]]; then
                openclaw_workspace="$dir"
                break
            fi
        done
    fi

    if [[ -z "$openclaw_workspace" ]]; then
        ask "Where is your OpenClaw workspace? (folder with AGENTS.md): "
        read -r openclaw_workspace
    fi

    if [[ -z "$openclaw_workspace" || ! -d "$openclaw_workspace" ]]; then
        warn "Could not find OpenClaw workspace. Skipping skill install."
        echo "  You can manually copy openclaw-skill/ to your workspace's skills/talkclaw/ later."
        return
    fi

    # Verify it's actually an OpenClaw workspace
    if [[ ! -f "$openclaw_workspace/AGENTS.md" ]]; then
        warn "$openclaw_workspace doesn't look like an OpenClaw workspace (no AGENTS.md)."
        ask "Install anyway? (y/N) "
        read -r reply
        [[ "$reply" =~ ^[Yy] ]] || return
    fi

    # Copy skill files
    local skill_src="$TALKCLAW_DIR/openclaw-skill"
    local skill_dest="$openclaw_workspace/skills/talkclaw"

    if [[ ! -d "$skill_src" ]]; then
        warn "Skill files not found at $skill_src. Skipping."
        return
    fi

    mkdir -p "$skill_dest"
    cp "$skill_src/SKILL.md" "$skill_dest/SKILL.md"
    cp "$skill_src/_meta.json" "$skill_dest/_meta.json"
    log "Installed TalkClaw skill to $skill_dest"

    # Append TalkClaw connection details to TOOLS.md
    local tools_file="$openclaw_workspace/TOOLS.md"
    local server="${SERVER_URL:-http://localhost:8080}"

    # Remove any existing TalkClaw section from TOOLS.md
    if [[ -f "$tools_file" ]] && grep -q "## TalkClaw Server" "$tools_file"; then
        # Remove old section (from ## TalkClaw Server to next ## or end of file)
        sed -i.bak '/^## TalkClaw Server/,/^## [^C]/{/^## [^C]/!d;}' "$tools_file" 2>/dev/null || \
            sed -i '' '/^## TalkClaw Server/,/^## [^C]/{/^## [^C]/!d;}' "$tools_file" 2>/dev/null || true
        # Clean up: remove the header if it's now empty
        sed -i.bak '/^## TalkClaw Server$/d' "$tools_file" 2>/dev/null || \
            sed -i '' '/^## TalkClaw Server$/d' "$tools_file" 2>/dev/null || true
        rm -f "${tools_file}.bak"
    fi

    cat >> "$tools_file" << TOOLSEOF

## TalkClaw Server

- **Server URL:** ${server}
- **API Port:** 8080
- **OpenClaw URL:** ${OPENCLAW_URL}
- **Session key format:** \`talkclaw-{sessionUUID}\`
- **Auth:** Bearer token (\`clw_\` prefix), stored in Docker volume
- See \`skills/talkclaw/SKILL.md\` for full app capability reference.
TOOLSEOF

    log "Updated $tools_file with TalkClaw connection details"
}

# ── Step 6: Print Connection Details + QR Code ───────────────────────────

install_qrencode() {
    if command -v qrencode &>/dev/null; then return 0; fi

    case "$OS" in
        macos)
            if command -v brew &>/dev/null; then
                brew install qrencode >/dev/null 2>&1 && return 0
            fi
            ;;
        linux)
            if command -v apt-get &>/dev/null; then
                sudo apt-get install -y -qq qrencode >/dev/null 2>&1 && return 0
            elif command -v dnf &>/dev/null; then
                sudo dnf install -y qrencode >/dev/null 2>&1 && return 0
            elif command -v pacman &>/dev/null; then
                sudo pacman -S --noconfirm qrencode >/dev/null 2>&1 && return 0
            fi
            ;;
    esac
    return 1
}

print_connection_details() {
    local server="${SERVER_URL:-http://localhost:8080}"
    local token="${API_TOKEN:-}"

    echo ""
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║             TalkClaw Setup Complete!                     ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}║${NC}                                                          ${BOLD}║${NC}"
    echo -e "${BOLD}║${NC}  ${GREEN}Server URL:${NC}  ${server}"
    echo -e "${BOLD}║${NC}  ${GREEN}API Token:${NC}   ${token:-check docker compose logs talkclaw}"
    echo -e "${BOLD}║${NC}                                                          ${BOLD}║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"

    # Generate QR code for instant app setup
    if [[ -n "$token" ]]; then
        local config_json="{\"server\":\"${server}\",\"token\":\"${token}\"}"
        local config_b64
        config_b64=$(echo -n "$config_json" | base64 | tr -d '\n')
        local setup_url="https://talk-claw.ai/setup?config=${config_b64}"

        echo ""
        echo -e "${BOLD}Scan this QR code with TalkClaw to connect instantly:${NC}"
        echo ""

        if install_qrencode; then
            qrencode -t ANSIUTF8 -m 2 "$setup_url"
        else
            warn "Install qrencode to display QR code: brew install qrencode (macOS) or apt install qrencode (Linux)"
            echo ""
            echo "  Or open this URL on your phone:"
            echo "  $setup_url"
        fi

        echo ""
        echo "  Setup URL: $setup_url"
    fi

    echo ""
    echo "Useful commands:"
    echo "  docker compose logs talkclaw  # View server logs"
    echo "  docker compose restart       # Restart server"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}TalkClaw Self-Hosted Setup${NC}"
    echo "Connect your TalkClaw iOS app to your OpenClaw gateway."
    echo ""

    # Initialize variables
    API_TOKEN=""
    SERVER_URL=""
    GATEWAY_TOKEN=""
    OPENCLAW_URL=""

    detect_os
    ask_openclaw_details
    install_docker
    check_ports
    deploy_talkclaw
    setup_tunnel
    install_openclaw_skill
    print_connection_details
}

main "$@"
