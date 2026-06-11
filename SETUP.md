# Live Activities Setup — RugbyCoach.AI

Step-by-step guide to wiring the **RugbyLiveActivities** plugin into the `ruck-app`
Capacitor project so live match scores appear on the iOS Lock Screen and Dynamic Island.

> **Audience:** basic Swift knowledge, no prior Live Activities experience.
> **Target:** iOS 16.1+ · **Bundle ID:** `ai.rugbycoach.app` · **Capacitor:** 8.x (SPM)

---

## 0. What you're building

ActivityKit (Apple's Live Activities framework) needs **two** pieces of native code:

| Piece | Lives in target | What it does |
|-------|-----------------|--------------|
| **Plugin** (`RugbyLiveActivitiesPlugin.swift`) | `App` (main app) | Starts / updates / ends the activity. Bridged to JS via Capacitor. |
| **Widget UI** (`RugbyLiveActivitiesWidget.swift`) | `RugbyLiveActivityWidget` (a **Widget Extension** you'll add) | Draws the Lock Screen + Dynamic Island. |
| **Shared model** (`RugbyMatchAttributes.swift`) | **BOTH** targets | The data contract. Must be identical in both, hence shared file membership. |

The files are already in the repo at:

```
ios/App/App/Plugins/RugbyLiveActivities/
    ├── RugbyLiveActivitiesPlugin.swift      → App target
    └── RugbyMatchAttributes.swift           → App + Widget targets (shared)
ios/App/RugbyLiveActivityWidget/
    ├── RugbyLiveActivitiesWidget.swift      → Widget target
    ├── RugbyLiveActivityWidgetBundle.swift  → Widget target
    └── Info.plist                           → Widget target
src/plugins/rugby-live-activities.ts         → JS/TS bridge
```

You still have to **register them with Xcode targets** — copying files onto disk isn't
enough; Xcode needs them in the project and assigned to the right targets.

---

## 1. Sync Capacitor & open Xcode

```bash
cd ~/ruck-app
npm install
npx cap sync ios
npx cap open ios          # opens ios/App/App.xcodeproj (or .xcworkspace) in Xcode
```

---

## 2. Add the plugin files to the **App** target

1. In Xcode's Project Navigator, right-click the **App** group → **Add Files to "App"…**
2. Select the folder `ios/App/App/Plugins/RugbyLiveActivities`.
3. Tick **Copy items if needed = OFF** (files already exist), **Create groups**, and
   under *Add to targets* check **App** only for now.
4. Click **Add**.

You should now see `RugbyLiveActivitiesPlugin.swift` and `RugbyMatchAttributes.swift`
in the project under the App target.

> **No `.m` bridging file is needed.** The plugin adopts `CAPBridgedPlugin` and declares
> its JS name + methods in Swift. Capacitor discovers it automatically at runtime.

---

## 3. Create the Widget Extension target

This is the target that renders the activity. It does **not** exist yet — create it:

1. **File → New → Target…**
2. Choose **Widget Extension** → **Next**.
3. Product Name: **`RugbyLiveActivityWidget`** (must match the folder name used here).
4. **UNcheck** "Include Configuration App Intent". **Check** "Include Live Activity".
   (If your Xcode doesn't show the Live Activity checkbox, that's fine — we replace the
   generated files anyway.)
5. Team: your signing team. **Finish.**
6. When prompted **"Activate scheme?"** → **Cancel** (keep the App scheme active).

Xcode generates a starter widget folder. **Delete the generated `.swift` files** it
created (move to Trash) — you'll use the ones in this repo instead.

Then add the repo's widget files to the new target:

1. Right-click the **RugbyLiveActivityWidget** group → **Add Files to "App"…**
2. Add `RugbyLiveActivitiesWidget.swift` and `RugbyLiveActivityWidgetBundle.swift`
   from `ios/App/RugbyLiveActivityWidget/`, targeting **RugbyLiveActivityWidget** only.
3. For the **`Info.plist`** in that folder: in the target's **Build Settings**, set
   **Info.plist File** to `RugbyLiveActivityWidget/Info.plist` (or let Xcode use its
   generated one and just ensure `NSExtensionPointIdentifier` =
   `com.apple.widgetkit-extension`).

---

## 4. Share `RugbyMatchAttributes.swift` with the widget (critical!)

The single most common reason a Live Activity never appears: the attributes type is
compiled into only one target.

1. Select **`RugbyMatchAttributes.swift`** in the navigator.
2. Open the **File Inspector** (right panel, ⌥⌘1).
3. Under **Target Membership**, tick **BOTH**:
   - ☑ App
   - ☑ RugbyLiveActivityWidget

---

## 5. Enable Live Activities in the app's Info.plist

Add `NSSupportsLiveActivities` to the **main app** Info.plist
(`ios/App/App/Info.plist`). This repo already includes it — verify it's present:

```xml
<key>NSSupportsLiveActivities</key>
<true/>
```

> Optional: add `NSSupportsLiveActivitiesFrequentUpdates` `<true/>` only if you push
> very frequent updates. For a rugby clock that mostly self-ticks, leave it off — it
> just asks the system for a larger update budget.

If you add a deep-link from the Dynamic Island (the widget uses
`rugbycoach://match/<id>`), register the URL scheme too:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array><string>rugbycoach</string></array>
  </dict>
</array>
```

---

## 6. Signing & capabilities

Live Activities that are **updated locally by the app** (this plugin uses `pushType: nil`)
**do not need a special entitlement or the Push Notifications capability.** All you need:

1. Select the **App** target → **Signing & Capabilities**.
   - Team set, **Automatically manage signing** on.
   - Bundle Identifier = **`ai.rugbycoach.app`**.
2. Select the **RugbyLiveActivityWidget** target → **Signing & Capabilities**.
   - Same Team.
   - Bundle Identifier = **`ai.rugbycoach.app.RugbyLiveActivityWidget`**
     (must be the app id with a suffix — Xcode usually sets this automatically).
   - Deployment target ≥ **iOS 16.1**.

> Only add the **Push Notifications** capability + APNs token handling later if you want
> the server (Supabase Edge Function) to update activities while the app is killed.
> The current implementation updates from the foreground/background app process, which
> is all a coach needs while actively running the match screen.

Set the **iOS Deployment Target** of the App target to **16.1 or higher** if it's lower
(Build Settings → *iOS Deployment Target*). The plugin compiles on lower targets because
every ActivityKit call is `@available`-guarded, but the widget extension itself needs 16.1+.

---

## 7. Register the plugin with Capacitor

**Local Swift plugins are auto-registered** — because `RugbyLiveActivitiesPlugin`
subclasses `CAPPlugin` and conforms to `CAPBridgedPlugin`, Capacitor finds it via the
Objective-C runtime at launch. **You do not need to edit `capacitor.config.json`** for
the plugin to load.

For documentation/clarity you *may* add a plugins entry (optional, no behavioural effect
for a local plugin):

```jsonc
// capacitor.config.json
{
  "appId": "ai.rugbycoach.app",
  "appName": "RugbyCoach.AI",
  "webDir": "www",
  "plugins": {
    "AdMob": { "appId": "ca-app-pub-3642567250366576~9386082802" },
    "RugbyLiveActivities": {}      // optional documentation stub
  }
}
```

Verify the JS name matches: the Swift `jsName` is `"RugbyLiveActivities"` and the TS
`registerPlugin('RugbyLiveActivities', …)` uses the same string. They must agree.

---

## 8. Build & run

```bash
npx cap sync ios
# then in Xcode: select the "App" scheme + an iOS 16.1+ simulator/device → ⌘R
```

If the build fails with *"Cannot find type 'RugbyMatchAttributes'"* in the widget, you
missed **Step 4** (shared target membership).

---

## 9. Wire it to the match timer

See **INTEGRATION_EXAMPLE.md** for exactly where in `www/index.html`'s `tick()` /
score / half-time / full-time flow to call `startMatch`, `updateMatch` and `endMatch`.

---

## Quick verification checklist

- [ ] `RugbyMatchAttributes.swift` shows **two** ticks in Target Membership.
- [ ] App Info.plist has `NSSupportsLiveActivities = true`.
- [ ] Widget bundle id = app id + `.RugbyLiveActivityWidget`.
- [ ] Both targets ≥ iOS 16.1 deployment target.
- [ ] App scheme runs; widget target builds without errors.
- [ ] `RugbyLiveActivities.isSupported()` returns `{ supported: true }` on device.

---

## 10. Testing checklist

### Simulator (Xcode 15+)
- [ ] Use an **iPhone 15 Pro** (or any Pro) simulator on **iOS 16.1+** — only Pro models
      render the **Dynamic Island**; non-Pro shows the Lock Screen banner only.
- [ ] Run the **App** scheme, start a match → lock the simulator (**⌘L**) and confirm the
      banner appears with score + ticking clock.
- [ ] Iterate on the design fast with the **SwiftUI canvas previews** in
      `RugbyLiveActivitiesWidget.swift` (Lock Screen / compact / expanded / minimal) —
      no need to run a full match each time.
- [ ] Long-press the Dynamic Island to verify the **expanded** layout.

### Real device (iPhone, iOS 16.1+)
- [ ] Settings → **RugbyCoach.AI → Live Activities = ON** (also Settings → Face ID &
      Passcode → *Live Activities* allowed on Lock Screen).
- [ ] Start a match, lock the phone, score a try → score updates on the Lock Screen
      within ~1s (force-push on score change).
- [ ] Leave the phone locked 2–3 minutes → the clock keeps ticking accurately on its own
      (self-ticking timer, no app pushes needed).
- [ ] Hit **Half Time**, then **Start 2nd Half** → badge flips PAUSED → LIVE, half shows
      "2nd Half".
- [ ] **Full time / leave match** → activity dismisses (shows final score briefly).

### Match-data specific checks
- [ ] **Score sync:** rapid successive scores (e.g. try + conversion) both land — the
      forced `update(true)` on score change avoids the 10s throttle.
- [ ] **Time sync after backgrounding:** background then foreground the app — the next
      `updateMatch` resets `startDate = now − elapsed`, so the Lock Screen re-aligns to
      the app clock (no drift).
- [ ] **Count-down mode:** the app's `S.dir==='down'` only affects the in-app display;
      `matchTime` sent to the activity is always elapsed "MM:SS" — confirm that's the
      behaviour you want, or pass the remaining time string if coaches prefer countdown.
- [ ] **Overtime / 80:00+:** clock displays 3-digit minutes fine (`MMM:SS` accepted).

### Debugging timing accuracy
- [ ] If the Lock Screen clock looks frozen: the activity is likely in `paused`/`finished`
      status (static string). Confirm `matchStatus` is `live` while running.
- [ ] If seconds drift vs the app: you're probably pushing `matchTime` but the device
      timer started from a stale `startDate`. Every `update` recomputes it — make sure
      `updateMatch` is actually being called (check the Xcode console for the
      `[RugbyLiveActivities]` warnings, or add an `os_log` in `pushUpdate`).
- [ ] **"Activity never appears":** 90% of the time it's missing shared target membership
      on `RugbyMatchAttributes.swift` (Step 4) or `NSSupportsLiveActivities` not set.
- [ ] **Update budget:** ActivityKit rate-limits frequent updates. The throttle in the
      integration helper (push only on change, else every 10s) keeps you well within it.
- [ ] Inspect live activities with **Console.app** → filter by your device and the
      `liveactivitiesd` / `RugbyLiveActivityWidget` processes for ActivityKit errors.
