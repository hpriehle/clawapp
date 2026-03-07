# Dashboard Widget Patterns

> Widgets are freeform — any valid HTML/CSS/JS runs in the WKWebView. This guide teaches **patterns**, not templates. The user can ask for anything: metrics, charts, tables, games, forms, integrations. Use these patterns to build whatever they need.

## Dashboard vs Inline Widgets

| | Inline (chat) | Dashboard |
|---|---|---|
| **Scrolling** | Disabled — content auto-sizes | Enabled — tall content scrolls |
| **Sizes** | Auto-height | Small (1×1 ~172pt²), Medium (2×1 ~360×172pt), Large (2×2 ~360×360pt) |
| **Lifecycle** | Tied to chat message | Persistent — always visible |
| **Auto-refresh** | Optional | Expected for live data |

**Pinning to dashboard:** After creating a widget with `surface: "inline"`, pin it via:
```
POST /api/v1/dashboard/:slug  { "size": "small" }
```
Or create with `surface: "dashboard"` to skip inline delivery.

**Sizes:** `"small"` = 1×1 grid cell, `"medium"` = full width single row, `"large"` = full width double height.

## Core Patterns

### Pattern 1: Data Fetching + Rendering

The fundamental pattern: route handler fetches data → frontend calls route → renders to DOM.

```javascript
// TC:ROUTES handler
{
  "method": "GET",
  "path": "/data",
  "description": "Fetch latest metrics",
  "handler": "const result = await ctx.fetch('https://api.example.com/metrics'); return { status: 200, json: result.body };"
}

// TC:SCRIPT
async function loadData() {
  try {
    const res = await fetch('/w/my-widget/data');
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const data = await res.json();
    renderData(data);
  } catch (err) {
    TalkClaw.handleError(err, 'Loading data');
  }
}
loadData();
```

### Pattern 2: Auto-Refresh

Use `TalkClaw.startAutoRefresh()` for live data. It handles:
- Immediate first call
- Interval polling
- Pause when app is backgrounded (Page Visibility API)
- Height reporting after each refresh

```javascript
TalkClaw.startAutoRefresh(30000, async function() {
  const res = await fetch('/w/my-widget/data');
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data = await res.json();
  renderData(data);
});
```

Call `TalkClaw.stopAutoRefresh()` if you need to stop manually.

### Pattern 3: SVG Charting

No external libraries needed. Build charts with pure JS + SVG:

```javascript
function sparkline(container, values, color) {
  const w = container.clientWidth;
  const h = 40;
  const max = Math.max(...values);
  const min = Math.min(...values);
  const range = max - min || 1;
  const step = w / (values.length - 1);

  const points = values.map((v, i) =>
    `${i * step},${h - ((v - min) / range) * h}`
  ).join(' ');

  container.innerHTML = `
    <svg viewBox="0 0 ${w} ${h}" class="tc-chart">
      <polyline points="${points}" fill="none" stroke="${color}"
        stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>`;
}
```

### Pattern 4: External API Integration

Route handlers can call any external API via `ctx.fetch()`:

```javascript
// TC:ROUTES
{
  "method": "GET",
  "path": "/weather",
  "description": "Get weather data",
  "handler": "const apiKey = await ctx.env.get('WIDGET_WEATHER_KEY'); const res = await ctx.fetch('https://api.openweathermap.org/data/2.5/weather?q=Seattle&appid=' + apiKey + '&units=imperial'); return { status: 200, json: res.body };"
}
```

Secrets go in `WIDGET_*` env vars accessible via `ctx.env.get()` — never in render vars or frontend code.

### Pattern 5: KV-Backed State

Use `ctx.kv` for widget-scoped persistent state without needing a database table:

```javascript
// Save state
await ctx.kv.set('last_sync', new Date().toISOString());
await ctx.kv.set('settings', JSON.stringify({ theme: 'dark', limit: 50 }));

// Read state
const lastSync = await ctx.kv.get('last_sync');
const settings = JSON.parse(await ctx.kv.get('settings') || '{}');
```

---

## Example Widgets

> These are examples of common patterns. The user can ask for anything — custom games, forms, data explorers, integrations. Use the patterns above to build whatever they need.

### Example 1: Metric Card with Sparkline

Shows: data fetching, SVG charting, auto-refresh, trend indicators.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<meta name="tc-widget-slug" content="server-uptime">
<meta name="tc-widget-title" content="Server Uptime">
<meta name="tc-widget-description" content="Live server response time with sparkline">
<link rel="stylesheet" href="/static/talkclaw.css">
</head>
<body>

<!-- TC:VARS
{
  "endpoint_url": "https://api.example.com/health",
  "label": "API Response Time"
}
-->

<!-- TC:HTML -->
<div class="tc-glass" id="root">
  <div class="tc-flex tc-items-center tc-justify-between">
    <div>
      <div class="tc-flex tc-items-center tc-gap-sm">
        <span class="tc-status-dot tc-status-dot--ok" id="status-dot"></span>
        <span class="tc-metric-label" id="label">API Response Time</span>
        <span class="tc-refresh-dot" id="refresh-dot" style="display:none"></span>
      </div>
      <div class="tc-flex tc-items-center tc-gap-sm">
        <span class="tc-metric tc-text-accent" id="value">—</span>
        <span class="tc-text-sm" id="unit">ms</span>
        <span id="trend"></span>
      </div>
    </div>
  </div>
  <div id="chart" class="tc-chart" style="height:40px;margin-top:var(--tc-space-sm)"></div>
</div>
<!-- /TC:HTML -->

<!-- TC:STYLE -->
<style>
/* No extra styles needed — CSS utilities handle layout */
</style>
<!-- /TC:STYLE -->

<!-- TC:SCRIPT -->
<script src="/static/talkclaw-bridge.js"></script>
<script>
const vars = TalkClaw.vars;
document.getElementById('label').textContent = vars.label || 'Response Time';

const history = [];
let prevValue = null;

function render(ms, ok) {
  document.getElementById('value').textContent = Math.round(ms);
  const dot = document.getElementById('status-dot');
  dot.className = 'tc-status-dot ' + (ok ? 'tc-status-dot--ok' : 'tc-status-dot--error');

  const trend = document.getElementById('trend');
  if (prevValue !== null) {
    const diff = ms - prevValue;
    if (Math.abs(diff) > 5) {
      trend.className = diff > 0 ? 'tc-trend-up' : 'tc-trend-down';
      trend.textContent = Math.abs(Math.round(diff)) + 'ms';
    } else {
      trend.textContent = '';
    }
  }
  prevValue = ms;

  history.push(ms);
  if (history.length > 20) history.shift();
  if (history.length > 1) sparkline(document.getElementById('chart'), history, 'var(--tc-accent)');
}

function sparkline(el, vals, color) {
  const w = el.clientWidth || 200;
  const h = 40;
  const max = Math.max(...vals), min = Math.min(...vals);
  const range = max - min || 1;
  const step = w / (vals.length - 1);
  const pts = vals.map((v, i) => `${i * step},${h - ((v - min) / range) * h}`).join(' ');
  el.innerHTML = '<svg viewBox="0 0 ' + w + ' ' + h + '"><polyline points="' + pts + '" fill="none" stroke="' + color + '" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
}

TalkClaw.startAutoRefresh(30000, async function() {
  document.getElementById('refresh-dot').style.display = '';
  const res = await fetch('/w/server-uptime/ping');
  if (!res.ok) throw new Error('HTTP ' + res.status);
  const data = await res.json();
  render(data.responseMs, data.ok);
  setTimeout(function() { document.getElementById('refresh-dot').style.display = 'none'; }, 1000);
});
</script>
<!-- /TC:SCRIPT -->

<!-- TC:ROUTES
[
  {
    "method": "GET",
    "path": "/ping",
    "description": "Ping the configured endpoint and measure response time",
    "handler": "const url = (await ctx.kv.get('endpoint_url')) || 'https://api.example.com/health'; const start = Date.now(); try { const res = await ctx.fetch(url); const ms = Date.now() - start; return { status: 200, json: { responseMs: ms, ok: res.status < 400 } }; } catch(e) { return { status: 200, json: { responseMs: Date.now() - start, ok: false } }; }"
  }
]
-->

</body>
</html>
```

### Example 2: Data Table with Sorting

Shows: scrollable content, sortable columns, table styling, pagination.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<meta name="tc-widget-slug" content="recent-activity">
<meta name="tc-widget-title" content="Recent Activity">
<meta name="tc-widget-description" content="Sortable activity log with pagination">
<link rel="stylesheet" href="/static/talkclaw.css">
</head>
<body>

<!-- TC:VARS
{
  "page_size": "10"
}
-->

<!-- TC:HTML -->
<div class="tc-glass" id="root">
  <div class="tc-flex tc-items-center tc-justify-between" style="margin-bottom:var(--tc-space-sm)">
    <span class="tc-text-sm tc-font-semibold">Recent Activity</span>
    <span class="tc-badge tc-badge-accent" id="total">0 items</span>
  </div>
  <div class="tc-scroll" style="max-height:300px">
    <table class="tc-table" id="table">
      <thead>
        <tr>
          <th data-sort="action" style="cursor:pointer">Action ↕</th>
          <th data-sort="user" style="cursor:pointer">User ↕</th>
          <th data-sort="time" style="cursor:pointer">Time ↕</th>
        </tr>
      </thead>
      <tbody id="tbody"></tbody>
    </table>
  </div>
  <div class="tc-flex tc-items-center tc-justify-between" style="margin-top:var(--tc-space-sm)">
    <button class="tc-btn tc-btn-ghost tc-text-sm" id="prev-btn" disabled>← Prev</button>
    <span class="tc-text-xs tc-text-tertiary" id="page-info">Page 1</span>
    <button class="tc-btn tc-btn-ghost tc-text-sm" id="next-btn" disabled>Next →</button>
  </div>
</div>
<!-- /TC:HTML -->

<!-- TC:STYLE -->
<style>
th[data-sort]:hover { color: var(--tc-accent); }
</style>
<!-- /TC:STYLE -->

<!-- TC:SCRIPT -->
<script src="/static/talkclaw-bridge.js"></script>
<script>
const vars = TalkClaw.vars;
const pageSize = parseInt(vars.page_size) || 10;
let allData = [];
let sortKey = 'time';
let sortAsc = false;
let page = 0;

function render() {
  const sorted = [...allData].sort((a, b) => {
    const va = a[sortKey] || '', vb = b[sortKey] || '';
    return sortAsc ? (va > vb ? 1 : -1) : (va < vb ? 1 : -1);
  });
  const start = page * pageSize;
  const slice = sorted.slice(start, start + pageSize);
  const tbody = document.getElementById('tbody');
  tbody.innerHTML = slice.map(function(row) {
    return '<tr><td>' + esc(row.action) + '</td><td>' + esc(row.user) + '</td><td>' + esc(row.time) + '</td></tr>';
  }).join('');
  document.getElementById('total').textContent = allData.length + ' items';
  document.getElementById('page-info').textContent = 'Page ' + (page + 1) + ' of ' + Math.max(1, Math.ceil(allData.length / pageSize));
  document.getElementById('prev-btn').disabled = page === 0;
  document.getElementById('next-btn').disabled = start + pageSize >= sorted.length;
  TalkClaw.reportHeight();
}

function esc(s) { var d = document.createElement('div'); d.textContent = s; return d.innerHTML; }

document.querySelectorAll('th[data-sort]').forEach(function(th) {
  th.addEventListener('click', function() {
    const key = th.dataset.sort;
    if (sortKey === key) sortAsc = !sortAsc;
    else { sortKey = key; sortAsc = true; }
    page = 0;
    render();
  });
});

document.getElementById('prev-btn').addEventListener('click', function() { page--; render(); });
document.getElementById('next-btn').addEventListener('click', function() { page++; render(); });

TalkClaw.startAutoRefresh(60000, async function() {
  const res = await fetch('/w/recent-activity/data');
  if (!res.ok) throw new Error('HTTP ' + res.status);
  allData = await res.json();
  render();
});
</script>
<!-- /TC:SCRIPT -->

<!-- TC:ROUTES
[
  {
    "method": "GET",
    "path": "/data",
    "description": "Fetch recent activity entries",
    "handler": "const rows = await ctx.db.query('SELECT action, username as user, created_at as time FROM activity_log ORDER BY created_at DESC LIMIT 100'); return { status: 200, json: rows };"
  }
]
-->

</body>
</html>
```

### Example 3: Multi-Section Dashboard Card

Shows: combining multiple visualizations, CSS grid layout, full-width design.

```html
<!DOCTYPE html>
<html lang="en">
<head>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<meta name="tc-widget-slug" content="system-overview">
<meta name="tc-widget-title" content="System Overview">
<meta name="tc-widget-description" content="Combined system metrics — CPU, memory, requests, errors">
<link rel="stylesheet" href="/static/talkclaw.css">
</head>
<body>

<!-- TC:VARS
{
  "refresh_interval_ms": "30000"
}
-->

<!-- TC:HTML -->
<div class="tc-glass" id="root">
  <div class="tc-flex tc-items-center tc-justify-between" style="margin-bottom:var(--tc-space-md)">
    <span class="tc-text-sm tc-font-semibold">System Overview</span>
    <span class="tc-refresh-dot" id="refresh-dot" style="display:none"></span>
  </div>
  <div class="tc-grid-2" style="margin-bottom:var(--tc-space-md)">
    <div class="tc-card">
      <div class="tc-metric-label">CPU</div>
      <div class="tc-metric tc-text-accent" id="cpu">—%</div>
      <div class="tc-progress" style="margin-top:var(--tc-space-xs)">
        <div class="tc-progress-bar" id="cpu-bar" style="width:0%"></div>
      </div>
    </div>
    <div class="tc-card">
      <div class="tc-metric-label">Memory</div>
      <div class="tc-metric tc-text-accent" id="mem">—%</div>
      <div class="tc-progress" style="margin-top:var(--tc-space-xs)">
        <div class="tc-progress-bar" id="mem-bar" style="width:0%"></div>
      </div>
    </div>
  </div>
  <div class="tc-grid-2">
    <div class="tc-card">
      <div class="tc-kv">
        <span class="tc-kv-label">Requests/min</span>
        <span class="tc-kv-value" id="rpm">—</span>
      </div>
      <div class="tc-kv" style="margin-top:var(--tc-space-xs)">
        <span class="tc-kv-label">Avg latency</span>
        <span class="tc-kv-value" id="latency">—</span>
      </div>
    </div>
    <div class="tc-card">
      <div class="tc-kv">
        <span class="tc-kv-label">Errors (1h)</span>
        <span class="tc-kv-value tc-text-error" id="errors">—</span>
      </div>
      <div class="tc-kv" style="margin-top:var(--tc-space-xs)">
        <span class="tc-kv-label">Uptime</span>
        <span class="tc-kv-value tc-text-success" id="uptime">—</span>
      </div>
    </div>
  </div>
</div>
<!-- /TC:HTML -->

<!-- TC:STYLE -->
<style>
/* No extra styles needed */
</style>
<!-- /TC:STYLE -->

<!-- TC:SCRIPT -->
<script src="/static/talkclaw-bridge.js"></script>
<script>
const vars = TalkClaw.vars;

function setBar(id, pct) {
  const bar = document.getElementById(id);
  bar.style.width = pct + '%';
  bar.className = 'tc-progress-bar' + (pct > 90 ? ' tc-error' : pct > 70 ? ' tc-warning' : '');
}

function render(d) {
  document.getElementById('cpu').textContent = d.cpu + '%';
  document.getElementById('mem').textContent = d.mem + '%';
  setBar('cpu-bar', d.cpu);
  setBar('mem-bar', d.mem);
  document.getElementById('rpm').textContent = d.rpm.toLocaleString();
  document.getElementById('latency').textContent = d.latencyMs + 'ms';
  document.getElementById('errors').textContent = d.errors;
  document.getElementById('uptime').textContent = d.uptime;
}

TalkClaw.startAutoRefresh(parseInt(vars.refresh_interval_ms) || 30000, async function() {
  document.getElementById('refresh-dot').style.display = '';
  const res = await fetch('/w/system-overview/metrics');
  if (!res.ok) throw new Error('HTTP ' + res.status);
  render(await res.json());
  setTimeout(function() { document.getElementById('refresh-dot').style.display = 'none'; }, 1000);
});
</script>
<!-- /TC:SCRIPT -->

<!-- TC:ROUTES
[
  {
    "method": "GET",
    "path": "/metrics",
    "description": "Aggregate system metrics from monitoring API",
    "handler": "const res = await ctx.fetch('https://api.example.com/system/metrics'); const d = res.body; return { status: 200, json: { cpu: d.cpu_percent || 0, mem: d.memory_percent || 0, rpm: d.requests_per_minute || 0, latencyMs: d.avg_latency_ms || 0, errors: d.error_count_1h || 0, uptime: d.uptime || '—' } };"
  }
]
-->

</body>
</html>
```

---

## Design Tips

- **Use `tc-glass` as root** — matches the iOS card chrome
- **Use `tc-card` for nested sections** — creates visual depth hierarchy
- **Prefer CSS utilities** over custom styles — `tc-flex`, `tc-grid-2`, `tc-kv`, `tc-metric`
- **Use CSS custom properties** (`var(--tc-*)`) for all colors, spacing, radii
- **Keep fonts system** — `-apple-system` matches native iOS text
- **Medium/Large widgets** are ideal for tables, charts, and multi-section layouts
- **Test on iPhone width** — small cards are ~172px square, medium/large are ~360px wide
