# TalkClaw Widget Engine — Product Requirements Document v2.3

**Status:** Implementation Ready — All architecture decisions resolved
**Platform:** TalkClaw iOS + Vapor server on Beelink N95 (Docker)
**Agent Runtime:** OpenClaw Gateway — multi-model (Claude, GPT-4, DeepSeek, local)
**Core Concept:** The AI writes full-stack widgets: a single structured HTML file (frontend) + sandboxed JS route handlers (backend). iOS renders via WKWebView. No pre-built components, no App Store updates required.
**v2.3 Changes:** Resolved: sandbox runtime (isolated-vm Node.js sidecar over Unix socket), remote access (Tailscale-always, no LAN assumption, HTTPS enforced), WKWebView isolation (one process per widget, V8 isolate per route), data limits (AI-trusted, no hard cap).
**Author:** Harrison Riehle / Omnira
**Date:** March 2026

---

## PART 1 — The Mental Model

### The AI Is a Full-Stack Developer

When a user asks TalkClaw for a widget — or when the agent decides one is appropriate — the AI does not pick from a menu of pre-built components. It writes code. A complete mini web application: a single structured HTML file for the frontend, and one or more backend JavaScript route handlers the Vapor server executes on demand.

The iOS app has no knowledge of widget types, no switch statements over component names, no pre-baked renderers. Every widget lives entirely on the server. This means:

- Any UI the AI can imagine and code, the user gets. No ceiling imposed by a component library.
- Adding new widget capabilities requires zero iOS code changes and zero App Store updates.
- Widgets are versioned, editable, and self-healing — the agent can fix its own mistakes mid-conversation.
- The platform works with any model routed through OpenClaw — Claude, GPT-4, DeepSeek, local.

### The Full Loop

1. **Trigger** — User says "make me a widget showing my Omnira lead count" — OR — agent detects the user has asked for the same data 3+ times and proactively offers.
2. **AI Plans** — Agent consults its skill context: reads the Widget Library (existing widgets), the design system reference, the sandbox API docs, and the HTML file structure convention.
3. **AI Generates** — Agent produces one artifact: a structured HTML file with named sections. This single file contains the frontend UI, inline styles, JavaScript logic, and route handler definitions embedded as JSON.
4. **Server Stores** — Agent calls `POST /api/v1/widgets`. Vapor parses the named sections, stores the HTML in the `widgets` table, extracts and registers the route handlers into `widget_routes`, and makes the sandbox live immediately.
5. **iOS Renders** — Server emits a `widgetInjected` WebSocket event. iOS opens a WKWebView pointed at `/w/:slug` on the Tailscale hostname. The session cookie is set. Widget loads, calls its own backend routes, displays data.
6. **User Interacts** — The widget is a real JS app. Buttons, forms, charts, polling — all native. Interactions that need the agent post back via the TalkClaw JS bridge.
7. **Agent Iterates** — User says "add a chart to that widget". Agent searches the Widget Library, finds the slug, fetches current HTML, patches the relevant section. Widget reloads in place.
8. **Error Self-Heal** — If a route handler throws, the widget shows an inline error state AND posts a system message into the originating chat session. The agent sees the error and can fix it without user intervention.
9. **Dashboard Pin** — User pins any inline widget to the Dashboard tab. It persists as a card, live as long as the server is running.

---

## PART 2 — Widget File Structure

### The Single-File Widget Format

A widget is stored as one HTML file in Postgres. It is structured with named HTML comment sections that both humans and the agent can navigate. The Vapor server parses these sections on ingest to extract route definitions. On serve, it injects render variables and strips the route definitions block before sending to the browser.

### 2.1 File Template

Every AI-generated widget MUST follow this structure:

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
"another_var": 42
}
-->

<!-- TC:HTML -->
<div class="tc-glass" id="root">
<!-- Widget markup here -->
</div>
<!-- /TC:HTML -->

<!-- TC:STYLE -->
<style>
/* Widget-specific styles here */
/* Uses var(--tc-*) tokens from talkclaw.css */
</style>
<!-- /TC:STYLE -->

<!-- TC:SCRIPT -->
<script src="/static/talkclaw-bridge.js"></script>
<script>
const vars = TalkClaw.vars; // Injected render variables
// Widget JavaScript logic here
</script>
<!-- /TC:SCRIPT -->

<!-- TC:ROUTES
[
{
"method": "GET",
"path": "/data",
"description": "Fetch widget data",
"handler": "const rows = await ctx.db.query('SELECT ...');  return { status: 200, json: rows };"
}
]
-->

</body>
</html>
```

### 2.2 Named Sections Reference

| Field | Type | Description |
|-------|------|-------------|
| TC:VARS | JSON object | Default render variable values. Merged with live `render_vars` from DB at serve time. |
| TC:HTML | HTML markup | The widget's DOM structure. |
| TC:STYLE | CSS in `<style>` tag | Widget-specific CSS. Should use `var(--tc-*)` tokens. |
| TC:SCRIPT | JS in `<script>` tag | All widget logic: data fetching, interactivity, bridge calls. |
| TC:ROUTES | JSON array | Route handler definitions. Extracted by Vapor on ingest, stored in `widget_routes`, NOT sent to browser. |

### 2.3 Section-Targeted PATCH

The `PATCH /api/v1/widgets/:slug` endpoint accepts a `sections` object. The agent only sends the sections it wants to change:

```json
PATCH /api/v1/widgets/lead-count-dashboard
{
  "sections": {
    "TC:SCRIPT": "<script>\n  // Updated JS logic\n</script>",
    "TC:ROUTES": "[{ \"method\": \"GET\", \"path\": \"/data\", ... }]"
  }
}
```

Vapor merges the provided sections into the stored HTML, increments the version, snapshots the previous version, re-registers any changed routes in the sandbox, and returns the new version number. iOS receives a `widgetUpdated` WebSocket event and reloads the WKWebView.

### 2.4 Render Variables

Render variables are key-value pairs stored on the widget record and injected into the HTML at serve time as `window.TALKCLAW_VARS` immediately before the TC:SCRIPT section. The TC:VARS section defines defaults; live values from the DB override them.

Examples:
- Lead count widget: `{ filter_status: 'new', highlight_threshold: 50, refresh_interval_ms: 30000 }`
- Marathon training widget: `{ training_week: 14, goal_miles: 40, athlete_name: 'Harrison' }`

Render variables are NOT secrets. Anything requiring credentials must live in a backend route handler.

---

## PART 3 — Authentication & Security

### 3.1 Widget Session Cookie

Widget routes at `/w/:slug/*` are served without the main Bearer token. Instead, they are protected by a long-lived HttpOnly session cookie issued by the Vapor server.

#### Cookie Properties

| Property | Value |
|----------|-------|
| Name | `tc_widget_session` |
| Value | Signed JWT: `{ jti, iat, exp, sub: 'widget-session' }` |
| HttpOnly | `true` — not accessible from widget JavaScript |
| SameSite | `Strict` |
| Secure | `true` — all traffic over Tailscale (HTTPS) |
| TTL | 30 days |
| Scope | Path: `/w/` — only sent to widget routes |

#### Issuance Flow

1. On app launch, iOS calls `POST /api/v1/widget-session` using the existing Keychain-stored Bearer token.
2. Vapor validates the Bearer token, issues a signed JWT, and sets it as a `Set-Cookie` header.
3. The WKWebView's `WKWebsiteDataStore` shares cookies with the app's `HTTPCookieStorage`.
4. iOS schedules a background refresh at T-2 days before expiry (belt-and-suspenders).
5. If any widget `fetch()` returns 401, the `talkclaw-bridge.js` fetch interceptor catches it, posts a `refreshSession` message to Swift, waits for the new cookie, then retries the original request transparently.

### 3.2 Sandbox Security Boundary

Agent-written route handlers run in a JS sandbox powered by `isolated-vm` — a Node.js native addon that uses V8 isolates. A lightweight Node.js sidecar service runs alongside Vapor in Docker Compose, communicating over a Unix socket.

The sandbox enforces:
- No filesystem access
- No process spawning
- No arbitrary module imports — only the `ctx` API surface (`db`, `fetch`, `kv`, `openclaw`, `env`)
- No cross-widget data access — `ctx.db` queries are scoped; `ctx.kv` is namespaced by `widget_id`
- 10 second execution timeout per route invocation
- 64MB memory limit per sandbox worker

---

## PART 3B — Infrastructure & Runtime

### 3B.1 Remote Access — Tailscale Always

No LAN-only path. The app always connects over Tailscale. Tailscale provides mutual TLS (HTTPS enforced). The Secure cookie flag works unconditionally.

Server URL is stored in Keychain, set through Settings tab. All API calls, WebSocket connections, WKWebView loads, and static assets use this as base.

Widget JS calls routes as relative paths (e.g. `fetch('/w/my-widget/data')`) — resolves correctly via WKWebView base URL.

### 3B.2 Sandbox Runtime — isolated-vm Node.js Sidecar

Docker Compose service topology:
- `talkclaw-server` (Vapor/Swift) — existing. Handles REST API, WebSockets, static files, `/w/:slug` serving.
- `talkclaw-sandbox` (Node.js + isolated-vm) — **new service**. Communicates with Vapor over a shared Unix socket volume. JSON-RPC interface: `execute(widgetId, routeId, req) → response`. No external port.
- `postgres` — unchanged.

### 3B.3 WKWebView Process Isolation

Every WidgetView instance creates its own `WKWebView` with its own `WKProcessPool`. Each widget runs in a completely isolated OS-level web content process.

Cookie sharing: use a single `WKWebsiteDataStore.nonPersistent()` instance held by AppState and passed to every WidgetView's `WKWebViewConfiguration`. All widgets share auth; none share JS state.

Memory: ~20-40MB per widget process. Dashboard with 6 widgets ≈ 240MB in web content processes.

---

## PART 4 — Error Handling & Agent Self-Healing

### 4.1 Route Handler Errors

**In the Widget (Frontend):**
- Widget JS wraps all fetch calls in try/catch.
- `TalkClaw.handleError(err, context)` renders an inline error card with Retry and Report to Agent buttons.
- Report to Agent calls `TalkClaw.sendStructured('widget_error', { slug, route, error, context })`.

**In the Chat Session (Backend):**
- Vapor sandbox logs the full stack trace to `widget_error_log`.
- Posts a system message to the widget's `created_by_session`:

```
[Widget Error] slug: lead-count-dashboard
Route: GET /data
Error: ReferenceError: ctx.db.query is not a function
Stack: handler.js:3:18
Widget HTML (TC:ROUTES section):
[current TC:ROUTES content]
```

The agent receives this as context and can fix the handler via `PATCH /api/v1/widgets/:slug` without user involvement.

### 4.2 Widget Load Errors

WidgetView detects navigation failure via `WKNavigationDelegate.didFail`. Renders a native SwiftUI error state (not web view) with widget title, error icon, failure reason, and Retry button. Does NOT post to chat — load failures are likely connectivity issues.

### 4.3 Error Log Table

| Field | Type | Description |
|-------|------|-------------|
| id | UUID PK | Primary key |
| widget_id | UUID FK | References widgets.id |
| route_id | UUID FK | References widget_routes.id |
| error_message | TEXT | Exception message |
| stack_trace | TEXT | Full stack trace |
| request_path | TEXT | The route path that was called |
| notified_session | UUID FK | Session that received the error system message |
| resolved_at | TIMESTAMPTZ | Set when the agent patches the widget after this error |
| created_at | TIMESTAMPTZ | Error timestamp |

---

## PART 5 — The OpenClaw Skill

### Location
`~/.openclaw/skills/talkclaw/widget-engine.md` on the Beelink server.

### 5.1 Skill Sections

1. **Capability & Intent Detection** — When to build a widget vs. respond with text. Trigger heuristics: "show me", "track", "monitor", "chart", "dashboard". Proactive offer: same data requested 3+ times.
2. **Widget Library (Dynamic)** — Auto-generated by Vapor from the `widgets` table. Lists all existing widgets with slug, title, description, surface, created date. Agent always searches this before creating new widgets.
3. **File Structure & Boilerplate** — The mandatory HTML template.
4. **Design System Reference** — All CSS custom properties and utility classes from `talkclaw.css`.
5. **JS Bridge API** — Full `TalkClaw.*` reference with usage examples.
6. **Sandbox Route API** — Complete `ctx` object reference available in TC:ROUTES handlers.
7. **Error Handling Convention** — Mandatory try/catch patterns.
8. **Iteration Protocol** — Fetch → read → identify section → PATCH only that section.

---

## PART 6 — Database Schema

### 6.1 widgets

| Field | Type | Description |
|-------|------|-------------|
| id | UUID PK | Primary key |
| slug | TEXT UNIQUE NOT NULL | URL-safe identifier. Used in all API calls and as route namespace under `/w/:slug/*` |
| title | TEXT NOT NULL | Human-readable name shown in iOS widget chrome |
| description | TEXT NOT NULL | Included in Widget Library skill section for agent discovery |
| surface | TEXT NOT NULL | `inline` or `dashboard` |
| html | TEXT NOT NULL | The full structured widget HTML file |
| render_vars | JSONB NOT NULL DEFAULT '{}' | Live render variable overrides |
| version | INTEGER NOT NULL DEFAULT 1 | Incremented on every PATCH |
| created_by_session | UUID FK NULL | Chat session that created this widget (for error routing) |
| created_at | TIMESTAMPTZ NOT NULL | Auto-set on insert |
| updated_at | TIMESTAMPTZ NOT NULL | Auto-set on update |

### 6.2 widget_routes

| Field | Type | Description |
|-------|------|-------------|
| id | UUID PK | Primary key |
| widget_id | UUID FK NOT NULL | References widgets.id (cascade delete) |
| method | TEXT NOT NULL | HTTP method: GET POST PUT DELETE PATCH |
| path | TEXT NOT NULL | Route path relative to `/w/:slug/` |
| handler_js | TEXT NOT NULL | JavaScript function body. Receives `(req, ctx)`. Returns `{ status, json }` |
| description | TEXT NOT NULL | Agent-written description |
| created_at | TIMESTAMPTZ NOT NULL | |
| updated_at | TIMESTAMPTZ NOT NULL | |

### 6.3 widget_kv

| Field | Type | Description |
|-------|------|-------------|
| widget_id | UUID FK NOT NULL | Composite PK with key |
| key | TEXT NOT NULL | Automatically namespaced to the widget |
| value | JSONB NOT NULL | Any JSON-serializable value |
| updated_at | TIMESTAMPTZ NOT NULL | |

### 6.4 dashboard_layout

| Field | Type | Description |
|-------|------|-------------|
| id | UUID PK | Primary key |
| widget_id | UUID FK NOT NULL | References widgets.id |
| position | INTEGER NOT NULL | Zero-indexed display order |
| col_span | INTEGER NOT NULL DEFAULT 1 | 1 = half-width, 2 = full-width |
| pinned_at | TIMESTAMPTZ NOT NULL | When the user pinned this widget |

### 6.5 widget_versions

| Field | Type | Description |
|-------|------|-------------|
| id | UUID PK | Primary key |
| widget_id | UUID FK NOT NULL | References widgets.id |
| version | INTEGER NOT NULL | Version number of this snapshot |
| html | TEXT NOT NULL | Full HTML at this version |
| render_vars_snapshot | JSONB NOT NULL | render_vars at this version |
| snapshot_at | TIMESTAMPTZ NOT NULL | |

### 6.6 widget_error_log

| Field | Type | Description |
|-------|------|-------------|
| id | UUID PK | Primary key |
| widget_id | UUID FK NOT NULL | References widgets.id |
| route_id | UUID FK NOT NULL | References widget_routes.id |
| error_message | TEXT NOT NULL | Exception message |
| stack_trace | TEXT | Full sandbox stack trace |
| request_path | TEXT NOT NULL | Route path that triggered the error |
| notified_session | UUID FK NULL | Session that received error system message |
| resolved_at | TIMESTAMPTZ NULL | Set when agent patches the widget |
| created_at | TIMESTAMPTZ NOT NULL | |

### 6.7 widget_sessions

| Field | Type | Description |
|-------|------|-------------|
| id | UUID PK | Primary key |
| jti | TEXT UNIQUE NOT NULL | JWT token ID / revocation handle |
| issued_at | TIMESTAMPTZ NOT NULL | |
| expires_at | TIMESTAMPTZ NOT NULL | issued_at + 30 days |
| revoked_at | TIMESTAMPTZ NULL | Set by DELETE /api/v1/widget-session |

---

## PART 7 — API Reference

All `/api/v1/*` endpoints require Bearer token. `/w/*` endpoints require the `tc_widget_session` cookie.

### 7.1 Widget Lifecycle

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/v1/widgets | List all widgets. `?surface=inline\|dashboard` filter |
| POST | /api/v1/widgets | Create widget. Body: `{ slug, title, description, surface, html }` |
| GET | /api/v1/widgets/:slug | Fetch full widget record including html and render_vars |
| PATCH | /api/v1/widgets/:slug | Update widget sections. Body: `{ sections: { 'TC:SCRIPT': '...' } }` |
| DELETE | /api/v1/widgets/:slug | Delete widget and all related data |
| GET | /api/v1/widgets/:slug/versions | List version snapshots |
| POST | /api/v1/widgets/:slug/rollback/:version | Restore a previous version |

### 7.2 Render Variables

| Method | Path | Description |
|--------|------|-------------|
| PATCH | /api/v1/widgets/:slug/vars | Merge-update render_vars (partial) |
| PUT | /api/v1/widgets/:slug/vars | Replace entire render_vars |
| DELETE | /api/v1/widgets/:slug/vars/:key | Remove a single render variable |

### 7.3 Dashboard

| Method | Path | Description |
|--------|------|-------------|
| GET | /api/v1/dashboard | Fetch ordered layout |
| PUT | /api/v1/dashboard | Replace full layout order |
| POST | /api/v1/dashboard/:slug | Pin a widget. Body: `{ col_span }` |
| DELETE | /api/v1/dashboard/:slug | Unpin a widget |
| PATCH | /api/v1/dashboard/:slug | Update col_span |

### 7.4 Auth

| Method | Path | Description |
|--------|------|-------------|
| POST | /api/v1/widget-session | Exchange Bearer token for 30-day widget session cookie |
| DELETE | /api/v1/widget-session | Revoke current widget session cookie |

### 7.5 Widget Serving (Cookie Auth — Called by WKWebView)

| Method | Path | Description |
|--------|------|-------------|
| GET | /w/:slug | Serve widget HTML (inject vars, strip routes, cache-bust with `?v=VERSION`) |
| * | /w/:slug/* | Proxy to sandbox router for widget's registered routes |
| GET | /static/talkclaw.css | TalkClaw design system stylesheet |
| GET | /static/talkclaw-bridge.js | TalkClaw JS bridge script |

---

## PART 8 — iOS Rendering

### 8.1 WidgetView

The single SwiftUI component that knows about widgets. Used in two contexts: WidgetBubbleView (inline in chat) and DashboardView (pinned grid).

| Property | Description |
|----------|-------------|
| slug | String. Widget identifier. Constructs load URL: `/w/:slug?v=VERSION` |
| surface | WidgetSurface enum: `.inline` \| `.dashboard`. Controls sizing constraints |
| version | Int. Current version. Cache-busting parameter |
| bridgeDelegate | WidgetBridgeDelegate protocol. Receives JS bridge callbacks |
| onHeightChange | `((CGFloat) -> Void)?`. For inline auto-sizing |

### 8.2 Widget Session Cookie Management

1. On app launch: iOS calls `POST /api/v1/widget-session`. Vapor generates a jti, stores it in `widget_sessions`, sets the 30-day cookie via `Set-Cookie`.
2. WKWebsiteDataStore shares the app's HTTPCookieStorage.
3. Background Timer fires at T-2 days for proactive refresh.
4. Fetch interceptor in `talkclaw-bridge.js` monkey-patches `window.fetch` — on any 401, posts `refreshSession` to Swift, awaits new cookie, retries transparently.

### 8.3 Inline Chat (WidgetBubbleView)

- Appears in ChatDetailView for any `MessageContent.widget` block. Full-width card between message bubbles.
- Glass chrome: `.ultraThinMaterial` + #161616 at 80% opacity. Corner radius 16pt. 1pt border. 2pt accent top bar.
- Header: widget title (left) + action menu (right): Edit, Pin to Dashboard, Delete.
- WidgetView fills the body. Auto-sizes to content up to 480pt maximum, then scrolls internally.
- Shimmer skeleton while loading. Collapsed summary state after dismiss.
- On `widgetUpdated` WebSocket event: increments version, WKWebView reloads.

### 8.4 Dashboard (DashboardView)

- 2-column LazyVGrid. `col_span` 1 = half width, 2 = full width.
- Full-width: 280pt fixed height. Half-width: 160pt.
- Pull-to-refresh: reloads `GET /api/v1/dashboard`, increments version on all WidgetViews.
- Long-press: Edit Mode. Widgets oscillate 3°. X badge to remove. Drag handle to reorder. Reorder calls `PUT /api/v1/dashboard`.
- Empty state: centered prompt with example suggestion chip.

---

## PART 9 — Implementation Plan

### Phase 1 — Server Foundation (~1 week)
No AI involvement yet. Goal: widget can be created via API and rendered in a test WKWebView.

- Fluent migrations: widgets, widget_routes, widget_kv, dashboard_layout, widget_versions, widget_error_log, widget_sessions
- All `/api/v1/*` REST endpoints
- Static file serving: `/static/talkclaw.css`, `/static/talkclaw-bridge.js` (stub)
- `/w/:slug` serve endpoint: load HTML from DB, merge render_vars, inject `window.TALKCLAW_VARS`, strip TC:ROUTES
- Section parser: extract named TC:* sections from HTML on ingest and PATCH
- Add `WidgetPayload` to SharedModels. Add `.widget(WidgetPayload)` to `MessageContent`

### Phase 2 — Sandbox Router (~1 week)
Goal: widget backend routes work end-to-end.

- `isolated-vm` Node.js sidecar service in Docker Compose. Unix socket communication.
- `/w/:slug/*` catch-all proxy route in Vapor
- Full `ctx` API: `ctx.db`, `ctx.fetch`, `ctx.kv`, `ctx.env`. `ctx.openclaw` stub.
- 10s timeout, 64MB memory limit per worker
- Error logging to `widget_error_log`. System message posting on error.

### Phase 3 — iOS WidgetView (~1 week)
Goal: widgets appear in chat and on the dashboard.

- WidgetView: WKWebView wrapper, auto-sizing, JS bridge Swift-side handler
- Widget session cookie: `POST /api/v1/widget-session` on launch, shared WKWebsiteDataStore, T-2 day refresh, fetch interceptor
- WidgetBubbleView: glass chrome, shimmer, action menu, collapsed state
- Wire `.widget` MessageContent case in ChatDetailView
- DashboardView: grid, Edit Mode, pull-to-refresh, empty state, pin flow
- `widgetUpdated` and `widgetInjected` WebSocket event handling

### Phase 4 — OpenClaw Skill & AI Integration (~1 week)
Goal: the AI creates working widgets from natural language.

- Write `widget-engine.md` skill file — all 8 sections
- Dynamic Widget Library section generation
- MessageController widget injection parser
- Full `talkclaw-bridge.js` implementation
- `ctx.openclaw` fully wired to OpenClaw gateway RPC
- End-to-end test: user asks → agent writes → widget appears → calls backend → displays data

### Phase 5 — Polish & Self-Healing (ongoing)

- Validate agent self-healing loop
- Version history UI in Files tab
- Skill iteration with examples of good widgets
- `talkclaw.css` refinement based on real widget output
- Widget edit flow UX
