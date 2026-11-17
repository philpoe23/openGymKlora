/* Trainer ↔ client routes end to end, on the real server.js in a child: the trainer sends a
   routine and a reply, the client sees both but never her notes, and a client cannot reach the
   trainer routes at all. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { boundPort } from './helpers.mjs';

const API = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const SECRET = crypto.randomBytes(32).toString('hex');
function mintSession(uid) {
  const payload = `${uid}:${Date.now() + 86400000}:0`;
  return payload + '.' + crypto.createHmac('sha256', SECRET).update(payload).digest('base64url');
}
const PT = 'u_pt_1', CLIENT = 'u_cl_1';
const as = uid => ({ Cookie: `gymsid=${mintSession(uid)}`, 'Content-Type': 'application/json' });
const plan = { opengym_plan: 1, unit: 'kg', routines: [{ id: 'r1', name: 'Glutes A', ex: [{ id: '0001', sets: 3, reps: 10 }] }], week: {}, customEx: [] };

async function startServer(t) {
  const dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'gym-training-'));
  fs.writeFileSync(path.join(dataDir, 'secret'), SECRET, { mode: 0o600 });
  fs.writeFileSync(path.join(dataDir, 'db.json'), JSON.stringify({
    users: [
      { id: PT, name: 'Klora', created: new Date().toISOString(), admin: true },
      { id: CLIENT, name: 'Sam', created: new Date().toISOString() }
    ], creds: [], subs: [], invites: []
  }));
  fs.writeFileSync(path.join(dataDir, `state-${CLIENT}.json`), JSON.stringify({ unit: 'kg', workouts: [{ id: 'w', d: new Date().toISOString().slice(0, 10), entries: [] }] }));
  const child = spawn(process.execPath, ['server.js'], {
    cwd: API, stdio: ['ignore', 'pipe', 'pipe'],
    env: { ...process.env, PORT: '0', DATA_DIR: dataDir, ORIGIN: 'http://localhost:8080', RP_ID: 'localhost' }
  });
  let log = '';
  child.stdout.on('data', d => log += d);
  child.stderr.on('data', d => log += d);
  t.after(() => { child.kill('SIGKILL'); fs.rmSync(dataDir, { recursive: true, force: true }); });
  const port = await boundPort(child, () => log);
  const call = async (who, method, p, body) => {
    const r = await fetch(`http://127.0.0.1:${port}${p}`, { method, headers: as(who), ...(body ? { body: JSON.stringify(body) } : {}) });
    return { status: r.status, body: await r.json() };
  };
  return { call, dataDir };
}

test('trainer assigns, notes and replies; the client sees all but the notes', async t => {
  const { call } = await startServer(t);
  let r = await call(PT, 'GET', '/api/trainer/clients');
  assert.equal(r.status, 200);
  assert.deepEqual(r.body.clients.map(c => c.name), ['Sam'], 'the trainer is not her own client');
  assert.equal(r.body.clients[0].week, 1);

  assert.equal((await call(CLIENT, 'POST', '/api/client/message', { text: 'Legs done, felt great' })).status, 200);
  r = await call(PT, 'GET', '/api/trainer/clients');
  assert.equal(r.body.clients[0].unread, 1);

  assert.equal((await call(PT, 'POST', '/api/trainer/client/note', { id: CLIENT, text: 'PRIVATE: watch left knee' })).status, 200);
  const a = await call(PT, 'POST', '/api/trainer/client/assign', { id: CLIENT, note: 'Mon + Thu', bundle: plan });
  assert.equal(a.status, 200);
  assert.equal(a.body.assignment.name, 'Glutes A');
  assert.equal((await call(PT, 'POST', '/api/trainer/client/assign', { id: CLIENT, bundle: { nope: 1 } })).status, 400);
  assert.equal((await call(PT, 'POST', '/api/trainer/client/message', { id: CLIENT, text: '' })).status, 400);
  await call(PT, 'POST', '/api/trainer/client/message', { id: CLIENT, text: 'Proud of you!' });

  r = await call(PT, 'GET', `/api/trainer/client?id=${CLIENT}`);
  assert.equal(r.body.notes.length, 1);
  assert.equal(r.body.messages.length, 2);
  assert.equal(r.body.assignments[0].bundle, undefined, 'the roster does not ship the plan itself');

  r = await call(CLIENT, 'GET', '/api/client/training');
  assert.equal(r.status, 200);
  assert.equal(r.body.trainer.name, 'Klora');
  assert.equal(JSON.stringify(r.body).includes('PRIVATE'), false);
  assert.equal(r.body.unread, 1);
  assert.equal(r.body.assignments[0].bundle.routines[0].name, 'Glutes A');

  const id = r.body.assignments[0].id;
  assert.equal((await call(CLIENT, 'POST', '/api/client/assignment/accept', { assignmentId: id })).status, 200);
  assert.equal((await call(PT, 'POST', '/api/trainer/client/assign/withdraw', { id: CLIENT, assignmentId: id })).status, 400);

  await call(CLIENT, 'GET', '/api/client/training?read=1');
  assert.equal((await call(CLIENT, 'GET', '/api/client/training')).body.unread, 0);
});

test('the trainer builds a program once and sends it to a client', async t => {
  const { call } = await startServer(t);
  let r = await call(PT, 'POST', '/api/trainer/program/save', { id: 'prog1', name: 'Glute builder', note: '3 days a week', bundle: plan });
  assert.equal(r.status, 200);
  assert.equal(r.body.program.bundle, undefined);
  assert.equal((await call(PT, 'POST', '/api/trainer/program/save', { name: 'x', bundle: { opengym_plan: 1, routines: [] } })).status, 400);

  r = await call(PT, 'GET', '/api/trainer/program?id=prog1');
  assert.equal(r.body.program.bundle.routines[0].name, 'Glutes A');

  await call(PT, 'POST', '/api/trainer/client/assign', { id: CLIENT, name: 'Glute builder', bundle: r.body.program.bundle, programId: 'prog1' });
  r = await call(PT, 'GET', '/api/trainer/programs');
  assert.deepEqual(r.body.programs.map(p => [p.id, p.days, p.assigned]), [['prog1', 1, 1]]);

  assert.equal((await call(CLIENT, 'GET', '/api/trainer/programs')).status, 403);
  assert.equal((await call(PT, 'POST', '/api/trainer/program/delete', { id: 'prog1' })).status, 200);
  assert.equal((await call(PT, 'GET', '/api/trainer/program?id=prog1')).status, 404);
  r = await call(CLIENT, 'GET', '/api/client/training');
  assert.equal(r.body.assignments.length, 1, 'deleting a program leaves what the client was sent');
});

test('a client cannot reach the trainer routes', async t => {
  const { call } = await startServer(t);
  for (const [m, p, b] of [['GET', '/api/trainer/clients'], ['GET', `/api/trainer/client?id=${CLIENT}`], ['POST', '/api/trainer/client/note', { id: CLIENT, text: 'x' }], ['POST', '/api/trainer/client/assign', { id: CLIENT, bundle: plan }]]) {
    assert.equal((await call(CLIENT, m, p, b)).status, 403, p);
  }
});

test('deleting a client removes their coaching file', async t => {
  const { call, dataDir } = await startServer(t);
  await call(PT, 'POST', '/api/trainer/client/note', { id: CLIENT, text: 'x' });
  assert.ok(fs.existsSync(path.join(dataDir, `training-${CLIENT}.json`)));
  assert.equal((await call(PT, 'POST', '/api/admin/user/delete', { id: CLIENT })).status, 200);
  assert.equal(fs.existsSync(path.join(dataDir, `training-${CLIENT}.json`)), false);
});
