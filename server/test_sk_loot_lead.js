'use strict';
// 스컬킹: 리드 색 판정(탈출·약탈은 투명, 해적/인어/스컬킹/크라켄/흰고래가 먼저면 리드 없음) + 약탈 동맹(둘 다 성공해야 +20).
//   node test_sk_loot_lead.js
const SK=require('./game/skull_king/SkullKingGame');
const ids=['a','b','c'];const names={a:'a',b:'b',c:'c'};
let ok=true;const chk=(n,c)=>{console.log(c?'ok  ':'FAIL',n);if(!c)ok=false;};
function mk(){const g=new SK(ids,names,{targetScore:100,expansions:['loot']});g.state='playing';g.round=3;
 g.hands={a:['sk_yellow_1'],b:['sk_purple_5','sk_yellow_9'],c:['sk_purple_2']};g.bids={a:1,b:1,c:0};g.tricks={a:0,b:0,c:0};g.bonuses={a:0,b:0,c:0};g.lootAlliances=[];g.scoreHistory=[];g.totalScores={a:0,b:0,c:0};return g;}
// pirate then purple: no lead suit
let g=mk();g.currentTrick=[{playerId:'a',cardId:'sk_pirate_1'},{playerId:'b',cardId:'sk_purple_5'}];
chk('pirate-first: no lead',g.getLeadSuit()===null);
g.hands.c=['sk_purple_2','sk_yellow_3'];chk('pirate-first: free',g.getLegalCards('c').length===2);
// escape then purple -> purple
g=mk();g.currentTrick=[{playerId:'a',cardId:'sk_escape_1'}];chk('escape only: null',g.getLeadSuit()===null);
g.currentTrick.push({playerId:'b',cardId:'sk_purple_5'});chk('escape then purple',g.getLeadSuit()==='purple');
g.hands.c=['sk_purple_2','sk_yellow_3'];chk('must follow purple',g.getLegalCards('c').join()==='sk_purple_2');
// loot then purple
g=mk();g.currentTrick=[{playerId:'a',cardId:'sk_loot_1'},{playerId:'b',cardId:'sk_purple_5'}];chk('loot then purple',g.getLeadSuit()==='purple');
// mermaid/kraken first
for(const id of ['sk_mermaid_1','sk_skull_king','sk_kraken','sk_white_whale']){g=mk();g.currentTrick=[{playerId:'a',cardId:id},{playerId:'b',cardId:'sk_purple_5'}];chk(id+' first: null',g.getLeadSuit()===null);}
// tigress pirate
g=mk();g.currentTrick=[{playerId:'a',cardId:'sk_tigress_1',tigressChoice:'pirate'},{playerId:'b',cardId:'sk_purple_5'}];chk('tigress pirate: null',g.getLeadSuit()===null);
// loot alliance: a plays loot, b wins. both bids met?
function run(bidB,tricksB){g=mk();g.bids={a:0,b:bidB,c:0};g.tricks={a:0,b:0,c:0};g.currentTrick=[{playerId:'a',cardId:'sk_loot_1'},{playerId:'b',cardId:'sk_purple_5'},{playerId:'c',cardId:'sk_purple_2'}];
 g.hands={a:[],b:[],c:[]};g.completeTrick();g.tricks.b=tricksB-1+1; // completeTrick already incremented b
 g.endRound();return g.lastRoundScores;}
let r=run(1,1);chk('both met: a=30+20, b=20+20 (round3)',r.a===30+20&&r.b===20+20);
r=run(2,1);chk('winner bid missed: no loot for a',r.a===30&&r.b<0);
console.log(r);
process.exit(ok?0:1);
