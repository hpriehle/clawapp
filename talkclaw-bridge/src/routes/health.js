'use strict';

module.exports = async function (fastify) {
  fastify.get('/api/health', { config: { skipAuth: true } }, async () => {
    return { status: 'ok', uptime: process.uptime() };
  });
};
