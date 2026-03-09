'use strict';

const { runJSON } = require('../exec');
const cache = require('../cache');
const config = require('../config');

module.exports = async function (fastify) {
  // GET /api/mail/unread?max=10
  fastify.get('/api/mail/unread', async (request) => {
    const max = parseInt(request.query.max || '10', 10);

    const cacheKey = `mail:unread:${max}`;
    const cached = cache.get(cacheKey);
    if (cached) return cached;

    const args = ['gmail', 'search', 'is:unread', '--json', '--results-only', '--max', String(max)];
    const data = await runJSON('gog', args);

    const result = { threads: data, fetchedAt: new Date().toISOString() };
    cache.set(cacheKey, result, config.cacheTTL.mail);
    return result;
  });

  // GET /api/mail/search?q=from:someone&max=10
  fastify.get('/api/mail/search', async (request) => {
    const q = request.query.q;
    if (!q) return { error: 'Missing q parameter', threads: [] };

    const max = parseInt(request.query.max || '10', 10);

    const cacheKey = `mail:search:${q}:${max}`;
    const cached = cache.get(cacheKey);
    if (cached) return cached;

    const args = ['gmail', 'search', q, '--json', '--results-only', '--max', String(max)];
    const data = await runJSON('gog', args);

    const result = { threads: data, fetchedAt: new Date().toISOString() };
    cache.set(cacheKey, result, config.cacheTTL.mail);
    return result;
  });
};
