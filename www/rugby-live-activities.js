/*
 * rugby-live-activities.js
 *
 * Browser-side controller for the native RugbyLiveActivities Capacitor plugin.
 * Included by www/index.html via <script src="rugby-live-activities.js"></script>.
 *
 * Design goals:
 *  - Zero-config in the app: `window.RugbyLiveActivity.sync()` reads global match
 *    state `S` and the global `fmtMs()` formatter automatically.
 *  - Safe no-op on web / Android / older iOS (no plugin) so callers never branch.
 *  - Unit-testable under Node: the controller is a factory with injectable plugin,
 *    state and clock, and pure helpers are exported. See test/live-activity.test.mjs.
 */
(function (global) {
  'use strict';

  /** Fallback "MM:SS" formatter, used only if the app's global fmtMs is absent. */
  function fmtMsLocal(ms) {
    ms = Math.max(0, ms | 0);
    var m = Math.floor(ms / 60000);
    var s = Math.floor((ms % 60000) / 1000);
    return String(m).padStart(2, '0') + ':' + String(s).padStart(2, '0');
  }

  /**
   * Build the native MatchData payload from the app's state object `S`.
   * `status` overrides the derived running/paused state (used for 'finished').
   */
  function buildPayload(state, matchId, fmt, statusOverride) {
    var status = statusOverride || (state.running ? 'live' : 'paused');
    return {
      matchId: matchId,
      homeTeam: state.myTeam || 'Home',
      awayTeam: state.opp || 'Away',
      homeScore: (state.scFor | 0),
      awayScore: (state.scAg | 0),
      matchTime: fmt(state.ms | 0),
      matchStatus: status,
      halfNumber: state.half === 2 ? 2 : 1,
    };
  }

  /** A change-signature: pushing only when this changes avoids burning the budget. */
  function signatureOf(payload) {
    return [payload.homeScore, payload.awayScore, payload.halfNumber, payload.matchStatus].join('|');
  }

  /**
   * Decide whether an update should be pushed.
   * Pushes when forced, when the visible signature changed, or after `maxAgeMs`
   * as a clock-resync safety net.
   */
  function shouldPush(force, sig, lastSig, now, lastPush, maxAgeMs) {
    if (force) return true;
    if (sig !== lastSig) return true;
    return (now - lastPush) >= maxAgeMs;
  }

  /**
   * Create a controller. All side-effecting dependencies are injected so the same
   * code runs in the browser and under a Node test harness.
   */
  function createController(opts) {
    opts = opts || {};
    var getPlugin = opts.getPlugin || function () { return null; };
    var getState = opts.getState || function () { return {}; };
    var fmt = opts.fmtMs || fmtMsLocal;
    var now = opts.now || function () { return Date.now(); };
    var maxAgeMs = opts.maxAgeMs != null ? opts.maxAgeMs : 10000;
    var makeId = opts.makeId || function () { return 'match-' + now(); };
    var log = opts.log || function () {};

    var active = false;
    var matchId = null;
    var lastSig = '';
    var lastPush = 0;

    function reset() {
      active = false;
      matchId = null;
      lastSig = '';
      lastPush = 0;
    }

    /**
     * Start (first call) or update (subsequent) the Live Activity from current state.
     * `force` bypasses the throttle (use on score changes / status flips).
     * Always resolves; never throws into the match loop.
     */
    function sync(force) {
      var plugin = getPlugin();
      if (!plugin) return Promise.resolve(null); // not on a supported platform
      var state = getState();

      if (!active) {
        matchId = matchId || makeId();
        var startPayload = buildPayload(state, matchId, fmt);
        active = true;
        lastSig = signatureOf(startPayload);
        lastPush = now();
        return Promise.resolve(plugin.startMatchActivity(startPayload))
          .catch(function (e) { active = false; log('start failed', e); return null; });
      }

      var payload = buildPayload(state, matchId, fmt);
      var sig = signatureOf(payload);
      if (!shouldPush(force, sig, lastSig, now(), lastPush, maxAgeMs)) {
        return Promise.resolve(null);
      }
      lastSig = sig;
      lastPush = now();
      return Promise.resolve(plugin.updateMatchActivity(payload))
        .catch(function (e) { log('update failed', e); return null; });
    }

    /** Close the activity (full time / leave match). Sends a final 'finished' frame. */
    function end() {
      var plugin = getPlugin();
      if (!plugin || !active || !matchId) { reset(); return Promise.resolve(null); }
      var state = getState();
      var id = matchId;
      reset();
      return Promise.resolve(plugin.endMatchActivity({
        matchId: id,
        homeScore: (state.scFor | 0),
        awayScore: (state.scAg | 0),
        matchTime: fmt(state.ms | 0),
        halfNumber: state.half === 2 ? 2 : 1,
        matchStatus: 'finished',
      })).catch(function (e) { log('end failed', e); return null; });
    }

    return {
      sync: sync,
      end: end,
      reset: reset,
      isActive: function () { return active; },
      currentMatchId: function () { return matchId; },
      // exposed for tests
      _build: function (statusOverride) { return buildPayload(getState(), matchId || 'pending', fmt, statusOverride); },
    };
  }

  // ---- Default browser instance, auto-wired to Capacitor + global S/fmtMs ----
  function defaultGetPlugin() {
    try {
      var C = global.Capacitor;
      if (!C || typeof C.getPlatform !== 'function') return null;
      if (C.getPlatform() !== 'ios') return null;
      return (C.Plugins && C.Plugins.RugbyLiveActivities) || null;
    } catch (e) { return null; }
  }

  var instance = createController({
    getPlugin: defaultGetPlugin,
    getState: function () { return global.S || {}; },
    fmtMs: function (ms) { return typeof global.fmtMs === 'function' ? global.fmtMs(ms) : fmtMsLocal(ms); },
    log: function (m, e) { try { console.warn('[LiveActivity] ' + m, e); } catch (_) {} },
  });

  global.RugbyLiveActivity = instance;

  // Test / advanced hooks
  global.RugbyLiveActivityInternals = {
    createController: createController,
    buildPayload: buildPayload,
    signatureOf: signatureOf,
    shouldPush: shouldPush,
    fmtMsLocal: fmtMsLocal,
  };

  // CommonJS export for Node tests.
  if (typeof module !== 'undefined' && module.exports) {
    module.exports = global.RugbyLiveActivityInternals;
  }
})(typeof window !== 'undefined' ? window : globalThis);
