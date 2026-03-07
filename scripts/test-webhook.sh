#!/bin/bash
#
# Send a test message to the TalkClaw iOS app.
#
# Usage:
#   API_TOKEN=clw_xxx ./scripts/test-webhook.sh [session_id]
#
# If no session_id is given, lists sessions and uses the most recent one.
# The message appears in the iOS app as an assistant message (no AI triggered).
#
# Environment variables:
#   TALKCLAW_URL  - Server base URL (default: http://localhost:8080)
#   API_TOKEN     - TalkClaw API token (required)

set -euo pipefail

URL="${TALKCLAW_URL:-http://localhost:8080}"
API="$URL/api/v1"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

log()   { echo -e "${GREEN}[+]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
fail()  { echo -e "${RED}[x]${NC} $1"; exit 1; }

# --- Preflight ---

if [ -z "${API_TOKEN:-}" ]; then
    fail "API_TOKEN is required. Export it or pass inline: API_TOKEN=clw_xxx $0"
fi

# Health check
log "Checking server health at $URL..."
HEALTH=$(curl -sf "$API/health" 2>/dev/null) || fail "Server not reachable at $URL"
echo "    $HEALTH"

# --- Resolve session ID ---

SESSION_ID="${1:-}"

if [ -z "$SESSION_ID" ]; then
    log "Listing sessions..."
    SESSIONS=$(curl -sf "$API/sessions" \
        -H "Authorization: Bearer $API_TOKEN" 2>/dev/null) \
        || fail "Failed to list sessions. Check API_TOKEN."

    SESSION_ID=$(echo "$SESSIONS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
items = data if isinstance(data, list) else data.get('items', data.get('sessions', []))
if not items:
    sys.exit(1)
print(items[0]['id'])
" 2>/dev/null) || fail "No sessions found. Create one in the iOS app first."

    log "Using most recent session: $SESSION_ID"
fi

# --- Send test message ---

TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
TEXT="Test message at $TIMESTAMP"

log "Sending assistant message to session $SESSION_ID..."
log "  text: $TEXT"

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$API/sessions/$SESSION_ID/messages" \
    -H "Authorization: Bearer $API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
        \"content\": \"$TEXT\",
        \"role\": \"assistant\"
    }")

if [ "$HTTP_CODE" = "200" ]; then
    log "Message delivered (HTTP $HTTP_CODE)"
    echo ""
    log "Check the iOS app - the message should appear in the chat."
elif [ "$HTTP_CODE" = "401" ]; then
    fail "Authentication failed (HTTP 401). Check API_TOKEN."
elif [ "$HTTP_CODE" = "400" ]; then
    fail "Bad request (HTTP 400). Session $SESSION_ID may not exist."
else
    fail "Unexpected response: HTTP $HTTP_CODE"
fi
