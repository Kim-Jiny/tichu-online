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
  const infos = hand.map(id => getCardInfo(id)).filter(Boolean);

  // Context for expansion synergy
  const hasWhiteWhale = infos.some(i => i.type === CARD_TYPE.WHITE_WHALE);
  const highNumbers = infos.filter(i =>
    i.type === CARD_TYPE.NUMBER &&
    ((i.suit === 'black' && i.value >= 9) || i.value >= 12)
  );
  // White Whale synergy: nullifies opponents' specials, so high numbers become
  // much more likely to win when we also hold White Whale.
  const whiteWhaleSynergy = hasWhiteWhale && highNumbers.length >= 1;

  let estimatedTricks = 0;
  for (const info of infos) {
    if (info.type === CARD_TYPE.SKULL_KING) {
      estimatedTricks += 1;
    } else if (info.type === CARD_TYPE.PIRATE) {
      estimatedTricks += 0.8;
    } else if (info.type === CARD_TYPE.MERMAID) {
      estimatedTricks += 0.7;
    } else if (info.type === CARD_TYPE.TIGRESS) {
      estimatedTricks += 0.5;
    } else if (info.type === CARD_TYPE.WHITE_WHALE) {
      // With high numbers in hand, White Whale nullifies opponents' specials
      // and our number wins → much more reliable trick.
      estimatedTricks += whiteWhaleSynergy ? 0.5 : 0.15;
    } else if (info.type === CARD_TYPE.NUMBER) {
      if (info.suit === 'black' && info.value >= 10) {
        estimatedTricks += whiteWhaleSynergy ? 0.85 : 0.7;
      } else if (info.suit === 'black' && info.value >= 7) {
        estimatedTricks += whiteWhaleSynergy ? 0.5 : 0.4;
      } else if (info.value >= 12) {
        estimatedTricks += whiteWhaleSynergy ? 0.45 : 0.3;
      }
    }
    // Escapes, low numbers, Kraken, and Loot contribute 0 to trick count.
    // Loot adds +20 bonus if bid is met, but doesn't win a trick itself.
  }

  const bid = Math.round(estimatedTricks);
  return { type: 'submit_bid', bid: Math.min(Math.max(bid, 0), game.round) };
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
    // Already met or exceeded bid: play weak.
    // Preserve Kraken/White Whale for follow-phase denial of high-stakes tricks
    // (SK+pirate / SK+mermaid). Dump simpler cards first.
    const loot = infos.find(c => c.info.type === CARD_TYPE.LOOT);
    if (loot) return makePlayAction(loot.id, loot.info);

    const escapes = infos.filter(c => c.info.type === CARD_TYPE.ESCAPE);
    if (escapes.length > 0) return makePlayAction(escapes[0].id, escapes[0].info);

    const tigress = infos.find(c => c.info.type === CARD_TYPE.TIGRESS);
    if (tigress) return makePlayAction(tigress.id, tigress.info, 'escape');

    // Lowest number before burning Kraken/White Whale (keep those as denial tools)
    const numbers = infos
      .filter(c => c.info.type === CARD_TYPE.NUMBER)
      .sort((a, b) => a.info.value - b.info.value);
    if (numbers.length > 0) return makePlayAction(numbers[0].id, numbers[0].info);

    const kraken = infos.find(c => c.info.type === CARD_TYPE.KRAKEN);
    if (kraken) return makePlayAction(kraken.id, kraken.info);

    const whale = infos.find(c => c.info.type === CARD_TYPE.WHITE_WHALE);
    if (whale) return makePlayAction(whale.id, whale.info);
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

  // Helper: determine if a number card would win against the current trick
  const wouldCardWin = (card) => {
    // Find lead suit
    let leadSuit = null;
    for (const t of trickCards) {
      if (t.info && t.info.type === CARD_TYPE.NUMBER) { leadSuit = t.info.suit; break; }
    }
    const numbered = trickCards.filter(t => t.info && t.info.type === CARD_TYPE.NUMBER);
    const trumpOnTable = numbered.filter(t => t.info.suit === 'black');
    let winSuit, winValue;
    if (trumpOnTable.length > 0) {
      winSuit = 'black';
      winValue = Math.max(...trumpOnTable.map(t => t.info.value));
    } else {
      const leadOnTable = numbered.filter(t => t.info.suit === leadSuit);
      if (leadOnTable.length > 0) {
        winSuit = leadSuit;
        winValue = Math.max(...leadOnTable.map(t => t.info.value));
      } else {
        return false;
      }
    }
    if (winSuit === 'black') {
      return card.info.suit === 'black' && card.info.value > winValue;
    }
    if (card.info.suit === 'black') return true;
    if (card.info.suit === winSuit && card.info.value > winValue) return true;
    return false;
  };

  // High-stakes trick: SK + pirate (+30/pirate) or SK + mermaid (+50) is on the
  // table. Voiding this with a Kraken is strictly better than a normal dump
  // because it denies opponents the bonus too.
  const highStakesTrick = (hasSK && hasPirate) || (hasSK && hasMermaid);

  // Helper: play weak card to dump the trick (highest loser first)
  const playWeak = () => {
    // High-stakes denial: a big-bonus play is forming on the table.
    // Kraken voids the whole trick (best denial). White Whale nullifies
    // specials, turning the trick into a number contest that awards no
    // SK/pirate/mermaid bonus (second-best denial).
    if (highStakesTrick) {
      const krakenBlock = infos.find(c => c.info.type === CARD_TYPE.KRAKEN);
      if (krakenBlock) return makePlayAction(krakenBlock.id, krakenBlock.info);
      const whaleBlock = infos.find(c => c.info.type === CARD_TYPE.WHITE_WHALE);
      if (whaleBlock) return makePlayAction(whaleBlock.id, whaleBlock.info);
    }
    // Loot never wins a trick → safest dump, and if we still win the trick
    // it grants a bonus to us.
    const loot = infos.find(c => c.info.type === CARD_TYPE.LOOT);
    if (loot) return makePlayAction(loot.id, loot.info);
    const escapes = infos.filter(c => c.info.type === CARD_TYPE.ESCAPE);
    if (escapes.length > 0) return makePlayAction(escapes[0].id, escapes[0].info);
    // Kraken voids the trick → great dump when we don't want any trick
    const kraken = infos.find(c => c.info.type === CARD_TYPE.KRAKEN);
    if (kraken) return makePlayAction(kraken.id, kraken.info);
    const tigress = infos.find(c => c.info.type === CARD_TYPE.TIGRESS);
    if (tigress) return makePlayAction(tigress.id, tigress.info, 'escape');
    // White Whale is volatile: if we have a weak hand it's often a dump too
    const whale = infos.find(c => c.info.type === CARD_TYPE.WHITE_WHALE);
    if (whale) return makePlayAction(whale.id, whale.info);
    const numbers = infos.filter(c => c.info.type === CARD_TYPE.NUMBER);
    if (numbers.length === 0) return null;
    // If special cards are winning, all numbers lose → play highest
    if (hasSK || hasPirate || hasMermaid) {
      numbers.sort((a, b) => b.info.value - a.info.value);
      return makePlayAction(numbers[0].id, numbers[0].info);
    }
    // Split into losers and winners
    const losers = numbers.filter(c => !wouldCardWin(c));
    const winners = numbers.filter(c => wouldCardWin(c));
    if (losers.length > 0) {
      // Play highest loser
      losers.sort((a, b) => b.info.value - a.info.value);
      return makePlayAction(losers[0].id, losers[0].info);
    }
    // All cards would win → play lowest to minimize damage
    winners.sort((a, b) => a.info.value - b.info.value);
    return makePlayAction(winners[0].id, winners[0].info);
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
    // Don't want more tricks: dump weak.
    // High-stakes denial: a big-bonus special trick (SK+pirate or SK+mermaid)
    // is forming. Voiding with Kraken or nullifying with White Whale is
    // strictly better than any normal dump because the opponent is denied the
    // bonus too. Fire this before playSafeLosingDump which would otherwise
    // spend a high trump as "safe".
    if (highStakesTrick) {
      const krakenBlock = infos.find(c => c.info.type === CARD_TYPE.KRAKEN);
      if (krakenBlock) return makePlayAction(krakenBlock.id, krakenBlock.info);
      const whaleBlock = infos.find(c => c.info.type === CARD_TYPE.WHITE_WHALE);
      if (whaleBlock) return makePlayAction(whaleBlock.id, whaleBlock.info);
    }
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
