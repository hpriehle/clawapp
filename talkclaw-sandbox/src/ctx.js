'use strict';

const { Pool } = require('pg');

// Connection pool cache: dbUrl -> Pool
const pools = new Map();

function getPool(dbUrl) {
  if (!pools.has(dbUrl)) {
    pools.set(dbUrl, new Pool({
      connectionString: dbUrl,
      max: 10,
      idleTimeoutMillis: 30000,
    }));
  }
  return pools.get(dbUrl);
}

/**
 * Create the ctx API object for a widget's sandbox execution.
 * All methods are synchronous-looking but use pre-fetched data or
 * synchronous bridges via isolated-vm callbacks.
 *
 * @param {string} widgetId
 * @param {string} dbUrl
 * @returns {{ db, kv, fetch, env }}
 */
function createCtxAPI(widgetId, dbUrl) {
  const pool = getPool(dbUrl);

  return {
    db: {
      /**
       * Synchronous DB query bridge for isolated-vm.
       * Executes a parameterized query against the widget's scoped schema.
       * Returns JSON string of rows.
       */
      querySync(sql, params) {
        // We use deasync pattern: isolated-vm callbacks must be synchronous
        // but pg is async. We use a shared-state approach.
        let done = false;
        let result = null;
        let error = null;

        pool.query(sql, params || [])
          .then(res => { result = JSON.stringify(res.rows); done = true; })
          .catch(err => { error = err; done = true; });

        // Spin-wait (isolated-vm callbacks run on main thread)
        // This is intentional — isolated-vm requires sync callbacks
        const start = Date.now();
        while (!done) {
          if (Date.now() - start > 5000) {
            throw new Error('DB query timed out (5s)');
          }
          // Allow event loop to process
          try {
            require('child_process').execSync('sleep 0.001', { stdio: 'ignore' });
          } catch {}
        }

        if (error) {
          throw new Error(`DB error: ${error.message}`);
        }
        return result;
      },
    },

    kv: {
      /**
       * Get a value from the widget's KV store.
       * Returns JSON string or null.
       */
      getSync(key) {
        let done = false;
        let result = null;
        let error = null;

        pool.query(
          'SELECT value FROM widget_kv WHERE widget_id = $1 AND key = $2',
          [widgetId, key]
        )
          .then(res => {
            result = res.rows.length > 0 ? JSON.stringify(res.rows[0].value) : null;
            done = true;
          })
          .catch(err => { error = err; done = true; });

        const start = Date.now();
        while (!done) {
          if (Date.now() - start > 5000) throw new Error('KV get timed out');
          try { require('child_process').execSync('sleep 0.001', { stdio: 'ignore' }); } catch {}
        }

        if (error) throw new Error(`KV error: ${error.message}`);
        return result;
      },

      /**
       * Set a value in the widget's KV store (upsert).
       */
      setSync(key, valueStr) {
        let done = false;
        let error = null;

        pool.query(
          `INSERT INTO widget_kv (id, widget_id, key, value, updated_at)
           VALUES (gen_random_uuid(), $1, $2, $3::jsonb, NOW())
           ON CONFLICT (widget_id, key)
           DO UPDATE SET value = $3::jsonb, updated_at = NOW()`,
          [widgetId, key, valueStr]
        )
          .then(() => { done = true; })
          .catch(err => { error = err; done = true; });

        const start = Date.now();
        while (!done) {
          if (Date.now() - start > 5000) throw new Error('KV set timed out');
          try { require('child_process').execSync('sleep 0.001', { stdio: 'ignore' }); } catch {}
        }

        if (error) throw new Error(`KV error: ${error.message}`);
      },
    },

    fetch: {
      /**
       * Synchronous HTTP fetch bridge.
       * Limited to GET/POST with JSON responses.
       */
      fetchSync(url, opts) {
        let done = false;
        let result = null;
        let error = null;

        const fetchOpts = {
          method: (opts && opts.method) || 'GET',
          headers: (opts && opts.headers) || {},
        };

        if (opts && opts.body) {
          fetchOpts.body = typeof opts.body === 'string' ? opts.body : JSON.stringify(opts.body);
          if (!fetchOpts.headers['Content-Type']) {
            fetchOpts.headers['Content-Type'] = 'application/json';
          }
        }

        globalThis.fetch(url, fetchOpts)
          .then(res => res.text())
          .then(text => { result = text; done = true; })
          .catch(err => { error = err; done = true; });

        const start = Date.now();
        while (!done) {
          if (Date.now() - start > 8000) throw new Error('Fetch timed out (8s)');
          try { require('child_process').execSync('sleep 0.001', { stdio: 'ignore' }); } catch {}
        }

        if (error) throw new Error(`Fetch error: ${error.message}`);
        return result;
      },
    },

    env: {
      /**
       * Get an environment variable. Only exposes WIDGET_ prefixed vars.
       */
      get(key) {
        // Only allow widget-scoped env vars for security
        const prefixed = key.startsWith('WIDGET_') ? key : `WIDGET_${key}`;
        return process.env[prefixed] || null;
      },
    },
  };
}

/**
 * Cleanup all pools on shutdown.
 */
async function closePools() {
  for (const [, pool] of pools) {
    await pool.end();
  }
  pools.clear();
}

module.exports = { createCtxAPI, closePools };
