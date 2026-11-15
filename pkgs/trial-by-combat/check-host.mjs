// Install check: start the installed launcher on a free loopback port, then
// drive the player HTTP API and the admin and spectator consoles through a
// lobby into a running match.
//
// usage: node check-host.mjs LAUNCHER

import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import readline from 'node:readline';

const [launcher] = process.argv.slice(2);
const TIMEOUT_MS = 10000;

function withTimeout(promise, what) {
  let timer;
  return Promise.race([
    promise.finally(() => clearTimeout(timer)),
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`timed out waiting for ${what}`)), TIMEOUT_MS);
    }),
  ]);
}

async function get(base, path) {
  const response = await withTimeout(fetch(`${base}${path}`), `GET ${path}`);
  assert.equal(response.status, 200, `GET ${path} returned ${response.status}`);
  return response;
}

async function post(base, path, body) {
  const response = await withTimeout(
    fetch(`${base}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: body == null ? undefined : JSON.stringify(body),
    }),
    `POST ${path}`,
  );
  const text = await response.text();
  assert.equal(response.status, 200, `POST ${path} returned ${response.status}: ${text}`);
  return text;
}

// A console client that records every state frame the server pushes.
async function openConsole(wsBase, role) {
  const ws = new WebSocket(`${wsBase}/ws?player=${role}`);
  const frames = [];
  const waiters = new Set();
  ws.addEventListener('message', (event) => {
    const message = JSON.parse(String(event.data));
    if (message.type !== 'state') return;
    assert.equal(message.role, role, `unexpected role on the ${role} console`);
    frames.push(message.state);
    for (const waiter of waiters) waiter();
  });
  await withTimeout(
    new Promise((resolve, reject) => {
      ws.addEventListener('open', resolve, { once: true });
      ws.addEventListener('error', () => reject(new Error(`${role} console failed to connect`)), {
        once: true,
      });
    }),
    `the ${role} console`,
  );
  return {
    close: () => ws.close(),
    send: (message) => ws.send(JSON.stringify(message)),
    // A frame received before an action must not satisfy a wait for its
    // effect, so callers take a mark first and wait past it.
    mark: () => frames.length,
    until(predicate, what, from = 0) {
      return withTimeout(
        new Promise((resolve) => {
          const check = () => {
            const match = frames.slice(from).findLast(predicate);
            if (match) {
              waiters.delete(check);
              resolve(match);
            }
          };
          waiters.add(check);
          check();
        }),
        `${role} console: ${what}`,
      );
    },
  };
}

async function checkClientAssets(base) {
  for (const role of ['spectate', 'admin']) {
    const page = await (await get(base, `/?player=${role}`)).text();
    assert.match(page, /Trial by Combat/);
    assert.ok(page.includes('/client/vendor/pixi.min.js'), `${role} page lacks the packaged renderer`);
    assert.ok(!page.includes('cdn.jsdelivr.net'), `${role} page still references a CDN`);
  }
  const styles = await (await get(base, '/client/styles.css')).text();
  assert.ok(styles.includes('/client/vendor/PressStart2P-v16.ttf'), 'stylesheet lacks the packaged face');
  assert.ok(!/fonts\.(googleapis|gstatic)\.com/.test(styles), 'stylesheet still references Google Fonts');

  const renderer = await (await get(base, '/client/vendor/pixi.min.js')).text();
  assert.match(renderer.slice(0, 200), /PixiJS - v8\.2\.6/);

  const face = Buffer.from(await (await get(base, '/client/vendor/PressStart2P-v16.ttf')).arrayBuffer());
  // TrueType name records are UTF-16BE.
  const familyName = Buffer.from('Press Start 2P', 'utf16le').swap16();
  assert.equal(face.readUInt32BE(0), 0x00010000, 'served font is not TrueType');
  assert.ok(face.includes(familyName), 'served font is not Press Start 2P');
}

async function playOneTurn(base, wsBase) {
  const lobby = await (await get(base, '/player1?nowait=true')).text();
  assert.ok(lobby.includes('=== TRIAL BY COMBAT - player1 (BLUE) ==='), 'player1 view header missing');
  assert.ok(lobby.includes('Phase: pre_lobby'), 'player1 view is not in the lobby');

  const admin = await openConsole(wsBase, 'admin');
  const spectator = await openConsole(wsBase, 'spectate');
  try {
    await admin.until((state) => state.phase === 'pre_lobby', 'lobby state');
    await spectator.until((state) => state.phase === 'pre_lobby', 'lobby state');

    let mark = admin.mark();
    admin.send({ type: 'admin', action: 'set_series_length', bestOf: 3 });
    await admin.until((state) => state.match?.best_of === 3, 'best-of-3 series', mark);

    mark = spectator.mark();
    await post(base, '/player1/join', { name: 'Check Blue' });
    await post(base, '/player2/join', { name: 'Check Red' });
    await post(base, '/player1/ready');
    await post(base, '/player2/ready');
    const running = await spectator.until(
      (state) => state.phase === 'match' && state.full_board_state?.players?.blue,
      'running match',
      mark,
    );
    assert.equal(running.full_board_state.size, 9);

    mark = spectator.mark();
    const wait = { action: 'WAIT', intent: 'The install check waits to watch the arena.' };
    assert.match(await post(base, '/player1/action', wait), /^Action accepted/);
    assert.match(await post(base, '/player2/action', wait), /^Action accepted/);
    await spectator.until((state) => state.phase === 'match' && state.turn === 1, 'resolved turn', mark);

    mark = admin.mark();
    admin.send({ type: 'admin', action: 'pause' });
    await admin.until((state) => state.paused === true, 'pause', mark);
    mark = admin.mark();
    admin.send({ type: 'admin', action: 'resume' });
    await admin.until((state) => state.paused === false && state.phase === 'match', 'resume', mark);
  } finally {
    admin.close();
    spectator.close();
  }
}

// Port 0 asks for a free port; the banner names the one chosen.
const server = spawn(launcher, [], {
  env: { ...process.env, PORT: '0' },
  stdio: ['ignore', 'pipe', 'inherit'],
});
const exited = once(server, 'exit');
const banners = readline.createInterface({ input: server.stdout });
try {
  const [banner] = await withTimeout(once(banners, 'line'), 'the listening banner');
  const port = banner.match(/^Trial by Combat listening on http:\/\/localhost:(\d+)$/)?.[1];
  assert.ok(port, `unexpected banner: ${banner}`);

  await checkClientAssets(`http://127.0.0.1:${port}`);
  console.log('client assets: renderer and arcade face served by the package');
  await playOneTurn(`http://127.0.0.1:${port}`, `ws://127.0.0.1:${port}`);
  console.log('match: both seats joined, readied and resolved turn 1; pause and resume applied');
} finally {
  server.kill();
  await exited;
}
