// 로비에 보일 방들을 만들고 연결을 유지한다.
const WebSocket=require('/Users/jiny/Documents/Jiny/godot/tichu/server/node_modules/ws');
const sleep=ms=>new Promise(r=>setTimeout(r,ms));
const defs=[
  ['u01','Beginners Welcome 🙂',{gameType:'tichu'},1],
  ['u02','Pros Only Please',{gameType:'tichu'},2],
  ['u03','Skull King time!',{gameType:'skull_king',maxPlayers:4,skExpansions:['kraken']},2],
  ['u04','Mighty Practice',{gameType:'mighty',maxPlayers:5},3],
  ['u05','Casual Love Letter',{gameType:'love_letter',maxPlayers:4},1],
  ['u06','Tichu with Friends ☁️',{gameType:'tichu',password:'1234'},1],
  ['u07','Pirate Abilities 🏴‍☠️',{gameType:'skull_king',maxPlayers:5,skExpansions:['pirate_abilities']},3],
  ['u08','After-work Mighty',{gameType:'mighty',maxPlayers:5},2],
];
(async()=>{
  for(const [u,name,opt,bots] of defs){
    const ws=new WebSocket('ws://127.0.0.1:8190');const q=[];ws.on('message',d=>q.push(JSON.parse(d)));
    await new Promise(r=>ws.on('open',r));
    const wait=async t=>{for(let i=0;i<100;i++){const k=q.findIndex(m=>m.type===t);if(k>=0)return q.splice(k,1)[0];await sleep(50);}return null};
    ws.send(JSON.stringify({type:'login',username:u,password:'shots1234!',deviceInfo:{appVersion:'3.3.0'}}));
    const l=await wait('login_success');if(!l){console.log(u,'login fail');continue;}
    ws.send(JSON.stringify({type:'create_room',roomName:name,password:'',isRanked:false,turnTimeLimit:30,targetScore:1000,allowSpectators:true,allowMidGameJoin:false,...opt}));
    const r=await wait('room_joined');console.log(u,name,!!r);
    for(let i=0;i<bots;i++){ws.send(JSON.stringify({type:'add_bot',speed:'normal',strategy:'heuristic'}));await sleep(200);}
  }
  console.log('ready');
  setInterval(()=>{},1e6);
})();
