// 테스트(시뮬레이터 안)가 /private/tmp/shots_req/<name>.req 를 만들면 그 순간의 시뮬레이터 화면을 찍고 <name>.ack 를 남긴다.
const fs=require('fs'),cp=require('child_process');
const U=fs.readFileSync(process.argv[2],'utf8').trim(),OUT=process.argv[3],D='/private/tmp/shots_req';
fs.mkdirSync(OUT,{recursive:true});
setInterval(()=>{for(const f of fs.readdirSync(D)){if(!f.endsWith('.req'))continue;
  const name=f.slice(0,-4);fs.unlinkSync(`${D}/${f}`);
  fs.mkdirSync(OUT,{recursive:true});
  const r=cp.spawnSync('xcrun',['simctl','io',U,'screenshot','--type=png',`${OUT}/${name}.png`]);
  fs.writeFileSync(`${D}/${name}.ack`,String(r.status));}},80);
