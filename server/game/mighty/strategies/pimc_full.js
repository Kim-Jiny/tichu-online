'use strict';

/**
 * Legacy strategy name kept for compatibility.
 *
 * The old full PIMC stack is collapsed into the shared oracle evaluator to
 * reduce CPU load and keep all full-information logic in one place.
 */

module.exports = require('./oracle');
