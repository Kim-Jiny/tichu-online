'use strict';

/**
 * Bot decision worker thread. Runs the expensive bot search (mighty
 * mixoracle/oracle/solver, tichu winrate monte-carlo) off the main event
 * loop so a 40-100ms decision no longer stalls every room's networking.
 *
 * Protocol (parent -> worker):  { id, gameType, botId, strat, state }
 *   state = game.serialize() (a JSON-safe snapshot; see MightyGame/TichuGame).
 * Protocol (worker -> parent):  { id, action }  or  { id, error }
 *
 * Only pure-computation modules are required here — no server singleton, DB,
 * WebSocket or lobby state (verified: bot modules require only deck/knowledge/
 * validator/logger). The worker is stateless between requests.
 */

const { parentPort } = require('worker_threads');
const MightyGame = require('../game/mighty/MightyGame');
const { decideMightyBotAction } = require('../game/mighty/MightyBot');
const TichuGame = require('../game/TichuGame');
const { decideBotAction } = require('../game/BotPlayer');

function decide(gameType, state, botId, strat) {
  if (gameType === 'mighty') {
    const game = MightyGame.reconstruct(state);
    return decideMightyBotAction(game, botId, strat);
  }
  if (gameType === 'tichu') {
    const game = TichuGame.reconstruct(state);
    return decideBotAction(game, botId, strat);
  }
  throw new Error(`botWorker: unsupported gameType ${gameType}`);
}

parentPort.on('message', (msg) => {
  const { id, gameType, botId, strat, state } = msg;
  const t0 = process.hrtime.bigint();
  try {
    const action = decide(gameType, state, botId, strat);
    const computeMs = Number(process.hrtime.bigint() - t0) / 1e6;
    parentPort.postMessage({ id, action: action || null, computeMs });
  } catch (e) {
    const computeMs = Number(process.hrtime.bigint() - t0) / 1e6;
    parentPort.postMessage({ id, error: (e && e.message) || String(e), computeMs });
  }
});
