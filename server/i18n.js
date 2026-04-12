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
  const catalog = catalogs[locale] || catalogs[DEFAULT_LOCALE];
  let msg = catalog[key] ?? catalogs[DEFAULT_LOCALE][key] ?? key;
  if (params) {
    for (const [k, v] of Object.entries(params)) {
      msg = msg.replace(`{${k}}`, v);
    }
  }
  return msg;
}

module.exports = { t };
