'use strict';

const fs = require('fs');
const { run } = require('../exec');
const cache = require('../cache');
const config = require('../config');

function parseMeminfo() {
  const raw = fs.readFileSync('/proc/meminfo', 'utf8');
  const lines = {};
  for (const line of raw.split('\n')) {
    const match = line.match(/^(\w+):\s+(\d+)/);
    if (match) lines[match[1]] = parseInt(match[2], 10) * 1024; // kB to bytes
  }
  const total = lines.MemTotal || 0;
  const available = lines.MemAvailable || 0;
  const used = total - available;
  return {
    total_gb: +(total / 1e9).toFixed(1),
    used_gb: +(used / 1e9).toFixed(1),
    available_gb: +(available / 1e9).toFixed(1),
    percent: total > 0 ? +((used / total) * 100).toFixed(1) : 0,
  };
}

function parseLoadavg() {
  const raw = fs.readFileSync('/proc/loadavg', 'utf8');
  const parts = raw.trim().split(/\s+/);
  return [parseFloat(parts[0]), parseFloat(parts[1]), parseFloat(parts[2])];
}

module.exports = async function (fastify) {
  // GET /api/system/stats
  fastify.get('/api/system/stats', async () => {
    const cached = cache.get('system:stats');
    if (cached) return cached;

    const memory = parseMeminfo();
    const load = parseLoadavg();

    // Disk usage
    const dfResult = await run('df', ['-B1', '--output=size,used,avail', '/']);
    const dfLines = dfResult.stdout.trim().split('\n');
    let disk = { total_gb: 0, used_gb: 0, available_gb: 0, percent: 0 };
    if (dfLines.length >= 2) {
      const parts = dfLines[1].trim().split(/\s+/);
      const total = parseInt(parts[0], 10);
      const used = parseInt(parts[1], 10);
      disk = {
        total_gb: +(total / 1e9).toFixed(1),
        used_gb: +(used / 1e9).toFixed(1),
        available_gb: +(parseInt(parts[2], 10) / 1e9).toFixed(1),
        percent: total > 0 ? +((used / total) * 100).toFixed(1) : 0,
      };
    }

    // Uptime
    const uptimeRaw = fs.readFileSync('/proc/uptime', 'utf8');
    const uptimeSeconds = parseFloat(uptimeRaw.split(' ')[0]);

    const result = {
      load,
      memory,
      disk,
      uptime_seconds: Math.round(uptimeSeconds),
      uptime_days: +(uptimeSeconds / 86400).toFixed(1),
      fetchedAt: new Date().toISOString(),
    };

    cache.set('system:stats', result, config.cacheTTL.system);
    return result;
  });
};
