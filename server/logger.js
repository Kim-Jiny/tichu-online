const isProduction = process.env.NODE_ENV === 'production';

function envFlag(name, defaultValue = false) {
  const raw = process.env[name];
  if (raw == null || raw === '') return defaultValue;
  return ['1', 'true', 'yes', 'on'].includes(String(raw).toLowerCase());
}

const verboseConnectionLogsEnabled = envFlag('VERBOSE_CONNECTION_LOGS', !isProduction);
const scoreDebugLogsEnabled = envFlag('ENABLE_SCORE_DEBUG_LOGS', !isProduction);
const adminAccessLogsEnabled = envFlag('ADMIN_ACCESS_LOGS', true);

function logVerboseConnection(message) {
  if (verboseConnectionLogsEnabled) {
    console.log(message);
  }
}

function logScoreDebug(message) {
  if (scoreDebugLogsEnabled) {
    console.log(message);
  }
}

function logAdminAccess(message) {
  if (adminAccessLogsEnabled) {
    console.log(message);
  }
}

module.exports = {
  logAdminAccess,
  logScoreDebug,
  logVerboseConnection,
  scoreDebugLogsEnabled,
  verboseConnectionLogsEnabled,
};
