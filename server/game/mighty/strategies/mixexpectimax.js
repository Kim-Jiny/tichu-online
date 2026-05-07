'use strict';

// Legacy compatibility alias. The public mix strategy now lives in
// `mixoracle`, but older saved bot configs may still request this name.
module.exports = require('./mixoracle');
