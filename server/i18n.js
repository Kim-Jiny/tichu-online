const ko = require('./locales/ko.json');
const en = require('./locales/en.json');
const de = require('./locales/de.json');

const catalogs = { ko, en, de };
const DEFAULT_LOCALE = 'ko';

/**
 * Translate a message key for the given locale.
 * Supports simple {placeholder} interpolation.
 *
 * @param {string|null} locale - 'en', 'ko', 'de', or null (falls back to ko)
 * @param {string} key - message key from locales/*.json
 * @param {Object} [params] - optional interpolation values, e.g. { minutes: 5 }
 * @returns {string} translated message
 */
function t(locale, key, params) {
  // Pick catalog for the requested locale, falling back to ko for unknown/null
  // locales (old clients that never send a locale code).
  const catalog = catalogs[locale] || catalogs[DEFAULT_LOCALE];
  // Fallback chain for a missing key: locale's generic_error, then ko's
  // generic_error, then the raw key. We intentionally do NOT cross-fall back
  // to the ko translation of a missing key — users with en/de locales should
  // see a locale-appropriate generic message, not Korean.
  let msg = catalog[key];
  if (msg === undefined) {
    msg = catalog['generic_error'] ?? catalogs[DEFAULT_LOCALE]['generic_error'] ?? key;
  }
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      msg = msg.replace(`{${k}}`, v);
    }
  }
  return msg;
}

module.exports = { t };
