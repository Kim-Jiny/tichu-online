'use strict';

// Backward-compat alias: smart rollout was promoted to be the default
// rollout. Re-export so existing imports still work.
module.exports = require('./rollout');
