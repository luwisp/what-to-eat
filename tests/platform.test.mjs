import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:net';
import { once } from 'node:events';
import test from 'node:test';
import WebSocket from 'ws';

async function withServer(t, probe = true) {
  const reservation = createServer();
  reservation.listen(0, '127.0.0.1');
  await once(reservation, 'listening');
  const port = reservation.address().port;
  await new Promise(resolve => reservation.close(resolve));
  let output = '';
  const child = spawn('bash', ['scripts/cj.sh', 'exec', 'target/release/bin/main'], {
    env: { ...process.env, HUAIWEI_PORT: String(port), HUAIWEI_ENABLE_PROBES: probe ? 'true' : 'false' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  child.stdout.on('data', data => { output += data; });
  child.stderr.on('data', data => { output += data; });
  const closed = once(child, 'exit');
  t.after(async () => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGTERM');
    await closed;
  });
  const origin = `http://127.0.0.1:${port}`;
  for (let attempt = 0; attempt < 80; attempt++) {
    if (child.exitCode !== null || child.signalCode !== null) {
      assert.fail(`Server exited before providing /health: ${output}`);
    }
    try {
      const response = await fetch(`${origin}/health`, { signal: AbortSignal.timeout(200) });
      if (response.ok) return { origin, port };
    } catch { /* Wait only while the real server is starting. */ }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.fail(`Server never became healthy: ${output}`);
}

test('health is JSON and unknown API paths do not return application HTML', async t => {
  const { origin } = await withServer(t);
  const response = await fetch(`${origin}/health`);
  assert.equal(response.status, 200);
  assert.match(response.headers.get('content-type'), /application\/json/);
  assert.deepEqual(await response.json(), { status: 'ok', sdk: '1.2.0' });
  const missing = await fetch(`${origin}/api/not-a-route`);
  assert.equal(missing.status, 404);
  assert.equal((await missing.json()).error.code, 'NOT_FOUND');
});

async function echo(port, value) {
  const socket = new WebSocket(`ws://127.0.0.1:${port}/__probe/ws`);
  try {
    await once(socket, 'open');
    const reply = once(socket, 'message');
    socket.send(value);
    const [data] = await reply;
    assert.equal(data.toString(), value);
    const close = once(socket, 'close');
    socket.close();
    await close;
  } finally {
    if (socket.readyState !== WebSocket.CLOSED) socket.terminate();
  }
}

test('two WebSocket clients exchange independent messages and reconnect', { timeout: 12000 }, async t => {
  const { port } = await withServer(t);
  await Promise.all([echo(port, '同行人A'), echo(port, '同行人B')]);
  await echo(port, '重新连接');
});

test('test-only WebSocket probe is absent in normal server mode', async t => {
  const { origin } = await withServer(t, false);
  const response = await fetch(`${origin}/__probe/ws`);
  assert.equal(response.status, 404);
});
