'use strict';

/**
 * Legacy strategy name kept for compatibility.
 *
 * The old sampled expectimax path was expensive and overlapped heavily with
 * the server's perfect-information view. Route it through the shared oracle
 * evaluator instead.
 */

module.exports = require('./oracle');
