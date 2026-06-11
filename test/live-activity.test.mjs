// Node test suite for the Live Activity browser controller (www/rugby-live-activities.js).
// Run: node --test test/   (or node test/live-activity.test.mjs)
//
// Exercises the full match lifecycle against a mock native plugin so the JS↔native
// contract (payload shape, throttling, start/update/end ordering) is verified without iOS.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { createController, buildPayload, signatureOf, shouldPush, fmtMsLocal } =
  require('../www/rugby-live-activities.js');

// --- A mock native plugin that records every call -------------------------
function mockPlugin() {
  const calls = [];
  return {
    calls,
    startMatchActivity: async (p) => { calls.push(['start', p]); return { started: true, matchId: p.matchId }; },
    updateMatchActivity: async (p) => { calls.push(['update', p]); return { updated: true }; },
    endMatchActivity: async (p) => { calls.push(['end', p]); return { ended: true }; },
  };
}

// --- A mutable fake of the app's global state `S` -------------------------
function fakeState() {
  return { myTeam: 'Saracens', opp: 'Quins', scFor: 0, scAg: 0, ms: 0, half: 1, running: false };
}

// Build a controller with a controllable clock + deterministic ids.
function harness(pluginRef) {
  const state = fakeState();
  let clock = 1000;
  let idN = 0;
  const ctrl = createController({
    getPlugin: () => pluginRef.value,
    getState: () => state,
    fmtMs: fmtMsLocal,
    now: () => clock,
    makeId: () => `match-${++idN}`,
    maxAgeMs: 10000,
  });
  return {
    ctrl, state,
    tick: (ms) => { clock += ms; },
    setClock: (v) => { clock = v; },
  };
}

// ---------------------------------------------------------------------------

test('pure helpers: payload, signature, shouldPush, fmt', () => {
  const s = { myTeam: 'A', opp: 'B', scFor: 7, scAg: 3, ms: 92000, half: 2, running: true };
  const p = buildPayload(s, 'm1', fmtMsLocal);
  assert.deepEqual(p, {
    matchId: 'm1', homeTeam: 'A', awayTeam: 'B',
    homeScore: 7, awayScore: 3, matchTime: '01:32',
    matchStatus: 'live', halfNumber: 2,
  });
  assert.equal(buildPayload({ ...s, running: false }, 'm1', fmtMsLocal).matchStatus, 'paused');
  assert.equal(buildPayload(s, 'm1', fmtMsLocal, 'finished').matchStatus, 'finished');
  assert.equal(signatureOf(p), '7|3|2|live');
  assert.equal(fmtMsLocal(0), '00:00');
  assert.equal(fmtMsLocal(5400000), '90:00');
  // shouldPush logic
  assert.equal(shouldPush(true, 'x', 'x', 0, 0, 10000), true);   // forced
  assert.equal(shouldPush(false, 'x', 'y', 0, 0, 10000), true);  // changed
  assert.equal(shouldPush(false, 'x', 'x', 5000, 0, 10000), false); // same, fresh
  assert.equal(shouldPush(false, 'x', 'x', 10000, 0, 10000), true); // same, stale
});

test('no plugin → safe no-op', async () => {
  const ref = { value: null };
  const { ctrl } = harness(ref);
  assert.equal(await ctrl.sync(true), null);
  assert.equal(ctrl.isActive(), false);
  assert.equal(await ctrl.end(), null);
});

test('first sync starts the activity exactly once, in LIVE', async () => {
  const ref = { value: mockPlugin() };
  const { ctrl, state } = harness(ref);
  state.running = true;
  await ctrl.sync(true);
  assert.equal(ctrl.isActive(), true);
  assert.equal(ref.value.calls.length, 1);
  const [kind, payload] = ref.value.calls[0];
  assert.equal(kind, 'start');
  assert.equal(payload.matchStatus, 'live');
  assert.equal(payload.matchId, 'match-1');
  assert.equal(payload.homeTeam, 'Saracens');
});

test('throttle: no redundant updates; resync after maxAge', async () => {
  const ref = { value: mockPlugin() };
  const h = harness(ref);
  h.state.running = true;
  await h.ctrl.sync(true);               // start
  assert.equal(ref.value.calls.length, 1);

  // clock advances but score/half/status unchanged → suppressed
  h.tick(1000); await h.ctrl.sync();
  h.tick(1000); await h.ctrl.sync();
  assert.equal(ref.value.calls.length, 1, 'identical state should not push');

  // cross the 10s safety net → one resync update
  h.tick(8500); await h.ctrl.sync();     // total 10.5s since last push
  assert.equal(ref.value.calls.length, 2);
  assert.equal(ref.value.calls[1][0], 'update');
});

test('score change forces an immediate update with new scores', async () => {
  const ref = { value: mockPlugin() };
  const h = harness(ref);
  h.state.running = true;
  await h.ctrl.sync(true);               // start 0-0
  h.tick(500);
  h.state.scFor = 5;                     // a try
  await h.ctrl.sync(true);               // forced
  assert.equal(ref.value.calls.length, 2);
  const [kind, p] = ref.value.calls[1];
  assert.equal(kind, 'update');
  assert.equal(p.homeScore, 5);
  assert.equal(p.matchStatus, 'live');
});

test('pause then resume flips status, keeps same matchId', async () => {
  const ref = { value: mockPlugin() };
  const h = harness(ref);
  h.state.running = true;
  await h.ctrl.sync(true);
  const id = h.ctrl.currentMatchId();

  h.state.running = false;              // pause
  await h.ctrl.sync(true);
  assert.equal(ref.value.calls.at(-1)[1].matchStatus, 'paused');

  h.state.running = true;               // resume
  await h.ctrl.sync(true);
  assert.equal(ref.value.calls.at(-1)[1].matchStatus, 'live');
  assert.equal(h.ctrl.currentMatchId(), id, 'matchId stays stable across the match');
});

test('half-time → 2nd half updates halfNumber', async () => {
  const ref = { value: mockPlugin() };
  const h = harness(ref);
  h.state.running = true;
  await h.ctrl.sync(true);
  h.state.half = 2;
  await h.ctrl.sync(true);
  assert.equal(ref.value.calls.at(-1)[1].halfNumber, 2);
});

test('end closes with a finished frame + final score, then deactivates', async () => {
  const ref = { value: mockPlugin() };
  const h = harness(ref);
  h.state.running = true;
  await h.ctrl.sync(true);
  h.state.scFor = 17; h.state.scAg = 12; h.state.ms = 4800000;
  await h.ctrl.end();
  const [kind, p] = ref.value.calls.at(-1);
  assert.equal(kind, 'end');
  assert.equal(p.matchStatus, 'finished');
  assert.equal(p.homeScore, 17);
  assert.equal(p.awayScore, 12);
  assert.equal(p.matchTime, '80:00');
  assert.equal(h.ctrl.isActive(), false);
  assert.equal(h.ctrl.currentMatchId(), null);
});

test('end when never started is a harmless no-op', async () => {
  const ref = { value: mockPlugin() };
  const { ctrl } = harness(ref);
  await ctrl.end();
  assert.equal(ref.value.calls.length, 0);
});

test('full lifecycle: reset → start → score → HT → 2nd half → FT starts a fresh id', async () => {
  const ref = { value: mockPlugin() };
  const h = harness(ref);

  // Match 1
  h.ctrl.reset();
  h.state.running = true;
  await h.ctrl.sync(true);                 // start (match-1)
  const id1 = h.ctrl.currentMatchId();
  h.state.scFor = 5; await h.ctrl.sync(true);
  h.state.running = false; h.state.half = 2; await h.ctrl.sync(true); // HT
  h.state.running = true; await h.ctrl.sync(true);                    // 2nd half
  await h.ctrl.end();                        // FT
  assert.equal(h.ctrl.isActive(), false);

  // Match 2 (coach starts a new game)
  h.ctrl.reset();
  Object.assign(h.state, { scFor: 0, scAg: 0, half: 1, running: true, ms: 0 });
  await h.ctrl.sync(true);
  const id2 = h.ctrl.currentMatchId();
  assert.notEqual(id1, id2, 'a new match must get a new activity id');

  const kinds = ref.value.calls.map((c) => c[0]);
  assert.deepEqual(kinds, ['start', 'update', 'update', 'update', 'end', 'start']);
});
