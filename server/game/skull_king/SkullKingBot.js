/**
 * Skull King Bot - AI decision making
 */

const { getCardInfo, CARD_TYPE } = require('./SkullKingDeck');

/**
 * Main entry point: decide bot action based on game state
 */
function decideSKBotAction(game, botId) {
  if (!game || !game.playerIds.includes(botId)) return null;

  if (game.state === 'bidding' && game.bids[botId] === null) {
    return decideBid(game, botId);
  }

  if (game.state === 'playing' && game.currentPlayer === botId) {
    return decidePlay(game, botId);
  }

  return null;
}

function decideBid(game, botId) {
  const hand = game.hands[botId] || [];
  let estimatedTricks = 0;

  for (const cardId of hand) {
    const info = getCardInfo(cardId);
    if (!info) continue;

    if (info.type === CARD_TYPE.SKULL_KING) {
      estimatedTricks += 1;
    } else if (info.type === CARD_TYPE.PIRATE) {
      estimatedTricks += 0.8;
    } else if (info.type === CARD_TYPE.MERMAID) {
      estimatedTricks += 0.7;
    } else if (info.type === CARD_TYPE.TIGRESS) {
      estimatedTricks += 0.5;
    } else if (info.type === CARD_TYPE.NUMBER) {
      if (info.suit === 'black' && info.value >= 10) {
        estimatedTricks += 0.7;
      } else if (info.suit === 'black' && info.value >= 7) {
        estimatedTricks += 0.4;
      } else if (info.value >= 12) {
        estimatedTricks += 0.3;
      }
    }
    // Escapes and low cards contribute 0
  }

  const bid = Math.round(estimatedTricks);
  return { type: 'submit_bid', bid: Math.min(bid, game.round) };
}

function decidePlay(game, botId) {
  const legalCards = game.getLegalCards(botId);
  if (legalCards.length === 0) return null;

  const bid = game.bids[botId] || 0;
  const tricksWon = game.tricks[botId] || 0;
  const tricksNeeded = bid - tricksWon;
  const tricksRemaining = (game.hands[botId] || []).length;

  // Leading the trick
  if (game.currentTrick.length === 0) {
    return decideLeadCard(legalCards, tricksNeeded, tricksRemaining);
  }

  // Following
  return decideFollowCard(game, botId, legalCards, tricksNeeded);
}

function decideLeadCard(legalCards, tricksNeeded, tricksRemaining) {
  const infos = legalCards.map(id => ({ id, info: getCardInfo(id) }));

  if (tricksNeeded > 0) {
    // Need tricks: lead strong
    // Prefer SK > Pirate > high black > high number
    const sk = infos.find(c => c.info.type === CARD_TYPE.SKULL_KING);
    if (sk) return makePlayAction(sk.id, sk.info);

    const pirate = infos.find(c => c.info.type === CARD_TYPE.PIRATE);
    if (pirate) return makePlayAction(pirate.id, pirate.info);

    const tigress = infos.find(c => c.info.type === CARD_TYPE.TIGRESS);
    if (tigress && tricksNeeded >= 1) return makePlayAction(tigress.id, tigress.info, 'pirate');

    // High numbered cards
    const numbers = infos
      .filter(c => c.info.type === CARD_TYPE.NUMBER)
      .sort((a, b) => {
        if (a.info.suit === 'black' && b.info.suit !== 'black') return -1;
        if (a.info.suit !== 'black' && b.info.suit === 'black') return 1;
        return b.info.value - a.info.value;
      });
    if (numbers.length > 0) return makePlayAction(numbers[0].id, numbers[0].info);
  } else if (tricksNeeded <= 0) {
    // Already met or exceeded bid: play weak
    const escapes = infos.filter(c => c.info.type === CARD_TYPE.ESCAPE);
    if (escapes.length > 0) return makePlayAction(escapes[0].id, escapes[0].info);

    const tigress = infos.find(c => c.info.type === CARD_TYPE.TIGRESS);
    if (tigress) return makePlayAction(tigress.id, tigress.info, 'escape');

    // Lowest number
    const numbers = infos
      .filter(c => c.info.type === CARD_TYPE.NUMBER)
      .sort((a, b) => a.info.value - b.info.value);
    if (numbers.length > 0) return makePlayAction(numbers[0].id, numbers[0].info);
  }

  // Fallback
  return makePlayAction(legalCards[0], getCardInfo(legalCards[0]));
}

function decideFollowCard(game, botId, legalCards, tricksNeeded) {
  const infos = legalCards.map(id => ({ id, info: getCardInfo(id) }));

  // Analyze what's on the table
  const trickCards = game.currentTrick.map(p => ({ ...p, info: getCardInfo(p.cardId) }));
  const hasSK = trickCards.some(p => p.info && p.info.type === CARD_TYPE.SKULL_KING);
  const hasPirate = trickCards.some(p => p.info && (p.info.type === CARD_TYPE.PIRATE ||
    (p.info.type === CARD_TYPE.TIGRESS && p.tigressChoice === 'pirate')));
  const hasMermaid = trickCards.some(p => p.info && p.info.type === CARD_TYPE.MERMAID);

  // Helper: play weak card to dump the trick
  const playWeak = () => {
    const escapes = infos.filter(c => c.info.type === CARD_TYPE.ESCAPE);
    if (escapes.length > 0) return makePlayAction(escapes[0].id, escapes[0].info);
    const tigress = infos.find(c => c.info.type === CARD_TYPE.TIGRESS);
    if (tigress) return makePlayAction(tigress.id, tigress.info, 'escape');
    const numbers = infos
      .filter(c => c.info.type === CARD_TYPE.NUMBER)
      .sort((a, b) => a.info.value - b.info.value);
    if (numbers.length > 0) return makePlayAction(numbers[0].id, numbers[0].info);
    return null;
  };

  // For zero-bid defense, preserve escapes if a special lead already guarantees a loss.
  const playSafeLosingDump = () => {
    const dumpScore = (card) => {
      if (card.info.type === CARD_TYPE.NUMBER) {
        return (card.info.suit === 'black' ? 100 : 0) + (card.info.value || 0);
      }
      if (card.info.type === CARD_TYPE.MERMAID) return 70;
      if (card.info.type === CARD_TYPE.PIRATE) return 60;
      if (card.info.type === CARD_TYPE.TIGRESS) return 50;
      if (card.info.type === CARD_TYPE.ESCAPE) return -100;
      if (card.info.type === CARD_TYPE.SKULL_KING) return -200;
      return 0;
    };

    if (hasPirate) {
      const safeDump = infos
        .filter(c => c.info.type !== CARD_TYPE.SKULL_KING && c.info.type !== CARD_TYPE.ESCAPE)
        .sort((a, b) => dumpScore(b) - dumpScore(a));
      if (safeDump.length > 0) {
        const card = safeDump[0];
        const tigressChoice = card.info.type === CARD_TYPE.TIGRESS ? 'pirate' : null;
        return makePlayAction(card.id, card.info, tigressChoice);
      }
    }

    if (hasSK) {
      const safeDump = infos
        .filter(c => c.info.type !== CARD_TYPE.MERMAID && c.info.type !== CARD_TYPE.ESCAPE)
        .sort((a, b) => dumpScore(b) - dumpScore(a));
      if (safeDump.length > 0) {
        const card = safeDump[0];
        const tigressChoice = card.info.type === CARD_TYPE.TIGRESS ? 'pirate' : null;
        return makePlayAction(card.id, card.info, tigressChoice);
      }
    }

    return null;
  };

  if (tricksNeeded > 0) {
    // Need to win this trick

    // SK on the table → play mermaid to capture (+50 bonus)
    if (hasSK) {
      const mermaid = infos.find(c => c.info.type === CARD_TYPE.MERMAID);
      if (mermaid) return makePlayAction(mermaid.id, mermaid.info);
      // Can't beat SK without mermaid → dump weak
      const weak = playWeak();
      if (weak) return weak;
    }

    // Pirate on the table → need SK to beat it (or mermaid won't help here)
    if (hasPirate && !hasSK) {
      const sk = infos.find(c => c.info.type === CARD_TYPE.SKULL_KING);
      if (sk) return makePlayAction(sk.id, sk.info);
      // Can't beat pirate without SK → dump weak
      const weak = playWeak();
      if (weak) return weak;
    }

    // Mermaid on the table → pirate beats it
    if (hasMermaid && !hasSK && !hasPirate) {
      const pirate = infos.find(c => c.info.type === CARD_TYPE.PIRATE);
      if (pirate) return makePlayAction(pirate.id, pirate.info);
      const tigress = infos.find(c => c.info.type === CARD_TYPE.TIGRESS);
      if (tigress) return makePlayAction(tigress.id, tigress.info, 'pirate');
    }

    // No special on table (or only numbers) → play strong
    if (!hasSK && !hasPirate && !hasMermaid) {
      const sk = infos.find(c => c.info.type === CARD_TYPE.SKULL_KING);
      if (sk) return makePlayAction(sk.id, sk.info);
      const pirate = infos.find(c => c.info.type === CARD_TYPE.PIRATE);
      if (pirate) return makePlayAction(pirate.id, pirate.info);
      const tigress = infos.find(c => c.info.type === CARD_TYPE.TIGRESS);
      if (tigress) return makePlayAction(tigress.id, tigress.info, 'pirate');
    }

    // Play high number to try to win
    const numbers = infos
      .filter(c => c.info.type === CARD_TYPE.NUMBER)
      .sort((a, b) => {
        if (a.info.suit === 'black' && b.info.suit !== 'black') return -1;
        if (a.info.suit !== 'black' && b.info.suit === 'black') return 1;
        return b.info.value - a.info.value;
      });
    if (numbers.length > 0) return makePlayAction(numbers[0].id, numbers[0].info);
  } else {
    // Don't want more tricks: dump weak
    const safeDump = playSafeLosingDump();
    if (safeDump) return safeDump;
    const weak = playWeak();
    if (weak) return weak;
  }

  return makePlayAction(legalCards[0], getCardInfo(legalCards[0]));
}

function makePlayAction(cardId, info, tigressChoice) {
  const action = { type: 'play_card', cardId };
  if (info && info.type === CARD_TYPE.TIGRESS) {
    action.tigressChoice = tigressChoice || 'escape';
  }
  return action;
}

module.exports = { decideSKBotAction };
