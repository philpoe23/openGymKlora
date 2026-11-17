/* Password sign-in for a native client (the Flutter app): with `token: true` in the body the 200
   also carries the signed session value, which that client then sends as `Authorization: Bearer`.
   Without it the response is the browser one, cookie only. Real server.js in a child, the same
   harness as server-password.test.js. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { boundPort } from './helpers.mjs';

const API = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const ORIGIN = 'http://localhost:8080';
const GOOD = 'correct horse battery staple';

async function startServer(t) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gym-tok-'));
  fs.writeFileSync(path.join(dataDir, 'db.json'), JSON.stringify({ users: [], creds: [], subs: [], invites: [] }));
  const child = spawn(process.execPath, ['server.js'], {
    cwd: API, stdio: ['ignore', 'pipe', 'pipe'],
    env: {
      ...process.env, PORT: '0', DATA_DIR: dataDir, ORIGIN, RP_ID: 'localhost',
      PASSWORD_LOGIN: '1', TRUST_PROXY: '1', INVITE_ONLY: '', ADMIN_UIDS: ''
    }
  });
  const h = { api: '', log: '' };
  child.stdout.on('data', d => h.log += d);
  child.stderr.on('data', d => h.log += d);
  t.after(() => { child.kill('SIGKILL'); fs.rmSync(dataDir, { recursive: true, force: true }); });
  h.api = `http://127.0.0.1:${await boundPort(child, () => h.log)}`;
  h.req = async (method, p, { body, ip = '198.51.100.1', headers = {} } = {}) => {
    const r = await fetch(`${h.api}${p}`, {
      method,
      headers: { 'Content-Type': 'application/json', 'Sec-Fetch-Site': 'same-origin', 'X-Forwarded-For': ip, ...headers },
      body: body === undefined ? undefined : JSON.stringify(body)
    });
    return { status: r.status, body: await r.json(), headers: r.headers };
  };
  return h;
}

async function register(h, name, ip) {
  const r = await h.req('POST', '/api/register/password', { body: { name, password: GOOD }, ip });
  assert.equal(r.status, 200, JSON.stringify(r.body));
  return r.body.user;
}

test('token: true returns a bearer token that /api/me accepts without a cookie', async t => {
  const h = await startServer(t);
  const u = await register(h, 'Ana', '198.51.100.10');
  const r = await h.req('POST', '/api/login/password', { body: { name: 'Ana', password: GOOD, token: true }, ip: '198.51.100.11' });
  assert.equal(r.status, 200);
  assert.equal(typeof r.body.token, 'string');
  assert.ok(r.body.token.length > 0);
  assert.equal(r.body.user.id, u.id);
  // The browser cookie is still set alongside it.
  assert.ok(r.headers.getSetCookie().some(c => c.includes(r.body.token)));
  const me = await h.req('GET', '/api/me', { headers: { Authorization: `Bearer ${r.body.token}` }, ip: '198.51.100.12' });
  assert.equal(me.status, 200);
  assert.equal(me.body.user.id, u.id);
  assert.equal(me.body.user.name, 'Ana');
});

test('without token: true the body carries no token', async t => {
  const h = await startServer(t);
  await register(h, 'Bea', '198.51.100.20');
  const r = await h.req('POST', '/api/login/password', { body: { name: 'Bea', password: GOOD }, ip: '198.51.100.21' });
  assert.equal(r.status, 200);
  assert.equal('token' in r.body, false);
  // Only the literal true asks for one.
  const s = await h.req('POST', '/api/login/password', { body: { name: 'Bea', password: GOOD, token: 'yes' }, ip: '198.51.100.22' });
  assert.equal(s.status, 200);
  assert.equal('token' in s.body, false);
});

test('a wrong password with token: true is still a 401 and no token', async t => {
  const h = await startServer(t);
  await register(h, 'Cy', '198.51.100.30');
  const r = await h.req('POST', '/api/login/password', { body: { name: 'Cy', password: 'not the right one at all', token: true }, ip: '198.51.100.31' });
  assert.equal(r.status, 401);
  assert.equal('token' in r.body, false);
});
