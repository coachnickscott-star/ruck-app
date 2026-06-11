# Integration Example — wiring Live Activities into the match timer

This shows exactly where in the existing `www/index.html` match code to start, update
and end the Live Activity. It maps the plugin's `MatchData` onto the app's existing
state object `S`.

## How the existing app stores match state

From `www/index.html`:

| App state | Meaning | Maps to `MatchData` |
|-----------|---------|---------------------|
| `S.myTeam` | Home team name | `homeTeam` |
| `S.opp` | Away team name | `awayTeam` |
| `S.scFor` | Home (your team) score | `homeScore` |
| `S.scAg` | Away (opponent) score | `awayScore` |
| `S.ms` | Elapsed milliseconds | → `fmtMs(S.ms)` = `matchTime` |
| `S.half` | Current half (1 or 2) | `halfNumber` |
| `S.running` | Clock running? | drives `matchStatus` |

Relevant existing functions: `tick()` (runs every 100 ms via `setInterval(tick,100)`),
`fmtMs(ms)` (formats "MM:SS"), the match-start path that sets `S.timer=setInterval(tick,100)`,
`resumeFromHT()`, `endMatchEarly()` / full-time path.

---

## Step 1 — Add a small inline helper

The app is plain inline JS (no bundler), so use the global Capacitor plugin directly.
Paste this near the top of the main `<script>` block in `www/index.html`:

```js
// ---- Live Activities (iOS 16.1+) -------------------------------------------
const LiveActivity = (() => {
  const Plugin = window.Capacitor?.Plugins?.RugbyLiveActivities;
  const isIOS  = window.Capacitor?.getPlatform?.() === 'ios';
  const on     = !!Plugin && isIOS;

  let activeMatchId = null;
  let lastPush = 0;
  let lastSig  = '';        // signature of what's currently displayed

  // Build the payload from current match state `S`.
  function payload(status) {
    return {
      matchId:    activeMatchId,
      homeTeam:   S.myTeam || 'Home',
      awayTeam:   S.opp    || 'Away',
      homeScore:  S.scFor | 0,
      awayScore:  S.scAg  | 0,
      matchTime:  fmtMs(S.ms),
      matchStatus: status,                 // 'live' | 'paused' | 'finished'
      halfNumber: S.half === 2 ? 2 : 1,
    };
  }

  function statusNow() { return S.running ? 'live' : 'paused'; }

  return {
    isOn: () => on,

    async start() {
      if (!on) return;
      activeMatchId = 'match-' + Date.now();
      lastSig = '';
      try { await Plugin.startMatchActivity(payload('live')); }
      catch (e) { console.warn('LiveActivity start failed', e); }
    },

    // Call this freely from tick() — it self-throttles.
    async update(force) {
      if (!on || !activeMatchId) return;
      const p = statusNow();
      // Only push when the visible content changes (score/half/status) OR every
      // ~10s as a clock-resync safety net. The lock screen ticks the seconds itself,
      // so we must NOT push every second — that burns ActivityKit's update budget.
      const sig = `${S.scFor}|${S.scAg}|${S.half}|${p}`;
      const now = Date.now();
      if (!force && sig === lastSig && now - lastPush < 10000) return;
      lastSig = sig; lastPush = now;
      try { await Plugin.updateMatchActivity(payload(p)); }
      catch (e) { console.warn('LiveActivity update failed', e); }
    },

    async end() {
      if (!on || !activeMatchId) return;
      try {
        await Plugin.endMatchActivity({
          matchId: activeMatchId,
          homeScore: S.scFor | 0,
          awayScore: S.scAg | 0,
          matchTime: fmtMs(S.ms),
          halfNumber: S.half === 2 ? 2 : 1,
        });
      } catch (e) { console.warn('LiveActivity end failed', e); }
      activeMatchId = null;
    },
  };
})();
```

---

## Step 2 — Start the activity at kickoff

Find the kickoff path where the clock first starts. In `www/index.html` this is where
`S.timer=setInterval(tick,100)` is set with `S.half=1` (around the first-half start):

```js
  S.half=1;S._fullTimeMode=false;
  S.ts=Date.now();S.running=true;S.timer=setInterval(tick,100);
  // … existing UI updates …
  LiveActivity.start();                 // ← add this line
```

---

## Step 3 — Update from the timer loop

The score buttons and the clock both change state, so the simplest robust hook is the
existing `tick()` function. Because `LiveActivity.update()` self-throttles, calling it
every tick is cheap:

```js
function tick(){
  const now=Date.now();
  S._lastTick=now;
  S.ms=now-S.ts;
  if(S.ycTimers&&S.ycTimers.length){ /* … existing sin-bin logic … */ }
  updClock();
  LiveActivity.update();                // ← add this line
}
```

Also push **immediately** when a score changes so the Lock Screen never lags a try.
Wherever `S.scFor` / `S.scAg` are mutated (the add-points handlers), add:

```js
  // after updating S.scFor / S.scAg and re-rendering the scoreboard:
  LiveActivity.update(true);            // force = bypass throttle for instant score sync
```

---

## Step 4 — Reflect pause / half-time

The clock pause toggle and the **Half Time** button change status. After the existing
pause logic (where `clearInterval(S.timer); S.running=false;`):

```js
  // pause:
  clearInterval(S.timer); S.running=false;
  LiveActivity.update(true);            // ← shows "PAUSED" badge

  // resume / start 2nd half (resumeFromHT):
  S.timer=setInterval(tick,100); S.running=true;
  LiveActivity.update(true);            // ← back to "LIVE", half flips to 2 automatically
```

`halfNumber` comes from `S.half`, so when `resumeFromHT()` sets `S.half=2`, the next
update automatically shows **2nd Half**.

---

## Step 5 — End at full time

In the full-time / leave-match paths (`endMatchEarly()`, the FT banner code, and
`doLeaveMatch()` which does `clearInterval(S.timer)`), close the activity:

```js
function endMatchEarly(){
  S.half=2; S._fullTimeMode=true;
  // … existing FT banner UI …
  saveMatch();
  LiveActivity.end();                   // ← add this line
}
```

Add the same `LiveActivity.end();` to `doLeaveMatch()` so abandoning a match also clears
the Lock Screen.

---

## Optional — Supabase note

The current design needs **no** Supabase calls: the match clock and score already live
in client state `S`, and the Lock Screen ticks the seconds on-device, so the plugin only
needs the local values shown above.

You'd only involve Supabase if you wanted **remote** updates (e.g. a second coach's phone
showing the same match, or updates while the app is fully killed). That requires:

1. `pushType: .token` in `Activity.request` (instead of `nil`) and forwarding the push
   token to a Supabase Edge Function.
2. The Edge Function sending ActivityKit pushes via APNs when the match row changes
   (subscribe to the `matches` table with Supabase Realtime / a DB trigger).

For grassroots single-device match tracking, the local approach in this guide is all you
need — keep it simple.

---

## TypeScript variant

If you later move the match code into a TypeScript build, import the typed wrapper
instead of the inline helper:

```ts
import { RugbyLiveActivities, MatchData } from './plugins/rugby-live-activities';

const data: MatchData = {
  matchId, homeTeam, awayTeam,
  homeScore, awayScore,
  matchTime,                 // "MM:SS"
  matchStatus: 'live',
  halfNumber: 1,
};

await RugbyLiveActivities.startMatch(data);
// in the loop:
await RugbyLiveActivities.updateMatch({ ...data, homeScore, awayScore, matchTime });
// at full time:
await RugbyLiveActivities.endMatch(matchId, { homeScore, awayScore, matchTime });
```
