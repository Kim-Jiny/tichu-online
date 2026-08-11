/**
 * What the bot hands its partner in the exchange.
 *
 * The rule is short: Dragon, else Phoenix, else the highest number card. It
 * used to be a score that weighed strength against keeping one's own pairs
 * together, and the weighing came out wrong — a King taken from KK scored
 * below a loose 10, so the partner got the 10 and the pair stayed home.
 *
 * The hands below are deliberately free of long straights. With a
 * 2-3-4-5-6…J-Q hand every low card counts as "in a plan", the spare King
 * looks cheap to give away, and the thing being tested never shows.
 *
 * Run: node server/test_bot_exchange.js
 */
const { selectExchangeCards } = require('./game/BotPlayer');

let failures = 0;
const check = (label, cond, detail = '') => {
  console.log(`${cond ? '  ok  ' : '  FAIL'} ${label}${!cond && detail ? ` — ${detail}` : ''}`);
  if (!cond) failures++;
};

const give = (cards) => selectExchangeCards(cards);

console.log('\n[the partner gets the best card in hand]');

{
  const hand = ['spade_K', 'heart_K', 'club_10', 'spade_Q', 'heart_Q',
    'club_8', 'diamond_8', 'spade_6', 'heart_6', 'club_4',
    'diamond_4', 'spade_2', 'heart_2', 'diamond_J'];
  const out = give(hand);
  check('a King out of a pair beats a loose 10',
    out.partner.endsWith('_K'), `gave ${out.partner}`);
}

{
  const hand = ['spade_A', 'heart_A', 'club_10', 'spade_Q', 'heart_Q',
    'club_8', 'diamond_8', 'spade_6', 'heart_6', 'club_4',
    'diamond_4', 'spade_2', 'heart_2', 'diamond_J'];
  const out = give(hand);
  check('so does an Ace out of a pair',
    out.partner.endsWith('_A'), `gave ${out.partner}`);
}

{
  const hand = ['spade_A', 'heart_A', 'spade_K', 'heart_K', 'club_10',
    'club_8', 'diamond_8', 'spade_6', 'heart_6', 'club_4',
    'diamond_4', 'spade_2', 'heart_2', 'diamond_J'];
  const out = give(hand);
  check('with both pairs it is the Ace, not the King',
    out.partner.endsWith('_A'), `gave ${out.partner}`);
}

{
  const hand = ['special_dragon', 'spade_A', 'heart_A', 'club_10', 'spade_Q',
    'heart_Q', 'club_8', 'diamond_8', 'spade_6', 'heart_6',
    'club_4', 'diamond_4', 'spade_2', 'heart_2'];
  const out = give(hand);
  check('the Dragon outranks everything', out.partner === 'special_dragon',
    `gave ${out.partner}`);
}

{
  const hand = ['special_phoenix', 'spade_A', 'heart_A', 'club_10', 'spade_Q',
    'heart_Q', 'club_8', 'diamond_8', 'spade_6', 'heart_6',
    'club_4', 'diamond_4', 'spade_2', 'heart_2'];
  const out = give(hand);
  check('the Phoenix comes next, ahead of an Ace',
    out.partner === 'special_phoenix', `gave ${out.partner}`);
}

{
  // Bird and Dog are specials but not strength; they must lose to a number
  // card rather than ride the "special" branch.
  const hand = ['special_bird', 'special_dog', 'club_10', 'spade_Q',
    'heart_Q', 'club_8', 'diamond_8', 'spade_6', 'heart_6',
    'club_4', 'diamond_4', 'spade_2', 'heart_2', 'diamond_J'];
  const out = give(hand);
  check('the Mahjong and the Dog are not "the best card"',
    out.partner.endsWith('_Q'), `gave ${out.partner}`);
}

{
  const hand = ['diamond_J', 'club_10', 'spade_8', 'heart_8', 'club_6',
    'diamond_6', 'spade_4', 'heart_4', 'club_2', 'diamond_2',
    'spade_9', 'heart_9', 'club_7', 'diamond_7'];
  const out = give(hand);
  check('a hand with nothing high still gives its highest',
    out.partner === 'diamond_J', `gave ${out.partner}`);
}

console.log('\n[and the three cards are still three different cards]');
{
  const hand = ['spade_A', 'heart_A', 'club_A', 'diamond_A', 'club_10',
    'spade_Q', 'heart_Q', 'club_8', 'diamond_8', 'spade_6',
    'heart_6', 'club_4', 'diamond_4', 'spade_2'];
  const out = give(hand);
  const picked = [out.left, out.partner, out.right];
  check('no card is handed to two people', new Set(picked).size === 3,
    picked.join(', '));
  check('every card came from the hand', picked.every((c) => hand.includes(c)),
    picked.join(', '));
  // Four Aces is a bomb, and the rule still sends one away. Deliberate: the
  // partner holding an Ace is worth more than a bomb this hand may never get
  // to drop. Recorded here so a future change to that trade is a decision.
  check('a bomb does not exempt the top card', out.partner.endsWith('_A'),
    `gave ${out.partner}`);
}

console.log('\n[opponents still get the dross]');
{
  const hand = ['special_dragon', 'spade_A', 'heart_A', 'club_10', 'spade_Q',
    'heart_Q', 'club_8', 'diamond_8', 'spade_6', 'heart_6',
    'club_4', 'diamond_4', 'spade_2', 'heart_2'];
  const out = give(hand);
  for (const [seat, card] of [['left', out.left], ['right', out.right]]) {
    check(`the ${seat} opponent gets no special and no Ace`,
      !card.startsWith('special_') && !card.endsWith('_A'), card);
  }
}

console.log(failures === 0 ? '\nPASS' : `\n${failures} FAILURE(S)`);
process.exit(failures === 0 ? 0 : 1);
