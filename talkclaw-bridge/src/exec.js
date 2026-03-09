'use strict';

const { execFile } = require('child_process');
const config = require('./config');

/**
 * Execute a command safely using execFile (no shell injection).
 * Returns { stdout, stderr, code }.
 */
function run(command, args, opts = {}) {
  const timeout = opts.timeout || 10000;

  // Inject GOG env vars if running gog
  const env = { ...process.env };
  if (command === 'gog' && config.gogAccount) {
    env.GOG_ACCOUNT = config.gogAccount;
  }
  if (command === 'gog' && config.gogKeyringPassword) {
    env.GOG_KEYRING_PASSWORD = config.gogKeyringPassword;
  }

  return new Promise((resolve) => {
    execFile(command, args, { timeout, env, maxBuffer: 1024 * 1024 }, (err, stdout, stderr) => {
      if (err && err.killed) {
        resolve({ stdout: '', stderr: 'Command timed out', code: -1 });
        return;
      }
      resolve({
        stdout: stdout || '',
        stderr: stderr || '',
        code: err ? err.code || 1 : 0,
      });
    });
  });
}

/**
 * Run a command and parse stdout as JSON.
 * Returns the parsed object or throws.
 */
async function runJSON(command, args, opts) {
  const result = await run(command, args, opts);
  if (result.code !== 0) {
    const err = new Error(`${command} failed (code ${result.code}): ${result.stderr}`);
    err.result = result;
    throw err;
  }
  return JSON.parse(result.stdout);
}

module.exports = { run, runJSON };
