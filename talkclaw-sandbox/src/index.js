'use strict';

const net = require('net');
const path = require('path');
const { SandboxManager } = require('./sandbox');
const { createCtxAPI, closePools } = require('./ctx');

const SOCKET_PATH = process.env.SANDBOX_SOCKET || '/tmp/talkclaw-sandbox.sock';
const DB_URL = process.env.DATABASE_URL || 'postgres://talkclaw:talkclaw@db:5432/talkclaw';

// Route registry: widgetId -> [{ routeId, method, path, handlerJS }]
const routeRegistry = new Map();
const sandboxManager = new SandboxManager();

/**
 * JSON-RPC server over Unix socket.
 * Vapor sends requests, sandbox executes widget route handlers.
 */
function startServer() {
  // Clean up stale socket
  const fs = require('fs');
  try { fs.unlinkSync(SOCKET_PATH); } catch {}

  const server = net.createServer((conn) => {
    let buffer = '';

    conn.on('data', (chunk) => {
      buffer += chunk.toString();

      // Simple newline-delimited JSON protocol
      let newlineIdx;
      while ((newlineIdx = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, newlineIdx).trim();
        buffer = buffer.slice(newlineIdx + 1);
        if (line) {
          handleRequest(line, conn);
        }
      }
    });

    conn.on('error', (err) => {
      console.error('[sandbox] Connection error:', err.message);
    });
  });

  server.listen(SOCKET_PATH, () => {
    // Make socket accessible
    fs.chmodSync(SOCKET_PATH, 0o777);
    console.log(`[sandbox] Listening on ${SOCKET_PATH}`);
  });

  server.on('error', (err) => {
    console.error('[sandbox] Server error:', err);
    process.exit(1);
  });

  // Graceful shutdown
  process.on('SIGTERM', () => {
    console.log('[sandbox] SIGTERM received, shutting down...');
    server.close();
    sandboxManager.disposeAll();
    closePools().then(() => process.exit(0));
  });
}

/**
 * Handle a JSON-RPC request from Vapor.
 *
 * Methods:
 *   - execute(widgetId, routeId, req) → { status, json }
 *   - register(widgetId, routes) → { ok: true }
 *   - unregister(widgetId) → { ok: true }
 *   - reload(widgetId, routes) → { ok: true }
 *   - ping → { pong: true }
 */
async function handleRequest(line, conn) {
  let request;
  try {
    request = JSON.parse(line);
  } catch {
    sendResponse(conn, { id: null, error: 'Invalid JSON' });
    return;
  }

  const { id, method, params } = request;

  try {
    let result;

    switch (method) {
      case 'execute':
        result = await executeRoute(params);
        break;

      case 'register':
        registerRoutes(params.widgetId, params.routes);
        result = { ok: true };
        break;

      case 'unregister':
        unregisterRoutes(params.widgetId);
        result = { ok: true };
        break;

      case 'reload':
        unregisterRoutes(params.widgetId);
        registerRoutes(params.widgetId, params.routes);
        result = { ok: true };
        break;

      case 'ping':
        result = { pong: true };
        break;

      default:
        result = { error: `Unknown method: ${method}` };
    }

    sendResponse(conn, { id, result });
  } catch (err) {
    sendResponse(conn, {
      id,
      error: {
        message: err.message,
        stack: err.stack,
      },
    });
  }
}

function sendResponse(conn, response) {
  try {
    conn.write(JSON.stringify(response) + '\n');
  } catch {}
}

/**
 * Register widget routes in the local registry.
 */
function registerRoutes(widgetId, routes) {
  routeRegistry.set(widgetId, routes);
  console.log(`[sandbox] Registered ${routes.length} routes for widget ${widgetId}`);
}

/**
 * Unregister widget routes and dispose its sandbox.
 */
function unregisterRoutes(widgetId) {
  routeRegistry.delete(widgetId);
  sandboxManager.dispose(widgetId);
  console.log(`[sandbox] Unregistered widget ${widgetId}`);
}

/**
 * Execute a widget route handler in an isolated V8 sandbox.
 *
 * params: { widgetId, routeId, method, path, body, query, headers }
 * returns: { status, json } or { error }
 */
async function executeRoute(params) {
  const { widgetId, routeId, method, path: routePath, body, query, headers } = params;

  // Find route handler
  const routes = routeRegistry.get(widgetId);
  if (!routes) {
    return { status: 404, json: { error: `Widget ${widgetId} not registered` } };
  }

  const route = routes.find(r => r.routeId === routeId);
  if (!route) {
    // Try matching by method + path
    const matched = routes.find(r =>
      r.method.toUpperCase() === method.toUpperCase() &&
      matchPath(r.path, routePath)
    );
    if (!matched) {
      return { status: 404, json: { error: `Route not found: ${method} ${routePath}` } };
    }
    return await runHandler(widgetId, matched, { method, path: routePath, body, query, headers });
  }

  return await runHandler(widgetId, route, { method, path: routePath, body, query, headers });
}

/**
 * Run a handler in the isolated-vm sandbox.
 */
async function runHandler(widgetId, route, req) {
  const ctx = createCtxAPI(widgetId, DB_URL);

  try {
    const result = await sandboxManager.execute(widgetId, route.handlerJS, req, ctx, {
      timeoutMs: 10000,
      memoryLimitMb: 64,
    });

    return result || { status: 200, json: {} };
  } catch (err) {
    if (err.message?.includes('Script execution timed out')) {
      return { status: 504, json: { error: 'Handler timed out (10s limit)' } };
    }
    throw err;
  }
}

/**
 * Simple path matching. Supports :param segments.
 */
function matchPath(pattern, actual) {
  const patternParts = pattern.replace(/^\//, '').split('/');
  const actualParts = actual.replace(/^\//, '').split('/');

  if (patternParts.length !== actualParts.length) return false;

  return patternParts.every((p, i) =>
    p.startsWith(':') || p === actualParts[i]
  );
}

// Start
startServer();
