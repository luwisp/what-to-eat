import test from 'node:test';
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {once} from 'node:events';
import {createServer} from 'node:net';
import WebSocket from 'ws';

async function server(t){
 const reserve=createServer();reserve.listen(0,'127.0.0.1');await once(reserve,'listening');const port=reserve.address().port;await new Promise(r=>reserve.close(r));
 let output='';const child=spawn('bash',['scripts/cj.sh','exec','target/integration/dining-server'],{env:{...process.env,HUAIWEI_PORT:String(port)},stdio:['ignore','pipe','pipe']});
 child.stdout.on('data',x=>{output+=x});child.stderr.on('data',x=>{output+=x});const exited=once(child,'exit');
 t.after(async()=>{if(child.exitCode===null)child.kill();await exited});
 const origin=`http://127.0.0.1:${port}`;
 for(let i=0;i<100;i++){if(child.exitCode!==null)assert.fail(output);try{if((await fetch(origin+'/health')).ok)return{origin,port}}catch{}await new Promise(r=>setTimeout(r,40))}assert.fail(output);
}
async function client(t,origin){const response=await fetch(origin+'/api/visitor/session',{method:'POST'});const cookie=response.headers.get('set-cookie').split(';')[0];const s=new WebSocket(origin.replace('http:','ws:')+'/ws',{headers:{Cookie:cookie,Origin:origin}});await once(s,'open');t.after(()=>s.terminate());
 const messages=[];s.on('message',b=>messages.push(JSON.parse(b.toString())));
 async function wait(predicate){for(let i=0;i<200;i++){const found=messages.find(predicate);if(found)return found;await new Promise(r=>setTimeout(r,15))}assert.fail('Expected message missing: '+JSON.stringify(messages))}
 return{cookie,s,messages,wait,send(type,payload){const requestId=crypto.randomUUID();s.send(JSON.stringify({type,requestId,payload}));return wait(m=>m.requestId===requestId)},state(){return messages.filter(x=>x.type==='room_state').at(-1)?.payload}};
}
const prefs={allergens:[],avoidFoods:[],dietMode:'none',maxSpiceLevel:null,tastePreferences:[],wantedDishIds:[],wantedSetMealIds:[],note:''};
test('two real WS clients: invite first, submit, recommend, confirm, invalidate and reconnect',{timeout:20000},async t=>{
 const{origin}=await server(t);const a=await client(t,origin);const b=await client(t,origin);
 const r=await fetch(origin+'/api/sessions',{method:'POST',headers:{Cookie:a.cookie,'Content-Type':'application/json',Origin:origin},body:JSON.stringify({restaurantCode:'TEST',people:2,budgetPerPersonFen:null,requestId:'create'})});assert.equal(r.status,201);const created=await r.json();
 const joinedA=await a.send('join_room',{code:created.session.roomCode});assert.equal(joinedA.payload.self.submitted,false);
 const joinedB=await b.send('join_room',{code:created.session.roomCode});assert.equal(joinedB.payload.session.id,created.session.id);
 const guestId=joinedB.payload.self.id;await b.send('update_preferences',{prefs:{...prefs,note:'先填写'},submit:true,expectedVersion:joinedB.payload.stateVersion});
 await a.wait(m=>m.type==='room_state'&&m.payload.members.some(x=>x.id===guestId&&x.submitted));
 const filledA=await a.send('update_preferences',{prefs,submit:true,expectedVersion:a.state().stateVersion});assert.equal(filledA.type,'room_state');
 const started=await a.send('request_recommendation',{});assert.equal(started.type,'recommendation_started');
 const result=await a.wait(m=>m.type==='room_state'&&m.payload.recommendation&&!m.payload.recommendationInvalid);const state=result.payload;assert.equal(state.recommendation.canConfirm,true);assert.equal(state.recommendation.mode,'rules');
 const denied=await b.send('confirm_recommendation',{id:state.recommendation.id,version:state.stateVersion,expectedVersion:state.stateVersion});assert.equal(denied.type,'error');assert.equal(denied.payload.code,'FORBIDDEN');
 const closed=await a.send('confirm_recommendation',{id:state.recommendation.id,version:state.stateVersion,expectedVersion:state.stateVersion});assert.equal(closed.payload.session.state,'closed');
 await fetch(origin+'/__test/menu-change',{method:'POST'});await a.wait(m=>m.type==='room_state'&&m.payload.recommendationInvalid&&m.payload.menuVersion===2);
 const reopen=await a.send('reopen_recommendation',{expectedVersion:a.state().stateVersion});assert.equal(reopen.payload.session.state,'open');
 b.s.close();await once(b.s,'close');const reconnect=new WebSocket(origin.replace('http:','ws:')+'/ws',{headers:{Cookie:b.cookie,Origin:origin}});await once(reconnect,'open');t.after(()=>reconnect.terminate());const reply=once(reconnect,'message');reconnect.send(JSON.stringify({type:'join_room',requestId:'rejoin',payload:{code:created.session.roomCode}}));const [raw]=await reply;const snapshot=JSON.parse(raw);assert.equal(snapshot.payload.self.id,guestId);assert.equal(snapshot.payload.members.length,2);
});

test('Cangjie serves both SPA deep links and assets while unknown API stays JSON',async t=>{
 const {origin}=await server(t);
 for(const path of ['/','/r/TEST','/s/A3F9/preferences','/admin/']){
  const response=await fetch(origin+path);assert.equal(response.status,200,path);assert.match(response.headers.get('content-type'),/text\/html/);const html=await response.text();assert.match(html,/id="app"/);
  const asset=html.match(/src="(\/assets\/[^\"]+\.js)"/)?.[1];assert.ok(asset,'Built entry script missing');const js=await fetch(origin+asset);assert.equal(js.status,200);assert.match(js.headers.get('content-type'),/javascript/);
 }
 const missing=await fetch(origin+'/api/missing');assert.equal(missing.status,404);assert.equal((await missing.json()).error.code,'NOT_FOUND');
 const traversal=await fetch(origin+'/assets/..%2f..%2fcjpm.toml');assert.equal(traversal.status,404);
});
