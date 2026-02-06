const { getCardValue, getCardRank } = require('./Deck');

// Card point values: 5=5pts, 10=10pts, K=10pts, Dragon=+25, Phoenix=-25
function getCardPoints(cardId) {
  const rank = getCardRank(cardId);
  if (rank === '5') return 5;
  if (rank === '10' || rank === 'K') return 10;
  if (cardId === 'special_dragon') return 25;
  if (cardId === 'special_phoenix') return -25;
  return 0;
}

function calculateTrickPoints(cards) {
  return cards.reduce((sum, cardId) => sum + getCardPoints(cardId), 0);
}

function calculateRoundScores(gameState) {
  // gameState: { finishOrder, teams, trickPiles, smallTichuDeclarations, largeTichuDeclarations }
  const { finishOrder, teams, trickPiles, smallTichuDeclarations, largeTichuDeclarations, playerCards } = gameState;
  // teams = { teamA: [pid1, pid3], teamB: [pid2, pid4] }

  const scores = { teamA: 0, teamB: 0 };

  // Check 1-2 finish (one team finishes 1st and 2nd)
  if (finishOrder.length >= 2) {
    const first = finishOrder[0];
    const second = finishOrder[1];
    const firstTeam = getTeam(first, teams);
    const secondTeam = getTeam(second, teams);

    if (firstTeam === secondTeam) {
      // 1-2 finish: 200 points for that team, ignore card points
      scores[firstTeam] = 200;
      scores[firstTeam === 'teamA' ? 'teamB' : 'teamA'] = 0;
      applyTichuBonuses(scores, smallTichuDeclarations, largeTichuDeclarations, finishOrder, teams);
      return scores;
    }
  }

  // Normal scoring: count card points in trick piles with last-player transfer rules
  // Last player's remaining hand cards go to the opposing team
  // Last player's trick pile goes to the first finisher's team
  const lastPlayer = finishOrder.length >= 3 ? getLastPlayer(finishOrder, teams) : null;
  const firstPlayer = finishOrder[0];
  const firstTeam = getTeam(firstPlayer, teams);

  // Count trick pile points per player, then reassign last player's pile to first finisher
  for (const [playerId, cards] of Object.entries(trickPiles)) {
    const pts = calculateTrickPoints(cards);
    if (lastPlayer && playerId === lastPlayer) {
      scores[firstTeam] += pts;
    } else {
      const team = getTeam(playerId, teams);
      scores[team] += pts;
    }
  }

  // Last player's remaining hand cards go to opposing team
  if (lastPlayer && playerCards[lastPlayer]) {
    const lastCards = playerCards[lastPlayer];
    const lastTeam = getTeam(lastPlayer, teams);
    const oppTeam = lastTeam === 'teamA' ? 'teamB' : 'teamA';
    scores[oppTeam] += calculateTrickPoints(lastCards);
  }

  applyTichuBonuses(scores, smallTichuDeclarations, largeTichuDeclarations, finishOrder, teams);
  return scores;
}

function applyTichuBonuses(scores, smallTichuDeclarations, largeTichuDeclarations, finishOrder, teams) {
  // Small Tichu: +100 if first, -100 otherwise
  for (const playerId of (smallTichuDeclarations || [])) {
    const team = getTeam(playerId, teams);
    if (finishOrder[0] === playerId) {
      scores[team] += 100;
    } else {
      scores[team] -= 100;
    }
  }

  // Large Tichu: +200 if first, -200 otherwise
  for (const playerId of (largeTichuDeclarations || [])) {
    const team = getTeam(playerId, teams);
    if (finishOrder[0] === playerId) {
      scores[team] += 200;
    } else {
      scores[team] -= 200;
    }
  }
}

function getTeam(playerId, teams) {
  if (teams.teamA.includes(playerId)) return 'teamA';
  if (teams.teamB.includes(playerId)) return 'teamB';
  return null;
}

function getLastPlayer(finishOrder, teams) {
  const allPlayers = [...teams.teamA, ...teams.teamB];
  // If finishOrder already contains all players, the last finisher is the last player.
  if (finishOrder.length === allPlayers.length) {
    return finishOrder[finishOrder.length - 1] || null;
  }
  // Otherwise, find the one not in finish order yet.
  for (const p of allPlayers) {
    if (!finishOrder.includes(p)) return p;
  }
  return null;
}

module.exports = { getCardPoints, calculateTrickPoints, calculateRoundScores };
