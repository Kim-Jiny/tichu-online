'use strict';

/**
 * Legacy strategy name kept for compatibility.
 *
 * The previous "smart" expectimax sampled many hidden worlds even though the
 * live server bot already has full state. Reuse the cheaper oracle evaluator.
 */

module.exports = require('./oracle');
