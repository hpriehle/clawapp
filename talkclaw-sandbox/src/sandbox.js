'use strict';

const ivm = require('isolated-vm');

/**
 * Manages V8 isolates for widget route handler execution.
 * Each widget gets its own isolate — fully separate heaps, no shared memory.
 */
class SandboxManager {
  constructor() {
    // widgetId -> { isolate, context }
    this.isolates = new Map();
  }

  /**
   * Execute a handler function in the widget's sandbox.
   *
   * @param {string} widgetId
   * @param {string} handlerJS - The handler function body
   * @param {object} req - { method, path, body, query, headers }
   * @param {object} ctx - The ctx API object (db, fetch, kv, env)
   * @param {object} opts - { timeoutMs, memoryLimitMb }
   * @returns {Promise<{ status: number, json: any }>}
   */
  async execute(widgetId, handlerJS, req, ctx, opts = {}) {
    const { timeoutMs = 10000, memoryLimitMb = 64 } = opts;

    // Create isolate if needed
    if (!this.isolates.has(widgetId)) {
      const isolate = new ivm.Isolate({ memoryLimit: memoryLimitMb });
      const context = await isolate.createContext();

      // Set up global object
      const jail = context.global;
      await jail.set('global', jail.derefInto());

      // Console.log bridge
      await jail.set('_log', new ivm.Callback((...args) => {
        console.log(`[widget:${widgetId}]`, ...args);
      }));

      await context.eval(`
        const console = {
          log: (...args) => _log(...args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a))),
          error: (...args) => _log('ERROR:', ...args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a))),
          warn: (...args) => _log('WARN:', ...args.map(a => typeof a === 'object' ? JSON.stringify(a) : String(a))),
        };
      `);

      this.isolates.set(widgetId, { isolate, context });
    }

    const { context } = this.isolates.get(widgetId);
    const jail = context.global;

    // Inject req as JSON string
    await jail.set('_reqJSON', JSON.stringify(req));

    // Inject ctx callbacks
    await jail.set('_ctxDbQuery', new ivm.Callback((queryStr, paramsStr) => {
      // Synchronous bridge — actual async DB calls happen through a different mechanism
      // For now, return a promise-like structure
      return ctx.db.querySync(queryStr, paramsStr ? JSON.parse(paramsStr) : []);
    }));

    await jail.set('_ctxKvGet', new ivm.Callback((key) => {
      return ctx.kv.getSync(key);
    }));

    await jail.set('_ctxKvSet', new ivm.Callback((key, valueStr) => {
      ctx.kv.setSync(key, valueStr);
    }));

    await jail.set('_ctxFetch', new ivm.Callback((url, optsStr) => {
      return ctx.fetch.fetchSync(url, optsStr ? JSON.parse(optsStr) : {});
    }));

    await jail.set('_ctxEnv', new ivm.Callback((key) => {
      return ctx.env.get(key);
    }));

    // Build and execute the handler wrapper
    // The handler receives (req, ctx) and should return { status, json }
    const wrapperCode = `
      (function() {
        const req = JSON.parse(_reqJSON);

        const ctx = {
          db: {
            query: (sql, params) => {
              const result = _ctxDbQuery(sql, params ? JSON.stringify(params) : undefined);
              return typeof result === 'string' ? JSON.parse(result) : result;
            }
          },
          kv: {
            get: (key) => {
              const result = _ctxKvGet(key);
              return result ? JSON.parse(result) : null;
            },
            set: (key, value) => {
              _ctxKvSet(key, JSON.stringify(value));
            }
          },
          fetch: (url, opts) => {
            const result = _ctxFetch(url, opts ? JSON.stringify(opts) : undefined);
            return typeof result === 'string' ? JSON.parse(result) : result;
          },
          env: {
            get: (key) => _ctxEnv(key)
          }
        };

        try {
          const handlerFn = new Function('req', 'ctx', ${JSON.stringify(handlerJS)});
          const result = handlerFn(req, ctx);
          return JSON.stringify(result || { status: 200, json: {} });
        } catch (err) {
          return JSON.stringify({
            status: 500,
            json: { error: err.message, stack: err.stack }
          });
        }
      })()
    `;

    const resultStr = await context.eval(wrapperCode, { timeout: timeoutMs });
    return JSON.parse(resultStr);
  }

  /**
   * Dispose a widget's isolate.
   */
  dispose(widgetId) {
    const entry = this.isolates.get(widgetId);
    if (entry) {
      try {
        entry.isolate.dispose();
      } catch {}
      this.isolates.delete(widgetId);
    }
  }

  /**
   * Dispose all isolates.
   */
  disposeAll() {
    for (const [id] of this.isolates) {
      this.dispose(id);
    }
  }
}

module.exports = { SandboxManager };
