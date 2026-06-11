// Verifies the DEFAULT auto-wired instance the app actually uses:
// www/index.html loads rugby-live-activities.js, which binds to window.Capacitor,
// window.S and window.fmtMs. This simulates that browser environment under Node.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const scriptPath = require.resolve('../www/rugby-live-activities.js');

function fmtMs(ms) {
  const m = Math.floor(ms / 60000), s = Math.floor((ms % 60000) / 1000);
  return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
}

// Re-load the script fresh against a given fake `window`.
function loadWithWindow(win) {
  delete require.cache[scriptPath];
  globalThis.window = win;
  try { require(scriptPath); } finally { delete globalThis.window; }
  return win;
}

function iosWindow(state) {
  const calls = [];
  const plugin = {
    startMatchActivity: async (p) => { calls.push(['start', p]); return {}; },
    updateMatchActivity: async (p) => { calls.push(['update', p]); return {}; },
    endMatchActivity: async (p) => { calls.push(['end', p]); return {}; },
  };
  const win = {
    console,
    Capacitor: { getPlatform: () => 'ios', Plugins: { RugbyLiveActivities: plugin } },
    S: state,
    fmtMs,
  };
  win._calls = calls;
  return win;
}

test('default instance reads window.S/fmtMs and starts via Capacitor on iOS', async () => {
  const state = { myTeam: 'Lions', opp: 'Tigers', scFor: 3, scAg: 0, ms: 65000, half: 1, running: true };
  const win = loadWithWindow(iosWindow(state));
  assert.ok(win.RugbyLiveActivity, 'controller attached to window');

  await win.RugbyLiveActivity.sync(true);
  assert.equal(win._calls.length, 1);
  const [kind, p] = win._calls[0];
  assert.equal(kind, 'start');
  assert.equal(p.homeTeam, 'Lions');
  assert.equal(p.awayTeam, 'Tigers');
  assert.equal(p.homeScore, 3);
  assert.equal(p.matchTime, '01:05'); // 65000ms via the app's fmtMs
  assert.equal(p.matchStatus, 'live');
  assert.equal(p.halfNumber, 1);
});

test('live state aliasing: mutating window.S is reflected on the next sync', async () => {
  const state = { myTeam: 'Lions', opp: 'Tigers', scFor: 0, scAg: 0, ms: 0, half: 1, running: true };
  const win = loadWithWindow(iosWindow(state));
  await win.RugbyLiveActivity.sync(true);     // start 0-0
  win.S.scFor = 7;                            // in-place mutation (as the app does)
  win.S.ms = 130000;
  await win.RugbyLiveActivity.sync(true);     // forced update
  const [kind, p] = win._calls.at(-1);
  assert.equal(kind, 'update');
  assert.equal(p.homeScore, 7);
  assert.equal(p.matchTime, '02:10');
});

test('non-iOS platform is a safe no-op (no plugin calls)', async () => {
  const win = iosWindow({ myTeam: 'A', opp: 'B', scFor: 0, scAg: 0, ms: 0, half: 1, running: true });
  win.Capacitor.getPlatform = () => 'web';
  loadWithWindow(win);
  const r = await win.RugbyLiveActivity.sync(true);
  assert.equal(r, null);
  assert.equal(win._calls.length, 0);
  assert.equal(win.RugbyLiveActivity.isActive(), false);
});

test('end sends finished frame through the default instance', async () => {
  const state = { myTeam: 'Lions', opp: 'Tigers', scFor: 24, scAg: 19, ms: 4801000, half: 2, running: false };
  const win = loadWithWindow(iosWindow(state));
  await win.RugbyLiveActivity.sync(true);
  await win.RugbyLiveActivity.end();
  const [kind, p] = win._calls.at(-1);
  assert.equal(kind, 'end');
  assert.equal(p.matchStatus, 'finished');
  assert.equal(p.homeScore, 24);
  assert.equal(p.awayScore, 19);
  assert.equal(win.RugbyLiveActivity.isActive(), false);
});
