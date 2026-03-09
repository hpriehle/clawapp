'use strict';

const { runJSON } = require('../exec');
const cache = require('../cache');
const config = require('../config');

module.exports = async function (fastify) {
  // GET /api/calendar/events?days=7&max=20&calendar=primary
  fastify.get('/api/calendar/events', async (request) => {
    const days = parseInt(request.query.days || '7', 10);
    const max = parseInt(request.query.max || '20', 10);
    const calendar = request.query.calendar || 'primary';

    const cacheKey = `cal:events:${calendar}:${days}:${max}`;
    const cached = cache.get(cacheKey);
    if (cached) return cached;

    const args = ['calendar', 'events', calendar, '--json', '--results-only', '--days', String(days), '--max', String(max)];
    const data = await runJSON('gog', args);

    const result = { events: data, fetchedAt: new Date().toISOString() };
    cache.set(cacheKey, result, config.cacheTTL.calendar);
    return result;
  });

  // GET /api/calendar/today?calendar=primary
  fastify.get('/api/calendar/today', async (request) => {
    const calendar = request.query.calendar || 'primary';

    const cacheKey = `cal:today:${calendar}`;
    const cached = cache.get(cacheKey);
    if (cached) return cached;

    const args = ['calendar', 'events', calendar, '--json', '--results-only', '--today'];
    const data = await runJSON('gog', args);

    const result = { events: data, fetchedAt: new Date().toISOString() };
    cache.set(cacheKey, result, config.cacheTTL.calendar);
    return result;
  });
};
