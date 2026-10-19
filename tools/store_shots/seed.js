const WebSocket=require('/Users/jiny/Documents/Jiny/godot/tichu/server/node_modules/ws');
const ws=new WebSocket('ws://127.0.0.1:8190');
const names=process.argv.slice(2);
const q=[];ws.on('message',d=>q.push(JSON.parse(d)));
const wait=async t=>{for(let i=0;i<100;i++){const k=q.findIndex(m=>m.type===t);if(k>=0)return q.splice(k,1)[0];await new Promise(r=>setTimeout(r,50));}throw new Error('timeout '+t)};
ws.on('open',async()=>{
  for(const n of names){const [u,nick]=n.split(':');
    ws.send(JSON.stringify({type:'register',username:u,password:'shots1234!',nickname:nick}));
    const r=await wait('register_result');console.log(u,r.success,r.message||'');}
  ws.close();
});
