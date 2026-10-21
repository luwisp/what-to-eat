import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { once } from 'node:events';
import test from 'node:test';

test('production startup, account isolation, logout and SQLite restart persistence', { timeout: 90000 }, async t => {
  const directory = await mkdtemp(join(tmpdir(), 'juxiaobao-auth-'));
  const db = join(directory, 'app.sqlite');
  const reservation = createServer();
  reservation.listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  const origin = `http://127.0.0.1:${port}`;
  let child, closed, output = '';
  async function stop() {
    if (child && child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
    if (closed) await closed;
  }
  t.after(async () => { await stop(); await rm(directory, {recursive:true, force:true}); });
  async function start(launcher) {
    const env = {...process.env, JUXIAOBAO_HOST:'127.0.0.1', JUXIAOBAO_PORT:String(port),
      JUXIAOBAO_DB_PATH:db, JUXIAOBAO_ENV_FILE:'/dev/null', DEEPSEEK_API_KEY:'', DEEPSEEK_MODEL:''};
    delete env.JUXIAOBAO_PUBLIC_BASE_URL;
    output = '';
    child = spawn('bash', launcher ? ['scripts/dev.sh'] : ['scripts/cj.sh','exec','target/release/bin/juxiaobao'], {env, stdio:['ignore','pipe','pipe']});
    closed = once(child, 'exit');
    child.stdout.on('data', d => output += d);
    child.stderr.on('data', d => output += d);
    for (let n=0;n<1000;n++) {
      if (child.exitCode !== null || child.signalCode !== null) assert.fail(output);
      try { if ((await fetch(origin+'/health', {signal:AbortSignal.timeout(200)})).ok) return; } catch {}
      await new Promise(resolve => setTimeout(resolve,50));
    }
    assert.fail('startup timeout: '+output);
  }
  async function request(path, method='GET', body, cookie='') {
    return fetch(origin+path, {method, headers:{origin, cookie, ...(body===undefined?{}:{'content-type':'application/json'})},
      body:body===undefined?undefined:JSON.stringify(body), signal:AbortSignal.timeout(10000)});
  }
  function cookie(response) { return response.headers.get('set-cookie').split(';')[0]; }
  // Exercise the documented launcher on a completely new database.
  await start(true);
  assert.match(output, new RegExp(`Consumer account: http://127.0.0.1:${port}/account`));
  for (const path of ['/', '/account', '/admin/', '/r/LAOXIANGJI', '/r/LAOXIANGJI/menu']) {
    const response = await request(path);
    assert.equal(response.status,200,path);
    assert.match(response.headers.get('content-type'),/text\/html/);
  }
  assert.equal((await request('/api/restaurants/LAOXIANGJI/menu')).status,200);
  const visitor = cookie(await request('/api/visitor/session','POST'));
  const account = {login:'audit-user',password:'audit-password-123'};
  assert.equal((await request('/api/user/register','POST',{...account,password:'short'})).status,400);
  assert.equal((await request('/api/user/register','POST',account)).status,201);
  assert.equal((await request('/api/user/register','POST',account)).status,409);
  assert.equal((await request('/api/user/login','POST',{...account,password:'wrong-password'})).status,401);
  const auth = cookie(await request('/api/user/login','POST',account,visitor));
  const both = visitor+'; '+auth;
  assert.equal((await request('/api/user/profile','PATCH',{nickname:'测试用户名'})).status,401);
  assert.equal((await request('/api/user/profile','PATCH',{nickname:'x'.repeat(41)},both)).status,400);
  assert.equal((await request('/api/user/profile','PATCH',{nickname:'bad\nname'},both)).status,400);
  assert.equal((await request('/api/user/profile','PATCH',{nickname:'我的用户名',userId:'other'},both)).status,400);
  const profile = await request('/api/user/profile','PATCH',{nickname:'  我的用户名  '},both);
  assert.equal(profile.status,200);
  assert.equal((await profile.json()).nickname,'我的用户名');
  const settings = {appetite:'large',allergens:['花生'],avoidFoods:['香菜'],dietMode:'none',maxSpiceLevel:1,tastePreferences:['清淡']};
  assert.equal((await request('/api/user/default-settings','PUT',settings,both)).status,200);
  assert.equal((await request('/api/user/default-settings','GET')).status,401);
  assert.equal((await request('/api/merchant/me','GET',undefined,both)).status,401);
  const roomResponse = await request('/api/sessions','POST',{restaurantCode:'LAOXIANGJI',people:1,budgetPerPersonFen:null,requestId:'audit-room'},both);
  assert.equal(roomResponse.status,201);
  const room = await roomResponse.json();
  const code = room.session.roomCode;
  const id = room.self.id;
  assert.equal(room.self.nickname,'我的用户名');
  await stop();
  // Also exercise the bare compiled entry's default origin, with the same DB.
  await start(false);
  assert.equal((await (await request('/api/user/me','GET',undefined,both)).json()).nickname,'我的用户名');
  const restored = await (await request('/api/user/default-settings','GET',undefined,both)).json();
  for (const [key,value] of Object.entries(settings)) assert.deepEqual(restored[key],value,key);
  assert.equal((await (await request('/api/sessions/'+code,'GET',undefined,both)).json()).self.id,id);
  assert.equal((await request('/api/user/logout','POST',undefined,both)).status,204);
  assert.equal((await request('/api/user/me','GET',undefined,both)).status,401);
  assert.equal((await (await request('/api/sessions/'+code,'GET',undefined,visitor)).json()).self.id,id);
  assert.equal((await request('/api/user/login','POST',account,visitor)).status,200);
  assert.equal((await request('/api/merchant/register','POST',account)).status,201);
  const merchant = cookie(await request('/api/merchant/login','POST',account));
  assert.equal((await request('/api/merchant/me','GET',undefined,merchant)).status,200);
  assert.equal((await request('/api/user/me','GET',undefined,merchant)).status,401);
  assert.equal((await request('/api/merchant/restaurant','POST',{name:'上传图片测试店',description:''},merchant)).status,204);
  assert.equal((await request('/api/merchant/images','POST',{data:'invalid'})).status,401);
  assert.equal((await request('/api/merchant/images','POST',{data:Buffer.from('<svg>bad</svg>').toString('base64')},merchant)).status,400);
  assert.equal((await request('/api/merchant/images','POST',{data:'A'.repeat(2800001)},merchant)).status,413);
  const menu = await (await request('/api/restaurants/LAOXIANGJI/menu')).json();
  const imageBytes=Buffer.from(await (await request(menu.dishes.find(d=>d.imageUrl).imageUrl)).arrayBuffer());
  const uploaded = await request('/api/merchant/images','POST',{data:imageBytes.toString('base64')},merchant);
  assert.equal(uploaded.status,201);
  const uploadedUrl=(await uploaded.json()).imageUrl;
  assert.match(uploadedUrl,/^\/uploads\/menu\/[a-zA-Z0-9-]+\.(jpg|png|webp)$/);
  assert.equal((await request(uploadedUrl)).headers.get('x-content-type-options'),'nosniff');
  await stop();await start(false);
  assert.deepEqual(Buffer.from(await (await request(uploadedUrl)).arrayBuffer()),imageBytes);
  assert.equal((await request('/api/merchant/logout','POST',undefined,merchant)).status,204);
  assert.equal((await request('/api/merchant/me','GET',undefined,merchant)).status,401);
});
