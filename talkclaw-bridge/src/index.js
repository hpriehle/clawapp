'use strict';

const path = require('path');
const fs = require('fs');
const config = require('./config');

const fastify = require('fastify')({ logger: true });

// Auth hook — skip for routes marked with skipAuth
fastify.addHook('onRequest', async (request, reply) => {
  if (request.routeOptions?.config?.skipAuth) return;

  const auth = request.headers.authorization;
  if (!auth || auth !== `Bearer ${config.token}`) {
    reply.code(401).send({ error: 'Unauthorized' });
  }
});

// Auto-load all route files from routes/
const routesDir = path.join(__dirname, 'routes');
for (const file of fs.readdirSync(routesDir)) {
  if (file.endsWith('.js')) {
    fastify.register(require(path.join(routesDir, file)));
  }
}

// Global error handler for route errors
fastify.setErrorHandler((error, request, reply) => {
  request.log.error(error);
  reply.code(500).send({
    error: error.message || 'Internal server error',
    ...(error.result ? { stderr: error.result.stderr } : {}),
  });
});

// Start server
fastify.listen({ port: config.port, host: config.host }, (err, address) => {
  if (err) {
    fastify.log.error(err);
    process.exit(1);
  }
  fastify.log.info(`TalkClaw Bridge listening on ${address}`);
});
