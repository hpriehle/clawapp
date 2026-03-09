'use strict';

const config = {
  port: parseInt(process.env.BRIDGE_PORT || '3847', 10),
  host: process.env.BRIDGE_HOST || '0.0.0.0',
  token: process.env.BRIDGE_TOKEN || '',

  // Cache TTLs in milliseconds
  cacheTTL: {
    calendar: 5 * 60 * 1000,   // 5 minutes
    mail: 2 * 60 * 1000,       // 2 minutes
    system: 30 * 1000,          // 30 seconds
  },

  // gog CLI requires account and keyring password
  gogAccount: process.env.GOG_ACCOUNT || '',
  gogKeyringPassword: process.env.GOG_KEYRING_PASSWORD || '',
};

if (!config.token) {
  console.error('BRIDGE_TOKEN is required. Set it in .env or environment.');
  process.exit(1);
}

module.exports = config;
