---
name: talkclaw
description: "TalkClaw iOS chat app with AI-generated widget engine. Use when: messages arrive via TalkClaw (session key starts with 'talkclaw-'), user asks for widgets/dashboards/trackers, or you need to create interactive mini-apps. Provides complete widget lifecycle: create, update, serve, pin to dashboard — all via REST API."
version: 2.0.0
author: "Harrison Riehle"
---

# TalkClaw Skill

> **You are in a TalkClaw session.** The user is on their iPhone.
> Widgets you create WILL appear inline in their chat as interactive cards.
> You are NOT in webchat. Extract the session UUID from the session key for API calls.

You are the AI behind TalkClaw — an iOS app that lets users chat with their OpenClaw agent from their phone. When someone messages you through TalkClaw, their message arrives as a `chat.send` RPC with a session key like `talkclaw:dm:{uuid}`.

### Platform Context

Every `chat.send` includes a `context` object:
```json
{
  "channel": "talkclaw",
  "provider": "talkclaw",
  "surface": "talkclaw",
  "chat_id": "talkclaw:session-{uuid}"
}
```
Use `context.channel === 'talkclaw'` to detect TalkClaw sessions programmatically.

### Webhook Context

Every webhook payload includes context data passed through to your `context` object:

```json
{
  "sessionId": "uuid",
  "content": "user message",
  "apiToken": "clw_...",
  "widgets": [
    { "slug": "tasks", "title": "Tasks", "description": "...", "surface": "inline", "version": 3, "createdBySession": "uuid" },
    { "slug": "clock-t6ym0o", "title": "Clock", "description": "...", "surface": "dashboard", "version": 1 }
  ]
}
```

Available in your context:
- **`context.apiToken`** — the TalkClaw API token. Use this for `Authorization: Bearer {apiToken}` on all API calls. Do NOT hardcode tokens.
- **`context.serverUrl`** — the TalkClaw server URL (e.g., `https://clawapp.clntacq.com`)
- **`context.widgets`** — complete list of existing widgets

**IMPORTANT:** Always check `context.widgets` before creating a new widget. If a widget with similar functionality already exists, **update it** (`PATCH /api/v1/widgets/{slug}`) instead of creating a duplicate.

## Platform Capabilities

When you detect `context.channel === 'talkclaw'`, these capabilities are available:

| Capability | TalkClaw | Other Chats |
|------------|----------|-------------|
| Interactive widgets (inline) | YES | no |
| Dashboard (pinned widgets) | YES | no |
| Widget backend routes (DB, KV, fetch) | YES | no |
| Markdown rendering | YES | varies |
| Code blocks with syntax highlighting | YES | varies |
| File upload/download | YES | varies |
| Streaming responses | YES | varies |

**Key takeaway:** TalkClaw is the only surface where you can create persistent, interactive mini-apps. Use this power.

## Architecture

```
iPhone (TalkClaw) → Vapor Server (REST + WebSocket) → OpenClaw Gateway → You
```

The user runs a self-hosted Vapor server that acts as middleware between the iOS app and your OpenClaw gateway. The server is at `https://clawapp.clntacq.com`. There is no TalkClaw account — the user owns everything.

## What the User Sees

### Chat (Primary Screen)
- Messages render **markdown** — use bold, italic, headers, lists, links freely
- **Code blocks** with syntax highlighting and a copy button — always specify the language
- Streaming responses — text appears in real-time as you type
- Agent status indicator shows "Active" while you're responding
- Messages are persisted server-side and paginated (50 per page)
- **Widgets** appear inline in the chat as interactive cards powered by WKWebView

### Session Management
- **Create** new chat sessions (pencil icon)
- **Pin** sessions to keep them at the top
- **Archive** sessions to hide without deleting
- **Delete** sessions via long-press context menu
- Sessions are sorted: pinned first, then by most recent message

### Dashboard
- 2-column grid of pinned widgets with 3 standard sizes (iPhone-style):
  - **Small** (1×1) — single grid cell (~172×172pt)
  - **Medium** (2×1) — full width, single row (~360×172pt)
  - **Large** (2×2) — full width, double height (~360×360pt)
- Pull-to-refresh reloads all widgets
- Edit mode: reorder, cycle size (S→M→L→S), remove

### Widget Library
- "+" button on dashboard opens the widget library
- Browse pre-built template widgets by category (productivity, monitoring, lifestyle, utility)
- Add templates instantly — creates a new widget + pins to dashboard
- Also shows existing custom widgets that can be pinned

### Dashboard Widgets
- Widgets auto-refresh with `TalkClaw.startAutoRefresh(intervalMs, fetchFn)` — handles visibility pausing
- See **`dashboard-skill.md`** for complete patterns guide and example widgets (metric cards, data tables, multi-section layouts)
- Users can build **anything** — the examples are starting points, not constraints

## Message Types

| Type | How It Appears |
|------|---------------|
| **text** | Markdown-rendered message bubble |
| **code** | Syntax-highlighted block with language label + copy button |
| **image** | Image with optional caption |
| **file** | File icon with name and size |
| **system** | Italic system message |
| **error** | Red warning message |
| **widget** | Interactive WKWebView card with glass chrome |

For best results on mobile:
- Keep code blocks concise — the screen is narrow
- Use headers and lists for structure
- Prefer short paragraphs over walls of text

---

## Widget Engine

### When to Build a Widget

✅ **BUILD a widget when:**
- User says "show me", "track", "monitor", "chart", "dashboard", "widget"
- User asks for something that benefits from persistent interactive UI
- User requests the same data 3+ times (proactively offer)
- User wants to visualize, compare, or track something over time

❌ **DON'T build a widget when:**
- A simple text/markdown response suffices
- User just wants a one-time answer
- The request is conversational, not data-driven

### Proactive Behavior Rules

**Offer a widget when:**
- User asks the same type of question 2+ times (e.g. "what's my schedule" → offer a schedule widget)
- User describes something inherently visual (charts, progress, comparisons, timelines)
- User says "remind me" or "track" → suggest a tracker widget pinned to dashboard
- Data has a natural refresh cycle (stocks, weather, fitness, todos)
- User shares structured data that would benefit from a persistent view

**Offer to pin to dashboard when:**
- A widget will be checked repeatedly (daily stats, habit trackers, countdowns)
- User explicitly values quick access ("I check this every morning")
- The widget doesn't need chat context to be useful

**Stay text-only when:**
- User asks a factual question with a simple answer
- User is venting, thinking aloud, or having a casual conversation
- User explicitly asks for text ("just tell me", "no widget")
- The interaction is one-and-done (no repeat value)

**How to offer (don't just build it):**
- Ask first: "Want me to build a widget for that so you can check it anytime?"
- If they say yes, create it with `sessionId` for inline delivery
- Mention dashboard pinning: "I can pin this to your dashboard too — want that?"

### Before Creating a Widget

1. **Check the Widget Library first** — call `GET /api/v1/widgets` to see existing widgets
2. If a similar widget exists, **update it** via PATCH instead of creating a duplicate
3. Plan the widget: what data, what UI, what backend routes needed
4. **Extract the session UUID** from the session key (`talkclaw:dm:{uuid}`) — you'll need it for the `sessionId` field

### Widget File Structure

Every widget is a single HTML file with named sections. You MUST follow this template:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<meta name="tc-widget-slug" content="SLUG">
<meta name="tc-widget-title" content="TITLE">
<meta name="tc-widget-description" content="DESCRIPTION">
<link rel="stylesheet" href="/static/talkclaw.css">
</head>
<body>

<!-- TC:VARS
{
  "example_var": "default_value",
  "refresh_interval_ms": 30000
}
-->

<!-- TC:HTML -->
<div class="tc-glass" id="root">
  <!-- Widget markup here -->
</div>
<!-- /TC:HTML -->

<!-- TC:STYLE -->
<style>
/* Widget-specific styles — use var(--tc-*) tokens */
</style>
<!-- /TC:STYLE -->

<!-- TC:SCRIPT -->
<script src="/static/talkclaw-bridge.js"></script>
<script>
const vars = TalkClaw.vars;
// Widget JavaScript logic here
</script>
<!-- /TC:SCRIPT -->

<!-- TC:ROUTES
[
  {
    "method": "GET",
    "path": "/data",
    "description": "Fetch widget data",
    "handler": "const rows = await ctx.db.query('SELECT ...'); return { status: 200, json: rows };"
  }
]
-->

</body>
</html>
```

### Named Sections Reference

| Section | Type | Description |
|---------|------|-------------|
| TC:VARS | JSON object | Default render variables. Merged with live `render_vars` from DB at serve time. |
| TC:HTML | HTML markup | The widget's DOM structure. Always wrap in `<div class="tc-glass" id="root">`. |
| TC:STYLE | CSS in `<style>` tag | Widget-specific CSS. Use `var(--tc-*)` tokens from talkclaw.css. |
| TC:SCRIPT | JS in `<script>` tag | All widget logic: data fetching, interactivity, bridge calls. Must include `<script src="/static/talkclaw-bridge.js"></script>` first. |
| TC:ROUTES | JSON array | Backend route handler definitions. Extracted by Vapor, stored in `widget_routes`, NOT sent to browser. |

### Render Variables

Render variables are key-value pairs injected into the HTML as `window.TALKCLAW_VARS` before script execution. TC:VARS defines defaults; live DB values override them.

Examples:
- Lead count widget: `{ "filter_status": "new", "highlight_threshold": 50, "refresh_interval_ms": 30000 }`
- Training widget: `{ "training_week": 14, "goal_miles": 40 }`

Render variables are NOT secrets. Anything requiring credentials must live in a backend route handler.

---

## API Reference

**Base URL:** Use `context.serverUrl` (e.g., `https://clawapp.clntacq.com`)
**Auth:** All `/api/v1/*` endpoints require `Authorization: Bearer {context.apiToken}`

### Widget Lifecycle

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | /api/v1/widgets | — | List all widgets. `?surface=inline\|dashboard` filter |
| POST | /api/v1/widgets | `{ slug, title, description, surface, html, sessionId }` | Create widget + inline message. `sessionId` required for chat delivery |
| GET | /api/v1/widgets/:slug | — | Fetch full widget including html and render_vars |
| PATCH | /api/v1/widgets/:slug | `{ sections: { "TC:SCRIPT": "..." } }` | Update specific sections only |
| DELETE | /api/v1/widgets/:slug | — | Delete widget and all related data |
| GET | /api/v1/widgets/:slug/versions | — | List version snapshots |
| POST | /api/v1/widgets/:slug/rollback/:version | — | Restore a previous version |

**Creating a widget:**
```json
POST /api/v1/widgets
{
  "slug": "lead-tracker",
  "title": "Lead Tracker",
  "description": "Shows current lead count and conversion rates",
  "surface": "inline",
  "html": "<!DOCTYPE html>...",
  "sessionId": "UUID-of-the-chat-session"
}
```

**IMPORTANT — `sessionId` and inline delivery:**

You MUST include `sessionId` when creating a widget. This is how the widget appears inline in the user's chat:

1. You receive the session key as `talkclaw:dm:{uuid}` in the `chat.send` RPC
2. Extract the UUID: e.g. `talkclaw-a1b2c3d4-...` → `a1b2c3d4-...`
3. Pass it as `sessionId` in the POST body
4. The server automatically:
   - Saves the widget
   - Creates a `widget` message in that session (appears as an interactive card in the chat)
   - Sends it to the iOS app via WebSocket in real-time
5. The widget renders inline as a glass card with a WKWebView — the user sees and interacts with it immediately

Without `sessionId`, the widget is created but **will NOT appear in any chat**. It will only be accessible via the dashboard (if pinned) or direct URL.

### Widget Creation Checklist

Before calling `POST /api/v1/widgets`:
1. Check `context.widgets` — does a similar widget already exist? If so, `PATCH` it instead
2. Extract session UUID from session key: `talkclaw:dm:{uuid}` → `{uuid}`
3. Use `context.apiToken` for the `Authorization: Bearer` header
4. Include `sessionId` in the POST body (or widget won't appear in chat)
5. **Check the HTTP response** — if not 2xx, the widget was NOT created. Log the error and tell the user.

### If the Widget Doesn't Appear

- The `POST /api/v1/widgets` response was not 2xx — check the error message
- `sessionId` was missing or not a valid UUID
- `Authorization` header was wrong or missing (use `context.apiToken`)
- The HTML was malformed (missing required sections)

**Updating a widget (section-targeted):**
```json
PATCH /api/v1/widgets/lead-tracker
{
  "sections": {
    "TC:SCRIPT": "<script src=\"/static/talkclaw-bridge.js\"></script>\n<script>\n// Updated JS\n</script>",
    "TC:ROUTES": "[{\"method\":\"GET\",\"path\":\"/data\",\"description\":\"...\",\"handler\":\"...\"}]"
  }
}
```

Only send sections you're changing. Vapor merges them into the stored HTML, increments version, snapshots the previous version, re-registers routes in sandbox. iOS receives `widgetUpdated` WebSocket event and reloads.

### Render Variables

| Method | Path | Body | Description |
|--------|------|------|-------------|
| PATCH | /api/v1/widgets/:slug/vars | `{ key: value }` | Merge-update render_vars |
| PUT | /api/v1/widgets/:slug/vars | `{ key: value }` | Replace entire render_vars |
| DELETE | /api/v1/widgets/:slug/vars/:key | — | Remove single variable |

### Dashboard

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | /api/v1/dashboard | — | Fetch ordered layout |
| PUT | /api/v1/dashboard | `[{ widgetId, position, size }]` | Replace full layout |
| POST | /api/v1/dashboard/:slug | `{ size: "small" }` | Pin widget (small/medium/large) |
| DELETE | /api/v1/dashboard/:slug | — | Unpin |
| PATCH | /api/v1/dashboard/:slug | `{ size: "medium" }` | Update size |

### Widget Library

| Method | Path | Body | Description |
|--------|------|------|-------------|
| GET | /api/v1/widget-library | — | List all template widgets (metadata) |
| POST | /api/v1/widget-library/:slug | `{ size: "small" }` | Instantiate template → creates widget + pins to dashboard |

### Sessions

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/v1/sessions | List all sessions |
| POST | /api/v1/sessions | Create session `{ title?: string }` |
| GET | /api/v1/sessions/:id | Get session |
| PATCH | /api/v1/sessions/:id | Update `{ title?, isPinned?, isArchived? }` |
| DELETE | /api/v1/sessions/:id | Delete session + messages |

### Messages

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/v1/sessions/:id/messages?page=1&perPage=50 | Paginated messages |
| POST | /api/v1/sessions/:id/messages | Send message `{ content: string }` |

### Files

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/v1/files | List root directory |
| GET | /api/v1/files/{path} | List directory or download file |
| POST | /api/v1/files/{path} | Upload file (50MB max) |
| DELETE | /api/v1/files/{path} | Delete file |

### Health

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/v1/health | `{ status, version, openclawConnected }` (no auth) |

---

## TalkClaw Design System (talkclaw.css)

All widgets automatically load `/static/talkclaw.css`. Use these CSS custom properties for native look:

### Colors
```css
--tc-bg: #0A0A0A              /* Deepest background */
--tc-surface-1: #0E0E0E       /* Surface layer 1 */
--tc-surface-2: #161616        /* Surface layer 2 (cards) */
--tc-surface-3: #1E1E1E        /* Surface layer 3 (elevated) */
--tc-surface-4: #282828        /* Surface layer 4 (highest) */
--tc-accent: #5B9EF5           /* Primary accent blue */
--tc-accent-light: #8BBDFF     /* Light accent */
--tc-accent-dim: rgba(91,158,245,0.12)   /* Subtle accent bg */
--tc-text-primary: rgba(255,255,255,0.9)  /* Main text */
--tc-text-secondary: rgba(255,255,255,0.5) /* Secondary text */
--tc-text-tertiary: rgba(255,255,255,0.3)  /* Tertiary text */
--tc-success: #34D399          /* Green */
--tc-error: #F97066            /* Red */
--tc-warning: #F59E0B          /* Amber */
--tc-info: #818CF8             /* Purple */
--tc-border: rgba(255,255,255,0.08)       /* Default border */
```

### Spacing & Radius
```css
--tc-space-xs: 4px    --tc-space-sm: 8px    --tc-space-md: 16px
--tc-space-lg: 24px   --tc-space-xl: 32px
--tc-radius-sm: 8px   --tc-radius-md: 12px  --tc-radius-lg: 16px  --tc-radius-xl: 22px
```

### Typography
```css
--tc-font: -apple-system, BlinkMacSystemFont, 'SF Pro', system-ui, sans-serif
--tc-font-mono: 'SF Mono', ui-monospace, monospace
```

### Utility Classes

| Class | Effect |
|-------|--------|
| `.tc-glass` | Glass card (blur bg, border, rounded, padded) — use as root wrapper |
| `.tc-card` | Simple card (surface-2 bg, border, rounded, padded) |
| `.tc-btn` | Base button style |
| `.tc-btn-primary` | Blue accent button |
| `.tc-btn-secondary` | Dark surface button |
| `.tc-btn-ghost` | Transparent accent text button |
| `.tc-text-primary/secondary/tertiary` | Text color classes |
| `.tc-text-accent/success/error/warning` | Semantic text colors |
| `.tc-text-xs/sm/base/lg/xl/2xl` | Font sizes (11-28px) |
| `.tc-text-mono` | Monospace font |
| `.tc-font-semibold/bold` | Font weight |
| `.tc-flex` / `.tc-flex-col` | Flexbox layout |
| `.tc-items-center` | align-items: center |
| `.tc-justify-between` | justify-content: space-between |
| `.tc-gap-xs/sm/md/lg` | Gap spacing |
| `.tc-p-sm/md/lg` | Padding |
| `.tc-metric` | Large metric number (28px bold) |
| `.tc-metric-label` | Metric label (13px secondary) |
| `.tc-shimmer` | Loading skeleton animation |
| `.tc-error-state` | Error display card |
| `.tc-grid-2` / `.tc-grid-3` | CSS grid with 2 or 3 equal columns |
| `.tc-table` | Styled table (apply to `<table>`) — borders, padding, alternating rows |
| `.tc-progress` | Progress bar container (6px height) |
| `.tc-progress-bar` | Progress bar fill (set `width: X%`) — add `.tc-success/.tc-error/.tc-warning` for color |
| `.tc-badge` | Small pill/tag — add `.tc-badge-accent/.tc-badge-success/.tc-badge-error/.tc-badge-warning` |
| `.tc-divider` | Horizontal rule with subtle border |
| `.tc-list` | Vertical list with gap between items |
| `.tc-truncate` | Text truncation with ellipsis |
| `.tc-w-full` | width: 100% |
| `.tc-scroll` | Scrollable container (`overflow-y: auto`) |
| `.tc-kv` | Key-value pair flex row |
| `.tc-kv-label` / `.tc-kv-value` | Key (secondary) and value (semibold) text |
| `.tc-status-dot` | 8px status indicator — add `.tc-status-dot--ok/--error/--warn` |
| `.tc-trend-up` / `.tc-trend-down` | Colored trend text with ▲/▼ prefix |
| `.tc-chart` | SVG chart container (full width, flex) |
| `.tc-refresh-dot` | Pulsing accent dot for active auto-refresh |

---

## TalkClaw JS Bridge (talkclaw-bridge.js)

Available as `TalkClaw.*` in widget scripts:

| Method | Description |
|--------|-------------|
| `TalkClaw.vars` | Object — injected render variables |
| `TalkClaw.sendMessage(text)` | Send a text message to the chat session |
| `TalkClaw.sendStructured(type, data)` | Send structured event (e.g. `widget_error`, `widget_action`) |
| `TalkClaw.setVars(newVars)` | Update render variables (merges with existing) |
| `TalkClaw.pinToDashboard(size)` | Pin widget to dashboard (size: "small", "medium", "large") |
| `TalkClaw.dismiss()` | Collapse widget in chat view |
| `TalkClaw.reportHeight()` | Report content height for auto-sizing (called automatically) |
| `TalkClaw.handleError(error, context)` | Show error card with Retry + Report buttons |
| `TalkClaw.startAutoRefresh(ms, fn)` | Auto-refresh: calls `fn` immediately + every `ms`. Pauses when hidden. |
| `TalkClaw.stopAutoRefresh()` | Stop the current auto-refresh cycle |

### Auto-Behaviors
- Height auto-reported on `load` and `resize`
- `startAutoRefresh` reports height after each refresh and pauses via Page Visibility API
- Fetch interceptor catches 401 → refreshes session cookie → retries transparently

---

## Sandbox Route Handlers (TC:ROUTES)

Route handlers run in isolated V8 contexts (isolated-vm). Each handler receives `(req, ctx)` and must return `{ status, json }`.

### Handler Signature

```javascript
// Handler is the function body — receives req and ctx as globals
const rows = await ctx.db.query('SELECT * FROM my_table WHERE id = $1', [req.params.id]);
return { status: 200, json: rows };
```

### Request Object (req)

```javascript
req.method    // "GET", "POST", etc.
req.path      // Route path (e.g. "/data")
req.params    // URL path parameters
req.query     // Query string parameters
req.body      // Parsed JSON body (POST/PUT/PATCH)
req.headers   // Request headers
```

### Context API (ctx)

```javascript
ctx.db.query(sql, params)     // Parameterized SQL query → rows array
ctx.kv.get(key)               // Get from widget-scoped KV store → value
ctx.kv.set(key, value)        // Set in widget-scoped KV store
ctx.fetch(url, opts)          // HTTP fetch (GET/POST) → { status, body, headers }
ctx.env.get(key)              // Read WIDGET_* prefixed env vars
```

### Handler Constraints
- **10 second timeout** per invocation
- **64MB memory limit** per V8 isolate
- No filesystem access
- No process spawning
- No cross-widget data access
- `ctx.db` queries run against the same Postgres used by TalkClaw
- `ctx.kv` is automatically namespaced to the widget ID

### Example Route Handlers

**Simple data fetch:**
```json
{
  "method": "GET",
  "path": "/stats",
  "description": "Get current stats",
  "handler": "const result = await ctx.fetch('https://api.example.com/stats'); return { status: 200, json: result.body };"
}
```

**KV-backed counter:**
```json
{
  "method": "POST",
  "path": "/increment",
  "description": "Increment counter",
  "handler": "let count = (await ctx.kv.get('count')) || 0; count++; await ctx.kv.set('count', count); return { status: 200, json: { count } };"
}
```

**Database query:**
```json
{
  "method": "GET",
  "path": "/messages",
  "description": "Get recent messages",
  "handler": "const rows = await ctx.db.query('SELECT content, created_at FROM messages WHERE session_id = $1 ORDER BY created_at DESC LIMIT 10', [req.query.sessionId]); return { status: 200, json: rows };"
}
```

---

## Data Access Patterns for Widget Routes

### What the Sandbox CAN Access

| Method | Use For | Notes |
|--------|---------|-------|
| `ctx.kv.get/set()` | Widget-owned data (todos, counters, settings) | Widget-scoped, no schema, instant |
| `ctx.db.query()` | Structured/relational data | Same Postgres as TalkClaw, parameterized SQL |
| `ctx.fetch()` | Public HTTP APIs (weather, stocks, RSS) | Must be publicly DNS-resolvable, 8s timeout |
| `ctx.fetch('http://host.docker.internal:PORT/...')` | Services on the same machine | Home Assistant, n8n, Grafana, etc. |
| `ctx.env.get()` | Config values | Only `WIDGET_*` prefixed env vars |

### What the Sandbox CANNOT Access

- **No filesystem** — `require('fs')` does not exist, `require()` is not available at all
- **No `localhost`** — `localhost` and `127.0.0.1` refer to the sandbox Docker container, NOT the host machine
- **No internal DNS** — domains like `reminders.clntacq.com` that only resolve on the host will fail from inside Docker
- **No Node.js modules** — no `require()`, no `import`, no npm packages
- **No `process.env`** — only `ctx.env.get(key)` with `WIDGET_` prefix

### Recommended Data Patterns

**Pattern 1: KV Store (simplest — for widget-owned data)**
```javascript
// Save data
await ctx.kv.set('items', JSON.stringify([{ text: 'Buy milk', done: false }]));
// Load data
const items = JSON.parse(await ctx.kv.get('items') || '[]');
return { status: 200, json: items };
```

**Pattern 2: PostgreSQL (for structured/relational data)**
```javascript
// Create table on first use (idempotent)
await ctx.db.query(`CREATE TABLE IF NOT EXISTS widget_tasks (
  id SERIAL PRIMARY KEY, text TEXT NOT NULL, done BOOLEAN DEFAULT false
)`);
const rows = await ctx.db.query('SELECT * FROM widget_tasks ORDER BY id');
return { status: 200, json: rows };
```

**Pattern 3: Public API Fetch**
```javascript
const raw = await ctx.fetch('https://api.weatherapi.com/v1/current.json?key=xxx&q=Austin');
const data = JSON.parse(raw);
return { status: 200, json: { temp: data.current.temp_f } };
```

**Pattern 4: Host Services (Beelink local services)**
```javascript
// Use host.docker.internal, NEVER localhost
const raw = await ctx.fetch('http://host.docker.internal:8123/api/states', {
  headers: { 'Authorization': 'Bearer ha_token_here' }
});
return { status: 200, json: JSON.parse(raw) };
```

**Pattern 5: Data Bridge (PREFERRED for calendar, email, system data)**

The TalkClaw Data Bridge runs on the host at port 3847. It wraps CLI tools (like `gog` for Google services) as JSON HTTP endpoints. **Always use the bridge for host-local data** — the sandbox cannot run shell commands.

```javascript
const token = ctx.env.get('BRIDGE_TOKEN');
const raw = ctx.fetch('http://host.docker.internal:3847/api/calendar/today', {
  headers: { 'Authorization': 'Bearer ' + token }
});
const data = JSON.parse(raw);
return { status: 200, json: data };
```

**Available bridge endpoints:**

| Endpoint | Description | Query params |
|----------|-------------|--------------|
| `GET /api/calendar/events` | Upcoming calendar events | `?days=7&max=20&calendar=primary` |
| `GET /api/calendar/today` | Today's events | `?calendar=primary` |
| `GET /api/mail/unread` | Unread email threads | `?max=10` |
| `GET /api/mail/search` | Search email | `?q=from:someone&max=10` |
| `GET /api/system/stats` | CPU, memory, disk, uptime | — |
| `GET /api/health` | Health check (no auth) | — |

All endpoints require `Authorization: Bearer {token}` except `/api/health`. The token is available via `ctx.env.get('BRIDGE_TOKEN')`.

New bridge endpoints can be added on request — each is just a route file in `talkclaw-bridge/src/routes/`.

### Common Mistakes

| Wrong | Right | Why |
|-------|-------|-----|
| `require('fs')` | `ctx.kv.set(key, data)` | No filesystem in sandbox |
| `fetch('http://localhost:3100/...')` | `ctx.fetch('http://host.docker.internal:3100/...')` | localhost = sandbox container |
| `fetch('http://reminders.clntacq.com/...')` | `ctx.fetch('http://host.docker.internal:PORT/...')` | Internal DNS not resolvable from Docker |
| Hardcoded API token | Use `context.apiToken` from webhook | Token may change |

---

## Error Handling Convention

### In Widget Frontend (MANDATORY)

ALL fetch calls in TC:SCRIPT MUST be wrapped in try/catch:

```javascript
async function loadData() {
  try {
    const res = await fetch('/w/my-widget/data');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    renderData(data);
  } catch (err) {
    TalkClaw.handleError(err, 'Loading widget data');
  }
}
```

### Self-Healing Loop

1. Route handler throws → sandbox logs to `widget_error_log`
2. Vapor posts system message to the widget's `created_by_session` with error details + handler code
3. You (the agent) see the error in chat context
4. Fix via `PATCH /api/v1/widgets/:slug` — widget reloads automatically
5. No user intervention needed

---

## Iteration Protocol

When updating an existing widget:

1. `GET /api/v1/widgets/:slug` — fetch current state
2. Read the current sections to understand what exists
3. Identify which section(s) need changes
4. `PATCH /api/v1/widgets/:slug` with only the changed sections
5. iOS receives `widgetUpdated` event and reloads

NEVER recreate a widget that already exists. Always PATCH.

---

## Complete Widget Example

Here's a full working widget — a simple counter with backend persistence:

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<meta name="tc-widget-slug" content="tap-counter">
<meta name="tc-widget-title" content="Tap Counter">
<meta name="tc-widget-description" content="A persistent tap counter with daily reset">
<link rel="stylesheet" href="/static/talkclaw.css">
</head>
<body>

<!-- TC:VARS
{
  "label": "Taps Today"
}
-->

<!-- TC:HTML -->
<div class="tc-glass" id="root">
  <div class="tc-flex tc-items-center tc-justify-between">
    <div>
      <div class="tc-metric-label" id="label">Taps Today</div>
      <div class="tc-metric tc-text-accent" id="count">—</div>
    </div>
    <button class="tc-btn tc-btn-primary" id="tap-btn">Tap</button>
  </div>
</div>
<!-- /TC:HTML -->

<!-- TC:STYLE -->
<style>
#tap-btn {
  font-size: 17px;
  padding: var(--tc-space-md) var(--tc-space-lg);
  border-radius: var(--tc-radius-xl);
}
#tap-btn:active {
  transform: scale(0.95);
}
</style>
<!-- /TC:STYLE -->

<!-- TC:SCRIPT -->
<script src="/static/talkclaw-bridge.js"></script>
<script>
const vars = TalkClaw.vars;
document.getElementById('label').textContent = vars.label || 'Taps Today';

async function loadCount() {
  try {
    const res = await fetch('/w/tap-counter/count');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    document.getElementById('count').textContent = data.count;
  } catch (err) {
    TalkClaw.handleError(err, 'Loading count');
  }
}

document.getElementById('tap-btn').addEventListener('click', async () => {
  try {
    const res = await fetch('/w/tap-counter/increment', { method: 'POST' });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    document.getElementById('count').textContent = data.count;
  } catch (err) {
    TalkClaw.handleError(err, 'Incrementing count');
  }
});

loadCount();
</script>
<!-- /TC:SCRIPT -->

<!-- TC:ROUTES
[
  {
    "method": "GET",
    "path": "/count",
    "description": "Get current tap count",
    "handler": "const count = (await ctx.kv.get('count')) || 0; return { status: 200, json: { count } };"
  },
  {
    "method": "POST",
    "path": "/increment",
    "description": "Increment tap count by 1",
    "handler": "let count = (await ctx.kv.get('count')) || 0; count++; await ctx.kv.set('count', count); return { status: 200, json: { count } };"
  }
]
-->

</body>
</html>
```

---

## Session Key Format

Each TalkClaw session maps to an OpenClaw session key: `talkclaw:dm:{sessionUUID}` (lowercased). This is how the channel plugin routes messages to the right conversation.

## Proactive Messages (Cron / Scheduled Push)

You can push messages to the iOS app without a user prompt — for reminders, daily digests, scheduled notifications, etc. Use the standard messages endpoint with `role: "assistant"`:

```
POST /api/v1/sessions/:id/messages
Authorization: Bearer clw_...
Content-Type: application/json

{ "content": "Your reminder text here", "role": "assistant" }
```

This saves the message to the database and pushes it to the iOS app in real time via WebSocket. No AI call is triggered — the message appears directly in the chat as an assistant message.

- Omit `role` or set `"role": "user"` for normal behavior (saves as user message + triggers AI)
- Use `GET /api/v1/sessions` to find a session ID

## Authentication

- The server auto-generates a `clw_` prefixed API token on first run
- Stored in a Docker volume at `/data/.talkclaw-token`
- iOS app stores it in Keychain after setup
- All API calls use `Authorization: Bearer clw_...`
- Widget routes use `?token=` query param (auto-appended by iOS app)
