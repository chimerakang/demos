/* ============================================================
   奪島遠征 Island Raid — roguelike 戰略小隊原型
   逆轉 Bad North：玩家搶灘攻島，佔領所有據點、肅清守軍。
   純 Canvas/JS，無外部相依。
   ============================================================ */
'use strict';

/* ---------------- RNG ---------------- */
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
let R = mulberry32(1);                 // 戰役 RNG（依 seed）
const rnd=(a=1,b)=> b===undefined? R()*a : a+R()*(b-a);
const ri=(a,b)=> Math.floor(rnd(a,b+1));
const pick=arr=> arr[Math.floor(R()*arr.length)];
const clamp=(v,a,b)=> v<a?a:v>b?b:v;
const dist=(ax,ay,bx,by)=> Math.hypot(ax-bx,ay-by);

/* ---------------- 常數 ---------------- */
const TW=22, TH=22, T=30, LIFT=5;      // 格數 / 格尺寸(px) / 每層高度視覺抬升
const CW=TW*T, CH=TH*T;
const AGGRO=T*4.6;                     // 守軍警戒半徑
const CAPTURE_TIME=4.5;                // 佔領一個據點所需秒數
const MAX_SQUADS=4;

/* ---------------- 兵種 ---------------- */
const TYPES={
  infantry:{name:'劍士', ico:'⚔️', n:9,  hp:3,   dmg:1.0, cd:.8,  spd:46, ranged:false,
            desc:'均衡近戰主力'},
  archer:  {name:'弓兵', ico:'🏹', n:8,  hp:2.4, dmg:.45, cd:.9,  spd:44, ranged:true,
            range:T*5.2, volleyCd:2.6, desc:'遠程齊射，近戰脆弱'},
  pike:    {name:'長槍兵',ico:'🔱', n:8,  hp:3.6, dmg:1.5, cd:1.15,spd:38, ranged:false,
            desc:'重擊緩慢，正面堅實'},
};
const ENEMY_TYPES=['infantry','archer','pike'];
const PLAYER_COLORS={infantry:'#5b9bff', archer:'#4ecfae', pike:'#9b8cf0'};
const ENEMY_COLOR='#ef7a6d', ENEMY_VET='#d94f3f';

/* ---------------- 技能 ---------------- */
const SKILLS={
  charge:{name:'衝鋒', ico:'💨', targeted:true,  cd:16, allow:['infantry','pike'],
    desc:'朝目標方向猛衝，撞擊敵兵並將其擊退——推下海即溺斃。'},
  volley:{name:'箭雨', ico:'☄️', targeted:true,  cd:15, allow:['archer'],
    desc:'對目標區域傾瀉密集箭矢。'},
  wall:  {name:'盾牆', ico:'🛡️', targeted:false, cd:18, allow:['infantry','pike'],
    desc:'原地結陣 5 秒，受到的傷害降低 65%。'},
  rally: {name:'集結', ico:'🚩', targeted:false, cd:50, allow:['infantry','archer','pike'],
    desc:'鼓舞士氣：治癒全隊並補充最多 3 名倒下的士兵。'},
};

/* ---------------- 戰役狀態 ---------------- */
let run=null;      // {seed, layer, campaign, roster, conquered}
let battle=null;   // 單場戰鬥狀態
let ui={sel:null, targeting:false};
let squadSeq=1;

function newRun(seed){
  R=mulberry32(seed);
  run={seed, layer:0, conquered:0, campaign:genCampaign(), roster:[
    mkRosterSquad('infantry'), mkRosterSquad('archer'),
  ]};
}
function mkRosterSquad(type){
  return {id:squadSeq++, type, vet:0, skill:null, alive:true, bonusN:0};
}
function squadMaxN(rs){ return TYPES[rs.type].n + rs.vet + rs.bonusN; }
function squadLabel(rs){ return TYPES[rs.type].name + (rs.vet>0? '★'.repeat(rs.vet):''); }

/* 戰役地圖：起始島 → 5 層每層 2 選 1 → 要塞 */
function genCampaign(){
  const layers=[[{type:'start', diff:0}]];
  for(let i=1;i<=5;i++){
    const mk=()=>{ const r=R();
      if(r<.30) return {type:'rich', diff:i};        // 富庶島：兩件戰利品
      if(r<.55) return {type:'hard', diff:i+2};      // 險惡島：更難、戰利品較佳
      return {type:'isle', diff:i}; };
    layers.push([mk(),mk()]);
  }
  layers.push([{type:'fort', diff:8}]);
  layers.flat().forEach((n,i)=>{n.cleared=false; n.seedOff=i*7919;});
  return layers;
}
const NODE_META={
  start:{ico:'⛵', nm:'前哨島'}, isle:{ico:'🏝️', nm:'小島'},
  rich:{ico:'💰', nm:'富庶島'}, hard:{ico:'💀', nm:'險惡島'}, fort:{ico:'🏰', nm:'要塞'},
};

/* ---------------- 島嶼產生 ---------------- */
function genIsland(diff, seedOff){
  const ir=mulberry32(run.seed+seedOff+1);
  const irnd=(a=1,b)=> b===undefined? ir()*a : a+ir()*(b-a);
  // 值雜訊
  const gsz=6, g=[];
  for(let y=0;y<=gsz;y++){g[y]=[];for(let x=0;x<=gsz;x++)g[y][x]=ir();}
  const noise=(fx,fy)=>{
    const gx=fx*gsz, gy=fy*gsz, x0=Math.floor(gx), y0=Math.floor(gy);
    const sx=gx-x0, sy=gy-y0, sm=t=>t*t*(3-2*t);
    const a=g[y0][x0], b=g[y0][x0+1], c=g[y0+1][x0], d=g[y0+1][x0+1];
    return a+(b-a)*sm(sx)+(c-a)*sm(sy)+(a-b-c+d)*sm(sx)*sm(sy);
  };
  const tiles=[];
  for(let y=0;y<TH;y++){tiles[y]=[];
    for(let x=0;x<TW;x++){
      const nx=(x+.5)/TW-.5, ny=(y+.5)/TH-.5;
      const rad=Math.hypot(nx,ny)*2;                       // 0 中心 → 1 邊緣
      let e=noise(x/TW,y/TH)*1.15 - rad*1.05 + .42;
      let h= e<0?0 : e<.14?1 : e<.3?2 : e<.44?3 : 4;
      if(x===0||y===0||x===TW-1||y===TH-1) h=0;
      tiles[y][x]={x,y,h,house:-1,shade:irnd(-1,1)};
    }
  }
  // 只留最大陸塊
  const seen=new Set(), key=(x,y)=>y*TW+x; let best=null;
  for(let y=0;y<TH;y++)for(let x=0;x<TW;x++){
    if(tiles[y][x].h===0||seen.has(key(x,y)))continue;
    const comp=[], q=[[x,y]]; seen.add(key(x,y));
    while(q.length){const [cx,cy]=q.pop(); comp.push([cx,cy]);
      for(const[dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]){
        const nx2=cx+dx, ny2=cy+dy;
        if(nx2<0||ny2<0||nx2>=TW||ny2>=TH)continue;
        if(tiles[ny2][nx2].h>0&&!seen.has(key(nx2,ny2))){seen.add(key(nx2,ny2));q.push([nx2,ny2]);}
      }}
    if(!best||comp.length>best.length)best=comp;
  }
  const bestSet=new Set(best.map(([x,y])=>key(x,y)));
  for(let y=0;y<TH;y++)for(let x=0;x<TW;x++)
    if(tiles[y][x].h>0&&!bestSet.has(key(x,y)))tiles[y][x].h=0;
  // 高度差平滑：與四鄰最低差不超過 1（保證可通行）
  let changed=true;
  while(changed){changed=false;
    for(let y=0;y<TH;y++)for(let x=0;x<TW;x++){
      const t0=tiles[y][x]; if(t0.h<=1)continue;
      let lo=99;
      for(const[dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]){
        const n=tiles[y+dy]?.[x+dx]; if(n&&n.h>0)lo=Math.min(lo,n.h);
      }
      if(lo<99&&t0.h>lo+1){t0.h=lo+1;changed=true;}
    }}
  // 海洋（連通地圖邊界的水域）
  const ocean=new Set(), q2=[[0,0]]; ocean.add(key(0,0));
  while(q2.length){const[cx,cy]=q2.pop();
    for(const[dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]){
      const nx2=cx+dx, ny2=cy+dy;
      if(nx2<0||ny2<0||nx2>=TW||ny2>=TH)continue;
      if(tiles[ny2][nx2].h===0&&!ocean.has(key(nx2,ny2))){ocean.add(key(nx2,ny2));q2.push([nx2,ny2]);}
    }}
  for(let y=0;y<TH;y++)for(let x=0;x<TW;x++){
    const t0=tiles[y][x];
    t0.ocean=t0.h===0&&ocean.has(key(x,y));
    if(t0.h===0&&!t0.ocean)t0.h=1;                        // 內陸積水填為低地
  }
  // 灘頭：h==1 且鄰海
  const beaches=[];
  for(let y=0;y<TH;y++)for(let x=0;x<TW;x++){
    const t0=tiles[y][x]; if(t0.h!==1)continue;
    t0.beach=[[1,0],[-1,0],[0,1],[0,-1]].some(([dx,dy])=>tiles[y+dy]?.[x+dx]?.ocean);
    if(t0.beach)beaches.push(t0);
  }
  // 據點（房舍）：最遠點取樣
  const nHouses=3+Math.min(2,diff>>1);
  const cand=[];
  for(let y=2;y<TH-2;y++)for(let x=2;x<TW-2;x++)
    if(tiles[y][x].h>=2)cand.push(tiles[y][x]);
  const houses=[];
  if(cand.length){
    houses.push(cand[Math.floor(ir()*cand.length)]);
    while(houses.length<nHouses&&cand.length){
      let far=null,fd=-1;
      for(const c of cand){
        const d=Math.min(...houses.map(h=>dist(c.x,c.y,h.x,h.y)));
        if(d>fd){fd=d;far=c;}
      }
      if(fd<3)break;
      houses.push(far);
    }
  }
  const houseObjs=houses.map((t0,i)=>{t0.house=i;
    return {tile:t0,captured:false,progress:0};});
  return {tiles,beaches,houses:houseObjs,diff};
}

/* ---------------- 尋路 ---------------- */
function tileAt(px,py){const x=Math.floor(px/T),y=Math.floor(py/T);
  return (x>=0&&y>=0&&x<TW&&y<TH)?battle.island.tiles[y][x]:null;}
function landPass(a,b){return a.h>0&&b.h>0&&Math.abs(a.h-b.h)<=1;}
function findPath(sx,sy,tx,ty,water){
  const tiles=battle.island.tiles;
  const pass=water? t0=>t0.ocean : t0=>t0.h>0;
  const start=tiles[sy]?.[sx], goal=tiles[ty]?.[tx];
  if(!start||!goal||!pass(goal))return null;
  const prev=new Map(), key=(x,y)=>y*TW+x;
  const q=[[sx,sy]]; prev.set(key(sx,sy),null);
  while(q.length){
    const[cx,cy]=q.shift();
    if(cx===tx&&cy===ty){
      const path=[]; let k=key(tx,ty), cur=[tx,ty];
      while(cur){path.unshift({x:cur[0],y:cur[1]}); cur=prev.get(k);
        if(cur)k=key(cur[0],cur[1]);}
      path.shift(); return path;
    }
    for(const[dx,dy]of[[1,0],[-1,0],[0,1],[0,-1]]){
      const nx=cx+dx, ny=cy+dy;
      if(nx<0||ny<0||nx>=TW||ny>=TH||prev.has(key(nx,ny)))continue;
      const a=tiles[cy][cx], b=tiles[ny][nx];
      if(!pass(b))continue;
      if(!water&&!landPass(a,b))continue;
      prev.set(key(nx,ny),[cx,cy]); q.push([nx,ny]);
    }
  }
  return null;
}
function nearestReachable(tx,ty,fromTile){ // 目標不可走時找附近可走格
  const tiles=battle.island.tiles;
  let bestT=null,bd=1e9;
  for(let y=Math.max(0,ty-2);y<=Math.min(TH-1,ty+2);y++)
    for(let x=Math.max(0,tx-2);x<=Math.min(TW-1,tx+2);x++){
      if(tiles[y][x].h<=0)continue;
      const d=dist(x,y,tx,ty);
      if(d<bd){bd=d;bestT=tiles[y][x];}
    }
  return bestT;
}

/* ---------------- 小隊 ---------------- */
function slotOffsets(n){
  const out=[[0,0]];
  for(let ring=1;out.length<n;ring++){
    const cnt=ring*6;
    for(let i=0;i<cnt&&out.length<n;i++){
      const a=i/cnt*Math.PI*2+ring;
      out.push([Math.cos(a)*ring*7.5,Math.sin(a)*ring*7.5]);
    }
  }
  return out;
}
function mkSquad(side,type,x,y,opt={}){
  const def=TYPES[type];
  const n=opt.n ?? def.n+(opt.vet||0);
  const s={
    id:opt.roster?opt.roster.id:('e'+squadSeq++), side, type, def,
    roster:opt.roster||null, vet:opt.vet||0,
    x,y, path:[], soldiers:[], engaged:false, dead:false,
    skill:opt.roster?opt.roster.skill:null, skillCd:0, buff:{wall:0},
    charge:null, volleyT:rnd(1,2.5), repathT:0, aiState:'garrison', aiTarget:null,
    home:{x:Math.floor(x/T),y:Math.floor(y/T)},
    maxN:n,
  };
  const slots=slotOffsets(n);
  for(let i=0;i<n;i++){
    s.soldiers.push({x:x+slots[i][0],y:y+slots[i][1],hp:def.hp+(s.vet?1:0),
      cd:rnd(.5), slot:i, kb:null});
  }
  return s;
}
function squadColor(s){
  if(s.side==='p')return PLAYER_COLORS[s.type];
  return s.vet?ENEMY_VET:ENEMY_COLOR;
}
function orderMove(s,tx,ty){
  const tiles=battle.island.tiles;
  let goal=tiles[ty]?.[tx];
  if(!goal)return;
  if(goal.h<=0){const alt=nearestReachable(tx,ty);if(!alt)return;goal=alt;}
  const cur=tileAt(s.x,s.y); if(!cur)return;
  const p=findPath(cur.x,cur.y,goal.x,goal.y,false);
  if(p){s.path=p; s.moveMark={x:goal.x,y:goal.y,t:0};}
}

/* ---------------- 戰鬥初始化 ---------------- */
function startBattle(node){
  const island=genIsland(node.diff,node.seedOff);
  battle={
    node, island, time:0, over:false, result:null,
    squads:[], boats:[], arrows:[], effects:[], waves:[],
    msgT:0, endT:0, surrendered:false,
  };
  ui.sel=null; ui.targeting=false;

  // 守軍
  const d=node.diff;
  const nDef=2+Math.round(d*.9);
  const spots=[];
  for(const h of island.houses)spots.push(h.tile);
  const landTiles=[];
  for(let y=0;y<TH;y++)for(let x=0;x<TW;x++)
    if(island.tiles[y][x].h>=2)landTiles.push(island.tiles[y][x]);
  for(let i=0;i<nDef;i++){
    const base=spots[i%spots.length]||pick(landTiles);
    const t0=nearestReachable(base.x+ri(-2,2),base.y+ri(-2,2))||base;
    const type=d>=3? pick(ENEMY_TYPES) : pick(['infantry','infantry','archer']);
    const vet=(d>=4&&R()<.25+d*.05)?1:0;
    battle.squads.push(mkSquad('e',type,t0.x*T+T/2,t0.y*T+T/2,{vet,n:TYPES[type].n-2+vet+Math.min(3,d>>1)}));
  }
  // 援軍船班
  if(d>=3)battle.waves.push({t:50,done:false});
  if(d>=6)battle.waves.push({t:95,done:false});
  if(node.type==='fort')battle.waves.push({t:140,done:false});

  // 玩家登陸艇：沿地圖下緣海面排開
  const alive=run.roster.filter(r=>r.alive);
  alive.forEach((rs,i)=>{
    const bx=(TW/(alive.length+1))*(i+1)*T, by=(TH-1)*T+T/2;
    const sq=mkSquad('p',rs.type,bx,by,{roster:rs,vet:rs.vet,n:squadMaxN(rs)});
    sq.onBoat=true;
    battle.squads.push(sq);
    battle.boats.push({squad:sq,x:bx,y:by,path:[],state:'idle',bob:rnd(6.28)});
  });
  showMsg('搶灘登陸！點選小隊 → 點擊灘頭','#ffe9a8',3.2);
  showScreen('battle');
  renderSquadBar();
}

/* ---------------- 主更新 ---------------- */
function update(dt){
  const b=battle; if(!b)return;
  b.time+=dt;

  // 船
  for(const bt of b.boats){
    bt.bob+=dt*2;
    if(bt.state==='sail'&&bt.path.length){
      const wp=bt.path[0], px=wp.x*T+T/2, py=wp.y*T+T/2;
      const d=dist(bt.x,bt.y,px,py), spd=70;
      if(d<spd*dt){bt.x=px;bt.y=py;bt.path.shift();
        if(!bt.path.length){ // 靠岸 → 下船
          bt.state='landed';
          const lt=bt.beach;
          bt.squad.onBoat=false;
          bt.squad.x=lt.x*T+T/2; bt.squad.y=lt.y*T+T/2;
          for(const so of bt.squad.soldiers){so.x=bt.x;so.y=bt.y;}
          addFx('ring',bt.squad.x,bt.squad.y,'#cfe3ff');
        }}
      else{bt.x+=(px-bt.x)/d*spd*dt;bt.y+=(py-bt.y)/d*spd*dt;}
    }
    if(bt.state!=='landed'){bt.squad.x=bt.x;bt.squad.y=bt.y-4;}
  }

  // 援軍
  for(const w of b.waves){
    if(!w.done&&b.time>=w.t){w.done=true;spawnWave();}
  }

  // 小隊
  const alive=b.squads.filter(s=>!s.dead);
  for(const s of alive){
    if(s.onBoat)continue;
    s.skillCd=Math.max(0,s.skillCd-dt);
    s.buff.wall=Math.max(0,s.buff.wall-dt);
    if(s.moveMark)s.moveMark.t+=dt;

    // 交戰判定
    s.engaged=false;
    for(const o of alive){
      if(o.side===s.side||o.dead||o.onBoat)continue;
      if(dist(s.x,s.y,o.x,o.y)<T*1.35){s.engaged=true;break;}
    }

    // 衝鋒
    if(s.charge){
      const c=s.charge, step=170*dt;
      const nx=s.x+c.dx*step, ny=s.y+c.dy*step;
      const nt=tileAt(nx,ny);
      if(!nt||nt.h<=0){c.left=0;}          // 衝到岸邊煞停（敵兵仍會被推下海）
      else{s.x=nx;s.y=ny;}
      c.left-=step;
      for(const o of alive){
        if(o.side===s.side||o.dead||o.onBoat)continue;
        for(const so of o.soldiers){
          if(c.hit.has(so))continue;
          if(dist(so.x,so.y,s.x,s.y)<T*.9){
            c.hit.add(so);
            so.hp-=1.5+(s.vet?.5:0);
            so.kb={dx:c.dx,dy:c.dy,left:T*1.05};
            addFx('slash',so.x,so.y,'#fff');
          }
        }
      }
      if(c.left<=0)s.charge=null;
    }
    else if(!s.engaged&&s.path.length&&s.buff.wall<=0){
      const wp=s.path[0], px=wp.x*T+T/2, py=wp.y*T+T/2;
      const cur=tileAt(s.x,s.y), nxt=b.island.tiles[wp.y][wp.x];
      const climb=cur&&nxt&&nxt.h>cur.h;
      const spd=s.def.spd*(climb?.55:1);
      const d=dist(s.x,s.y,px,py);
      if(d<spd*dt){s.x=px;s.y=py;s.path.shift();}
      else{s.x+=(px-s.x)/d*spd*dt;s.y+=(py-s.y)/d*spd*dt;}
    }

    // 弓兵齊射
    if(s.def.ranged&&!s.engaged&&!s.charge){
      s.volleyT-=dt;
      if(s.volleyT<=0){
        let tgt=null,bd=1e9;
        for(const o of alive){
          if(o.side===s.side||o.dead||o.onBoat)continue;
          const d=dist(s.x,s.y,o.x,o.y);
          if(d<s.def.range&&d<bd){bd=d;tgt=o;}
        }
        if(tgt){
          s.volleyT=s.def.volleyCd;
          for(const so of s.soldiers){
            const v=tgt.soldiers[Math.floor(Math.random()*tgt.soldiers.length)];
            if(!v)break;
            fireArrow(so.x,so.y,v.x+rnd(-9,9),v.y+rnd(-9,9),s.side,
              s.def.dmg*2+(s.vet?.3:0));
          }
          if(s.side==='e')aggroPlayerHit(s);   // 被射的玩家不反擊 AI，但守軍射擊會暴露
        } else s.volleyT=.4;
      }
    }

    // 士兵層
    updateSoldiers(s,alive,dt);
    if(!s.soldiers.length){
      s.dead=true;
      if(s.roster){s.roster.alive=false;
        showMsg(squadLabel(s.roster)+' 小隊全滅…','#ff9d94',2.5);}
      addFx('ring',s.x,s.y,'#1b2440');
      renderSquadBar();
      if(ui.sel===s){ui.sel=null;ui.targeting=false;updateSkillBtn();}
    }
  }

  // 守軍 AI
  aiTick(dt,alive);

  // 佔領
  updateCapture(dt,alive);

  // 箭矢 / 特效
  updateArrows(dt,alive);
  b.effects=b.effects.filter(f=>(f.t+=dt)<f.T);

  // 勝負
  if(!b.over){
    const pAlive=b.squads.some(s=>s.side==='p'&&!s.dead);
    const eAlive=b.squads.some(s=>s.side==='e'&&!s.dead);
    const allCap=b.island.houses.every(h=>h.captured);
    if(allCap&&!b.surrendered){
      b.surrendered=true; b.waves.length=0;
      if(eAlive)showMsg('據點全數易幟！肅清殘餘守軍','#ffe9a8',3);
    }
    const wavePending=b.waves.some(w=>!w.done);
    if(!pAlive){b.over=true;b.result='lose';}
    else if(allCap&&!eAlive&&!wavePending){b.over=true;b.result='win';}
    if(b.over)b.endT=1.6;
  } else {
    b.endT-=dt;
    if(b.endT<=0)finishBattle();
  }
  b.msgT=Math.max(0,b.msgT-dt);
  if(b.msgT<=0)document.getElementById('msg').classList.remove('on');
  updateObjective();
}

/* 士兵個體：追擊 / 佔位 / 攻擊 / 擊退 / 溺水 */
function updateSoldiers(s,alive,dt){
  const slots=slotOffsets(s.maxN);
  const foes=[];
  for(const o of alive){
    if(o.side===s.side||o.dead||o.onBoat)continue;
    if(dist(s.x,s.y,o.x,o.y)<T*3.2)foes.push(o);
  }
  for(const so of s.soldiers){
    so.cd=Math.max(0,so.cd-dt);
    if(so.kb){ // 擊退
      const step=140*dt;
      so.x+=so.kb.dx*step; so.y+=so.kb.dy*step; so.kb.left-=step;
      if(so.kb.left<=0){so.kb=null;
        const t0=tileAt(so.x,so.y);
        if(!t0||t0.h<=0){so.hp=0;addFx('splash',so.x,so.y,'#9cc8ff');}
      }
      continue;
    }
    let tgt=null,bd=1e9;
    if(foes.length&&s.buff.wall<=0||s.engaged){
      for(const o of foes)for(const v of o.soldiers){
        const d=dist(so.x,so.y,v.x,v.y);
        if(d<bd&&d<T*1.9){bd=d;tgt=v;}
      }
    }
    if(tgt){
      if(bd>8){const step=(s.def.spd+12)*dt;
        so.x+=(tgt.x-so.x)/bd*step; so.y+=(tgt.y-so.y)/bd*step;}
      else if(so.cd<=0){
        so.cd=s.def.cd;
        let dmg=s.def.dmg*(s.vet?1.25:1);
        const os=findOwner(tgt,alive);
        if(os&&os.buff.wall>0)dmg*=.35;
        tgt.hp-=dmg;
        addFx('slash',tgt.x,tgt.y,'#ffffff');
        if(os&&os.side==='e')aggroDefender(os,s);
      }
    } else {
      const off=slots[so.slot%slots.length];
      const px=s.x+off[0], py=s.y+off[1];
      const d=dist(so.x,so.y,px,py);
      if(d>2){const step=(s.def.spd+26)*dt;
        so.x+=(px-so.x)/d*Math.min(step,d);so.y+=(py-so.y)/d*Math.min(step,d);}
    }
    // 走到水裡（被擠壓等）緩慢淹死保護：拉回最近陸地
    const t0=tileAt(so.x,so.y);
    if(t0&&t0.h<=0&&!so.kb){
      const back=nearestReachable(t0.x,t0.y);
      if(back){so.x+=((back.x*T+T/2)-so.x)*.2;so.y+=((back.y*T+T/2)-so.y)*.2;}
    }
  }
  s.soldiers=s.soldiers.filter(so=>so.hp>0);
}
function findOwner(soldier,alive){
  for(const s of alive)if(s.soldiers.includes(soldier))return s;
  return null;
}

/* ---------------- 守軍 AI ---------------- */
function aggroDefender(es,from){ if(es.aiState==='garrison'){es.aiState='attack';es.aiTarget=from;} }
function aggroPlayerHit(){/* 佔位：目前玩家小隊不自動反追 */}
function aiTick(dt,alive){
  for(const s of alive){
    if(s.side!=='e'||s.onBoat||s.dead)continue;
    s.repathT-=dt;
    if(s.repathT>0)continue;
    s.repathT=.6;
    const players=alive.filter(o=>o.side==='p'&&!o.onBoat&&!o.dead);
    if(!players.length){s.path=[];continue;}
    let near=null,bd=1e9;
    for(const p of players){const d=dist(s.x,s.y,p.x,p.y);if(d<bd){bd=d;near=p;}}
    if(s.aiState==='garrison'){
      if(bd<AGGRO){s.aiState='attack';s.aiTarget=near;}
      else{
        // 有據點被佔領中 → 馳援
        const contested=battle.island.houses.find(h=>!h.captured&&h.progress>0);
        if(contested){s.aiState='attack';s.aiTarget=near;}
      }
    }
    if(s.aiState==='attack'){
      if(!s.aiTarget||s.aiTarget.dead||s.aiTarget.onBoat)s.aiTarget=near;
      const tgt=s.aiTarget;
      if(!tgt){s.aiState='garrison';continue;}
      const td=dist(s.x,s.y,tgt.x,tgt.y);
      if(s.def.ranged&&td<s.def.range*.9&&td>T*1.6){s.path=[];continue;}
      if(td>T*1.1){
        const ct=tileAt(s.x,s.y), tt=tileAt(tgt.x,tgt.y);
        if(ct&&tt){const p=findPath(ct.x,ct.y,tt.x,tt.y,false);
          if(p)s.path=p.slice(0,10);}
      } else s.path=[];
    }
  }
}
function spawnWave(){
  const b=battle;
  const beach=pick(b.island.beaches); if(!beach)return;
  const d=b.node.diff;
  const type=pick(ENEMY_TYPES);
  const sq=mkSquad('e',type,beach.x*T+T/2,beach.y*T+T/2,
    {vet:d>=5?1:0,n:TYPES[type].n-1+Math.min(3,d>>1)});
  sq.aiState='attack';
  b.squads.push(sq);
  addFx('ring',sq.x,sq.y,'#ffb4a8');
  showMsg('敵方援軍登陸！','#ff9d94',2.5);
}

/* ---------------- 佔領 ---------------- */
function updateCapture(dt,alive){
  for(const h of battle.island.houses){
    if(h.captured)continue;
    const hx=h.tile.x*T+T/2, hy=h.tile.y*T+T/2;
    const pNear=alive.some(s=>s.side==='p'&&!s.dead&&!s.onBoat&&dist(s.x,s.y,hx,hy)<T*1.1);
    const eNear=alive.some(s=>s.side==='e'&&!s.dead&&dist(s.x,s.y,hx,hy)<T*2.4);
    if(pNear&&!eNear){
      h.progress+=dt/CAPTURE_TIME;
      if(h.progress>=1){h.captured=true;h.progress=1;
        addFx('ring',hx,hy,'#8ab4ff');
        showMsg('據點佔領！','#cfe3ff',1.6);}
    } else if(h.progress>0&&!pNear){
      h.progress=Math.max(0,h.progress-dt/CAPTURE_TIME*.7);
    }
  }
}

/* ---------------- 箭矢 ---------------- */
function fireArrow(sx,sy,tx,ty,side,dmg){
  const d=dist(sx,sy,tx,ty);
  battle.arrows.push({sx,sy,tx,ty,t:0,T:.35+d/260,side,dmg});
}
function updateArrows(dt,alive){
  const b=battle;
  for(const a of b.arrows){
    a.t+=dt;
    if(a.t>=a.T){
      a.hit=true;
      let v=null,bd=12,os=null;
      for(const s of alive){
        if(s.side===a.side||s.dead||s.onBoat)continue;
        for(const so of s.soldiers){
          const d=dist(so.x,so.y,a.tx,a.ty);
          if(d<bd){bd=d;v=so;os=s;}
        }
      }
      if(v){
        let dmg=a.dmg;
        if(os.buff.wall>0)dmg*=.35;
        v.hp-=dmg;
        addFx('slash',v.x,v.y,'#ffe1a8');
        if(os.side==='e')aggroDefender(os,null);
      } else addFx('puff',a.tx,a.ty,'#c9d6f2');
    }
  }
  b.arrows=b.arrows.filter(a=>!a.hit);
}

/* ---------------- 技能 ---------------- */
function useSkill(s,tx,ty){
  const sk=SKILLS[s.skill]; if(!sk||s.skillCd>0)return;
  if(sk.targeted&&tx===undefined)return;
  s.skillCd=sk.cd;
  if(s.skill==='charge'){
    const dx=tx-s.x, dy=ty-s.y, d=Math.hypot(dx,dy)||1;
    s.charge={dx:dx/d,dy:dy/d,left:Math.min(d,T*3.4),hit:new Set()};
    s.path=[];
    addFx('ring',s.x,s.y,'#fff');
  }
  else if(s.skill==='volley'){
    for(let i=0;i<14;i++){
      const ang=rnd(6.28), r=rnd(T*1.25);
      const ax=tx+Math.cos(ang)*r, ay=ty+Math.sin(ang)*r;
      setTimeout(()=>{ if(battle&&!battle.over)
        fireArrow(s.x+rnd(-8,8),s.y-6,ax,ay,s.side,1.4); }, i*90);
    }
    addFx('ring',tx,ty,'#ffe1a8');
  }
  else if(s.skill==='wall'){
    s.buff.wall=5; s.path=[];
    addFx('ring',s.x,s.y,'#9b8cf0');
  }
  else if(s.skill==='rally'){
    for(const so of s.soldiers)so.hp=s.def.hp+(s.vet?1:0);
    let need=Math.min(3,s.maxN-s.soldiers.length);
    while(need-->0)
      s.soldiers.push({x:s.x+rnd(-6,6),y:s.y+rnd(-6,6),
        hp:s.def.hp+(s.vet?1:0),cd:0,slot:s.soldiers.length,kb:null});
    addFx('ring',s.x,s.y,'#f2c56b');
  }
  ui.targeting=false;
  updateSkillBtn();
}

/* ---------------- 特效 / 訊息 ---------------- */
function addFx(type,x,y,color){battle.effects.push({type,x,y,color,t:0,
  T:type==='ring'?.6:type==='splash'?.8:.3});}
function showMsg(txt,color,dur=2){
  const el=document.getElementById('msg');
  el.textContent=txt; el.style.color=color||'#fff'; el.classList.add('on');
  battle.msgT=dur;
}

/* ---------------- 戰鬥結束 → 獎勵 ---------------- */
function finishBattle(){
  const b=battle;
  if(b.result==='win'){
    b.node.cleared=true;
    run.conquered++;
    for(const rs of run.roster)if(rs.alive){/* 島間全員休整 */}
    saveBest();
    if(b.node.type==='fort'){showEnd(true);return;}
    run.layer++;
    showReward(b.node.type==='rich'?2:1, b.node.type==='hard');
  } else {
    showEnd(false);
  }
  battle=null;
}

/* ---------------- 獎勵卡 ---------------- */
const CARD_DEFS=[
  {id:'recruit', ico:'⛵', ttl:'援軍小隊', tag:'新戰力',
    ok:()=>run.roster.filter(r=>r.alive).length<MAX_SQUADS,
    dsc:()=>'一支新的小隊加入遠征（隨機兵種）。'},
  {id:'vet', ico:'🎖️', ttl:'老兵勳章', tag:'強化',
    ok:()=>run.roster.some(r=>r.alive&&r.vet<2),
    dsc:()=>'選一支小隊晉升老兵：+傷害、+體力、+1 人。'},
  {id:'skill', ico:'📜', ttl:'技能卷軸', tag:'技能',
    ok:()=>run.roster.some(r=>r.alive&&!r.skill),
    dsc:()=>'習得隨機戰技，指派給一支小隊。'},
  {id:'banner', ico:'🚩', ttl:'軍旗', tag:'全體',
    ok:()=>true,
    dsc:()=>'所有小隊編制 +1 人。'},
];
function showReward(picks,better){
  const wrap=document.getElementById('reward-cards');
  const sub=document.getElementById('reward-sub');
  wrap.innerHTML='';
  let remaining=picks;
  sub.textContent=picks>1?`富庶之島——可選擇 ${picks} 項戰利品`:'選擇一項戰利品';
  const pool=CARD_DEFS.filter(c=>c.ok());
  const opts=[];
  const shuffled=[...pool].sort(()=>R()-.5);
  while(opts.length<3&&shuffled.length)opts.push(shuffled.pop());
  while(opts.length<3)opts.push(CARD_DEFS[3]); // banner 湊數
  for(const c of opts){
    const el=document.createElement('button');
    el.className='card';
    const skillId=c.id==='skill'?pick(Object.keys(SKILLS)):null;
    const ttl=c.id==='skill'?`卷軸：${SKILLS[skillId].name}`:c.ttl;
    const dsc=c.id==='skill'?SKILLS[skillId].desc:c.dsc();
    el.innerHTML=`<div class="ico">${c.id==='skill'?SKILLS[skillId].ico:c.ico}</div>
      <div class="ttl">${ttl}</div><div class="dsc">${dsc}</div>
      <div class="tag">${better?'險惡之地・戰利品 ':''}${c.tag}</div>`;
    el.onclick=()=>{
      applyCard(c.id,skillId,better,()=>{
        remaining--;
        el.remove();
        if(remaining<=0)showCampaign();
        else sub.textContent=`還可選擇 ${remaining} 項`;
      });
    };
    wrap.appendChild(el);
  }
  showScreen('reward');
}
function applyCard(id,skillId,better,done){
  if(id==='recruit'){
    const rs=mkRosterSquad(pick(['infantry','archer','pike']));
    if(better)rs.vet=1;
    run.roster.push(rs);
    done();
  }
  else if(id==='banner'){
    for(const r of run.roster)if(r.alive)r.bonusN++;
    done();
  }
  else if(id==='vet'){
    pickSquadModal('選擇要晉升的小隊', r=>r.alive&&r.vet<2, rs=>{
      rs.vet=Math.min(2,rs.vet+(better?2:1)); done();
    });
  }
  else if(id==='skill'){
    const sk=SKILLS[skillId];
    pickSquadModal(`把「${sk.name}」交給誰？`,
      r=>r.alive&&!r.skill&&sk.allow.includes(r.type),
      rs=>{rs.skill=skillId; done();},
      ()=>{ // 沒有符合的小隊 → 換成軍旗
        for(const r of run.roster)if(r.alive)r.bonusN++;
        done();
      });
  }
}
function pickSquadModal(title,filter,cb,fallback){
  const list=run.roster.filter(filter);
  if(!list.length){ if(fallback)fallback(); else cb(run.roster.find(r=>r.alive)); return; }
  const m=document.getElementById('modal');
  m.innerHTML='';
  const box=document.createElement('div'); box.className='box';
  box.innerHTML=`<h3 style="margin:0 0 14px">${title}</h3>`;
  const row=document.createElement('div'); row.className='row';
  for(const rs of list){
    const bt=document.createElement('button'); bt.className='btn';
    bt.textContent=`${TYPES[rs.type].ico} ${squadLabel(rs)}`;
    bt.onclick=()=>{m.classList.remove('on');cb(rs);};
    row.appendChild(bt);
  }
  box.appendChild(row); m.appendChild(box); m.classList.add('on');
}

/* ---------------- 畫面切換 / UI ---------------- */
function showScreen(name){
  document.querySelectorAll('.screen').forEach(s=>s.classList.remove('on'));
  document.getElementById('scr-'+name).classList.add('on');
}
function showCampaign(){
  const map=document.getElementById('camp-map');
  const sub=document.getElementById('camp-sub');
  map.innerHTML='';
  sub.textContent=`種子 ${run.seed} ・ 已攻陷 ${run.conquered} 座島 ・ 選擇下一個目標`;
  run.campaign.forEach((layer,li)=>{
    const col=document.createElement('div'); col.className='layer';
    for(const node of layer){
      const el=document.createElement('div');
      const meta=NODE_META[node.type];
      el.className='node'+(node.type==='fort'?' fort':'');
      if(node.cleared)el.classList.add('done');
      else if(li===run.layer)el.classList.add('avail');
      el.innerHTML=`<div class="ico">${meta.ico}</div><div>${meta.nm}</div>
        <div>${'☠'.repeat(clamp(Math.ceil(node.diff/2),1,4))}</div>`;
      if(li===run.layer&&!node.cleared)
        el.onclick=()=>startBattle(node);
      col.appendChild(el);
    }
    map.appendChild(col);
    if(li<run.campaign.length-1){
      const ar=document.createElement('div');ar.className='arrow';ar.textContent='➜';
      map.appendChild(ar);
    }
  });
  const roster=document.getElementById('camp-roster');
  roster.innerHTML='';
  for(const rs of run.roster){
    const el=document.createElement('div'); el.className='rchip';
    if(!rs.alive)el.style.opacity=.35;
    el.innerHTML=`<div class="nm">${TYPES[rs.type].ico} ${squadLabel(rs)}</div>
      <div class="dt">${rs.alive?`${squadMaxN(rs)} 人 ・ ${TYPES[rs.type].desc}`:'已全滅'}</div>
      ${rs.skill?`<div class="sk">${SKILLS[rs.skill].ico} ${SKILLS[rs.skill].name}</div>`:''}`;
    roster.appendChild(el);
  }
  showScreen('campaign');
}
function showEnd(win){
  const t=document.getElementById('end-title');
  const s=document.getElementById('end-sub');
  t.textContent=win?'🏰 要塞陷落・遠征成功':'☠ 遠征覆滅';
  t.style.color=win?'#f2c56b':'#ef7a6d';
  s.innerHTML=`攻陷島嶼 <b>${run.conquered}</b> 座 ・ 種子 <b>${run.seed}</b><br>`+
    (win?'群島已是你的了，指揮官。':'艦隊沉沒於怒濤之中——再組一支遠征軍吧。');
  saveBest();
  showScreen('end');
}
function saveBest(){
  try{
    const best=+localStorage.getItem('islandraid.best')||0;
    if(run.conquered>best)localStorage.setItem('islandraid.best',run.conquered);
  }catch(e){}
}
function renderSquadBar(){
  const bar=document.getElementById('squad-bar');
  bar.innerHTML='';
  if(!battle)return;
  battle.squads.filter(s=>s.side==='p').forEach((s,i)=>{
    const el=document.createElement('button');
    el.className='chip'+(s.dead?' dead':'')+(ui.sel===s?' sel':'');
    el.innerHTML=`<div class="nm" style="color:${squadColor(s)}">${i+1} ${TYPES[s.type].name}${s.vet?'★'.repeat(s.vet):''}</div>
      <div class="st">${s.dead?'全滅':(s.onBoat?'船上 ':'')+s.soldiers.length+' 人'}</div>
      ${s.skill?`<div class="sk">${SKILLS[s.skill].ico}${SKILLS[s.skill].name}</div>`:''}`;
    if(!s.dead)el.onclick=()=>selectSquad(s);
    bar.appendChild(el);
  });
}
function selectSquad(s){
  ui.sel=s; ui.targeting=false;
  renderSquadBar(); updateSkillBtn();
}
function updateSkillBtn(){
  const bt=document.getElementById('skill-btn');
  const s=ui.sel;
  if(!s||s.dead||!s.skill||s.onBoat){bt.style.display='none';return;}
  const sk=SKILLS[s.skill];
  bt.style.display='block';
  bt.classList.toggle('cd',s.skillCd>0);
  bt.classList.toggle('arm',ui.targeting);
  bt.textContent=s.skillCd>0? `${sk.ico} ${sk.name} ${Math.ceil(s.skillCd)}s`
    : ui.targeting? `${sk.ico} 點擊目標位置…` : `${sk.ico} ${sk.name}`;
}
function updateObjective(){
  const el=document.getElementById('objective');
  if(!battle){el.innerHTML='';return;}
  const hs=battle.island.houses;
  const cap=hs.filter(h=>h.captured).length;
  const foes=battle.squads.filter(s=>s.side==='e'&&!s.dead).length;
  const wave=battle.waves.some(w=>!w.done);
  el.innerHTML=`佔領據點 <b>${cap}/${hs.length}</b><br>殘餘守軍 <b>${foes}</b>${wave?'<br>⚠ 敵援軍將至':''}`;
}

/* ---------------- 輸入 ---------------- */
const cv=document.getElementById('cv');
const ctx=cv.getContext('2d');
function canvasPos(e){
  const r=cv.getBoundingClientRect();
  return {x:(e.clientX-r.left)/r.width*CW, y:(e.clientY-r.top)/r.height*CH};
}
function pickTile(mx,my){
  const tiles=battle.island.tiles;
  for(let y=TH-1;y>=0;y--){
    const rowTop=t0=>y*T-t0.h*LIFT;
    const x=Math.floor(mx/T);
    if(x<0||x>=TW)continue;
    const t0=tiles[y][x];
    const top=rowTop(t0);
    if(my>=top&&my<top+T)return t0;
  }
  return null;
}
cv.addEventListener('pointerdown',e=>{
  if(!battle||battle.over)return;
  const {x:mx,y:my}=canvasPos(e);
  const t0=pickTile(mx,my); if(!t0)return;
  const wx=t0.x*T+T/2, wy=t0.y*T+T/2;

  // 技能瞄準模式
  if(ui.targeting&&ui.sel&&!ui.sel.dead){useSkill(ui.sel,wx,wy);return;}

  // 點到玩家小隊 → 選取
  let hit=null,bd=T*1.1;
  for(const s of battle.squads){
    if(s.side!=='p'||s.dead)continue;
    const d=dist(s.x,s.y,wx,wy);
    if(d<bd){bd=d;hit=s;}
  }
  if(hit){selectSquad(hit);return;}

  const s=ui.sel;
  if(!s||s.dead)return;

  if(s.onBoat){ // 下令搶灘
    let beach=t0.beach?t0:null;
    if(!beach){let bd2=2.6;
      for(const bt of battle.island.beaches){
        const d=dist(bt.x,bt.y,t0.x,t0.y);
        if(d<bd2){bd2=d;beach=bt;}
      }}
    if(!beach){showMsg('請點選灘頭（淺色沙岸）','#ffe9a8',1.6);return;}
    const boat=battle.boats.find(b2=>b2.squad===s);
    if(!boat)return;
    // 找 beach 旁的海面格
    let landing=null;
    for(const[dx,dy]of[[0,1],[1,0],[-1,0],[0,-1]]){
      const n=battle.island.tiles[beach.y+dy]?.[beach.x+dx];
      if(n&&n.ocean){landing=n;break;}
    }
    if(!landing)return;
    const bTile=tileAt(boat.x,boat.y);
    const p=findPath(bTile.x,bTile.y,landing.x,landing.y,true);
    if(p){boat.path=p;boat.state='sail';boat.beach=beach;
      s.moveMark={x:beach.x,y:beach.y,t:0};}
    return;
  }
  orderMove(s,t0.x,t0.y);
});
document.getElementById('skill-btn').onclick=()=>{
  const s=ui.sel;
  if(!s||!s.skill||s.skillCd>0||s.onBoat)return;
  const sk=SKILLS[s.skill];
  if(sk.targeted){ui.targeting=!ui.targeting;updateSkillBtn();}
  else useSkill(s);
};
window.addEventListener('keydown',e=>{
  if(!battle)return;
  const n=+e.key;
  if(n>=1&&n<=4){
    const ps=battle.squads.filter(s=>s.side==='p');
    if(ps[n-1]&&!ps[n-1].dead)selectSquad(ps[n-1]);
  }
  if(e.key==='q'||e.key==='Q')document.getElementById('skill-btn').click();
});

/* ---------------- 繪製 ---------------- */
const LAND_COLS=['','#d8c58f','#7fb069','#5f9452','#8a8f98'];
const LAND_DARK=['','#b9a672','#5f8c4e','#47723c','#6b7078'];
function render(){
  ctx.clearRect(0,0,CW,CH);
  if(!battle)return;
  const b=battle, tiles=b.island.tiles;

  // 海
  ctx.fillStyle='#2c4a7c'; ctx.fillRect(0,0,CW,CH);
  ctx.fillStyle='rgba(255,255,255,.05)';
  for(let i=0;i<40;i++){
    const wx=(i*97)%CW, wy=(i*211)%CH;
    const ph=Math.sin(b.time*1.5+i)*3;
    ctx.fillRect(wx+ph,wy,10,2);
  }

  // 地形（由上往下畫，偽 2.5D）
  for(let y=0;y<TH;y++)for(let x=0;x<TW;x++){
    const t0=tiles[y][x]; if(t0.h<=0)continue;
    const top=y*T-t0.h*LIFT;
    // 側壁
    ctx.fillStyle=LAND_DARK[t0.h];
    ctx.fillRect(x*T,top+T-1,T,t0.h*LIFT+2);
    // 頂面
    ctx.fillStyle=LAND_COLS[t0.h];
    ctx.fillRect(x*T,top,T,T);
    if(t0.shade>0.5){ctx.fillStyle='rgba(255,255,255,.04)';ctx.fillRect(x*T,top,T,T);}
    else if(t0.shade<-0.5){ctx.fillStyle='rgba(0,0,0,.05)';ctx.fillRect(x*T,top,T,T);}
    if(t0.beach){ctx.fillStyle='rgba(255,244,200,.35)';ctx.fillRect(x*T,top,T,T);}
  }

  // 據點
  for(const h of b.island.houses){
    const t0=h.tile, hx=t0.x*T+T/2, hy=t0.y*T+T/2-t0.h*LIFT;
    ctx.fillStyle=h.captured?'#3f5f9e':'#6e4632';
    ctx.fillRect(hx-8,hy-4,16,10);
    ctx.beginPath();
    ctx.moveTo(hx-10,hy-4);ctx.lineTo(hx,hy-13);ctx.lineTo(hx+10,hy-4);
    ctx.closePath();
    ctx.fillStyle=h.captured?'#5b9bff':'#a8543a';
    ctx.fill();
    // 旗
    ctx.strokeStyle='#e8eefc';ctx.beginPath();
    ctx.moveTo(hx+8,hy-4);ctx.lineTo(hx+8,hy-20);ctx.stroke();
    ctx.fillStyle=h.captured?'#5b9bff':'#ef7a6d';
    ctx.fillRect(hx+8,hy-20,8,5);
    if(!h.captured&&h.progress>0){
      ctx.fillStyle='#101628';ctx.fillRect(hx-12,hy-26,24,4);
      ctx.fillStyle='#8ab4ff';ctx.fillRect(hx-12,hy-26,24*h.progress,4);
    }
  }

  // 移動標記
  const s=ui.sel;
  if(s&&!s.dead&&s.moveMark&&s.moveMark.t<1.2){
    const m=s.moveMark, t0=tiles[m.y][m.x];
    const mx=m.x*T+T/2, my=m.y*T+T/2-t0.h*LIFT;
    ctx.strokeStyle='rgba(255,255,255,.8)';
    ctx.beginPath();ctx.arc(mx,my,8+Math.sin(b.time*6)*2,0,6.28);ctx.stroke();
  }

  // 船
  for(const bt of b.boats){
    if(bt.state==='landed')continue;
    const bx=bt.x, by=bt.y+Math.sin(bt.bob)*1.5;
    ctx.fillStyle='#7a5a3a';
    ctx.beginPath();
    ctx.moveTo(bx-14,by);ctx.lineTo(bx+14,by);ctx.lineTo(bx+9,by+7);ctx.lineTo(bx-9,by+7);
    ctx.closePath();ctx.fill();
    ctx.strokeStyle='#caa'; ctx.beginPath();ctx.moveTo(bx,by);ctx.lineTo(bx,by-14);ctx.stroke();
    ctx.fillStyle=squadColor(bt.squad);
    ctx.fillRect(bx,by-14,9,5);
  }

  // 士兵（按 y 排序）
  const draws=[];
  for(const sq of b.squads){
    if(sq.dead)continue;
    if(sq.onBoat){continue;}
    for(const so of sq.soldiers)draws.push({so,sq});
  }
  draws.sort((a,b2)=>a.so.y-b2.so.y);
  for(const {so,sq} of draws){
    const t0=tileAt(so.x,so.y);
    const lift=(t0?t0.h:0)*LIFT;
    const px=so.x, py=so.y-lift;
    ctx.fillStyle='rgba(0,0,0,.25)';
    ctx.beginPath();ctx.ellipse(px,py+3,4,2,0,0,6.28);ctx.fill();
    ctx.fillStyle=squadColor(sq);
    ctx.beginPath();ctx.arc(px,py,3.6,0,6.28);ctx.fill();
    ctx.fillStyle='rgba(255,255,255,.55)';
    ctx.beginPath();ctx.arc(px-1,py-1.4,1.2,0,6.28);ctx.fill();
    if(sq.buff.wall>0){
      ctx.strokeStyle='rgba(155,140,240,.7)';
      ctx.beginPath();ctx.arc(px,py,5.4,0,6.28);ctx.stroke();
    }
  }

  // 小隊旗（選取圈 + 人數）
  for(const sq of b.squads){
    if(sq.dead)continue;
    const t0=tileAt(sq.x,sq.y);
    const lift=(t0&&!sq.onBoat?t0.h:0)*LIFT;
    const px=sq.x, py=sq.y-lift;
    if(sq===ui.sel){
      ctx.strokeStyle='rgba(255,255,255,.9)';
      ctx.setLineDash([4,4]);
      ctx.beginPath();ctx.arc(px,py,15+Math.sin(b.time*5)*1.5,0,6.28);ctx.stroke();
      ctx.setLineDash([]);
    }
    if(!sq.onBoat){
      ctx.fillStyle='rgba(12,18,34,.75)';
      ctx.beginPath();ctx.arc(px,py-16,7,0,6.28);ctx.fill();
      ctx.fillStyle=squadColor(sq);
      ctx.font='bold 9px sans-serif';ctx.textAlign='center';ctx.textBaseline='middle';
      ctx.fillText(sq.soldiers.length,px,py-15.5);
    }
  }

  // 箭矢
  for(const a of b.arrows){
    const k=a.t/a.T;
    const x=a.sx+(a.tx-a.sx)*k, y=a.sy+(a.ty-a.sy)*k - Math.sin(k*Math.PI)*26;
    const x2=a.sx+(a.tx-a.sx)*Math.min(1,k+.06),
          y2=a.sy+(a.ty-a.sy)*Math.min(1,k+.06)-Math.sin(Math.min(1,k+.06)*Math.PI)*26;
    ctx.strokeStyle=a.side==='p'?'#d9ecff':'#ffd9c9';
    ctx.beginPath();ctx.moveTo(x,y);ctx.lineTo(x2,y2);ctx.stroke();
  }

  // 特效
  for(const f of b.effects){
    const k=f.t/f.T;
    if(f.type==='ring'){
      ctx.strokeStyle=f.color; ctx.globalAlpha=1-k;
      ctx.beginPath();ctx.arc(f.x,f.y,4+k*26,0,6.28);ctx.stroke();
    } else if(f.type==='splash'){
      ctx.fillStyle=f.color; ctx.globalAlpha=1-k;
      for(let i=0;i<5;i++){
        const a2=i/5*6.28;
        ctx.beginPath();
        ctx.arc(f.x+Math.cos(a2)*k*14,f.y+Math.sin(a2)*k*10-k*8,2,0,6.28);
        ctx.fill();
      }
    } else {
      ctx.fillStyle=f.color; ctx.globalAlpha=(1-k)*.9;
      ctx.beginPath();ctx.arc(f.x,f.y,2+k*4,0,6.28);ctx.fill();
    }
    ctx.globalAlpha=1;
  }

  // 瞄準模式提示框
  if(ui.targeting){
    ctx.strokeStyle='rgba(242,197,107,.9)';
    ctx.setLineDash([8,6]);
    ctx.strokeRect(3,3,CW-6,CH-6);
    ctx.setLineDash([]);
  }
}

/* ---------------- 主迴圈 ---------------- */
let lastT=0, hudT=0;
function loop(ts){
  const dt=Math.min(.05,(ts-lastT)/1000||0); lastT=ts;
  if(battle&&document.getElementById('scr-battle').classList.contains('on')){
    update(dt);
    hudT+=dt;
    if(hudT>.25){hudT=0;renderSquadBar();updateSkillBtn();}
  }
  render();
  requestAnimationFrame(loop);
}

/* ---------------- 啟動 ---------------- */
function begin(seed){
  newRun(seed);
  showCampaign();
}
document.getElementById('bt-start').onclick=()=>{
  const v=document.getElementById('seed-in').value.trim();
  const seed=v? (isNaN(+v)? [...v].reduce((a,c)=>a*31+c.charCodeAt(0)>>>0,7):+v)
              : Math.floor(Math.random()*1e9);
  begin(seed);
};
document.getElementById('bt-how').onclick=()=>{
  const m=document.getElementById('modal');
  m.innerHTML=`<div class="box"><h3 style="margin:0 0 10px">玩法</h3>
    <div class="stat" style="text-align:left">
    ・點小隊（或按 <b>1–4</b>）選取 → 點灘頭登陸、點地面移動<br>
    ・站上<b>敵方據點</b>並守住即可佔領；佔領全部據點並肅清守軍獲勝<br>
    ・<b>Q</b> 或點下方按鈕發動技能；「衝鋒」可把敵兵撞下海<br>
    ・每座島之後選擇戰利品：新小隊／老兵／技能／軍旗<br>
    ・小隊全滅便永遠失去——謹慎用兵，指揮官
    </div>
    <button class="btn primary" style="margin-top:16px" onclick="document.getElementById('modal').classList.remove('on')">了解</button></div>`;
  m.classList.add('on');
};
document.getElementById('bt-again').onclick=()=>begin(Math.floor(Math.random()*1e9));
document.getElementById('bt-same').onclick=()=>begin(run.seed);
try{
  const best=+localStorage.getItem('islandraid.best')||0;
  if(best>0)document.getElementById('best').textContent=`最佳紀錄：${best} 座島`;
}catch(e){}

/* 自動測試模式：?auto 直接開局並登陸（供截圖／冒煙測試） */
if(location.search.includes('auto')){
  begin(12345);
  startBattle(run.campaign[0][0]);
  setTimeout(()=>{
    battle.boats.forEach((bt,i)=>{
      const beach=battle.island.beaches[(i*3)%battle.island.beaches.length];
      if(!beach)return;
      let landing=null;
      for(const[dx,dy]of[[0,1],[1,0],[-1,0],[0,-1]]){
        const n=battle.island.tiles[beach.y+dy]?.[beach.x+dx];
        if(n&&n.ocean){landing=n;break;}
      }
      if(!landing)return;
      const bTile=tileAt(bt.x,bt.y);
      const p=findPath(bTile.x,bTile.y,landing.x,landing.y,true);
      if(p){bt.path=p;bt.state='sail';bt.beach=beach;}
    });
  },300);
}

requestAnimationFrame(loop);
