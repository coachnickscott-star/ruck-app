//
//  RugbyLiveActivitiesPlugin.swift
//  RugbyCoach.AI
//
//  Capacitor plugin that drives a Live Activity showing the live rugby match
//  score, clock, half and status on the Lock Screen and in the Dynamic Island.
//
//  TARGET MEMBERSHIP: this file belongs to the "App" target ONLY.
//  (The shared model `RugbyMatchAttributes.swift` is the file that goes in both targets.)
//
//  Requires iOS 16.1+ for ActivityKit. All ActivityKit calls are guarded so the
//  plugin loads and fails gracefully on older OS versions.
//

import Foundation
import Capacitor
import ActivityKit

/// Capacitor bridge for ActivityKit Live Activities.
///
/// We adopt `CAPBridgedPlugin` (the modern Capacitor 6+/7/8 registration path). This
/// declares the plugin's JS name and method list in Swift, so NO Objective-C `.m`
/// bridging file is required.
@objc(RugbyLiveActivitiesPlugin)
public class RugbyLiveActivitiesPlugin: CAPPlugin, CAPBridgedPlugin {

    // MARK: - CAPBridgedPlugin registration metadata

    /// Internal identifier — must match the @objc class name above.
    public let identifier = "RugbyLiveActivitiesPlugin"

    /// The name the plugin is exposed under to JavaScript:
    /// `Capacitor.Plugins.RugbyLiveActivities` / `registerPlugin('RugbyLiveActivities')`.
    public let jsName = "RugbyLiveActivities"

    /// Every method callable from JS must be declared here with its return style.
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startMatchActivity",  returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "updateMatchActivity", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "endMatchActivity",    returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isSupported",         returnType: CAPPluginReturnPromise)
    ]

    // MARK: - Internal state

    /// Tracks the currently running activity, keyed by `matchId`.
    ///
    /// `Activity` is generic over the attributes type, so we keep a typed dictionary.
    /// We only ever expect one live match at a time, but keying by id keeps update/end
    /// targeting unambiguous and makes "activity already running" trivial to detect.
    @available(iOS 16.1, *)
    private var activities: [String: Activity<RugbyMatchAttributes>] {
        get { _activities as? [String: Activity<RugbyMatchAttributes>] ?? [:] }
        set { _activities = newValue }
    }
    /// Type-erased backing store (stored properties can't carry @available).
    private var _activities: Any = [String: Any]()

    // MARK: - isSupported

    /// Lets the JS layer ask, before doing anything else, whether Live Activities are
    /// available on this device and currently enabled by the user in Settings.
    @objc func isSupported(_ call: CAPPluginCall) {
        guard #available(iOS 16.1, *) else {
            call.resolve(["supported": false, "reason": "iOS 16.1 or later is required"])
            return
        }
        let enabled = ActivityAuthorizationInfo().areActivitiesEnabled
        call.resolve([
            "supported": enabled,
            "reason": enabled ? "" : "Live Activities are turned off in Settings"
        ])
    }

    // MARK: - startMatchActivity

    /// Launches a new Live Activity for a match.
    ///
    /// Expected JS payload (see `MatchData` in rugby-live-activities.ts):
    /// ```
    /// { matchId, homeTeam, awayTeam, homeScore, awayScore, matchTime, matchStatus, halfNumber }
    /// ```
    @objc func startMatchActivity(_ call: CAPPluginCall) {
        guard #available(iOS 16.1, *) else {
            call.reject("Live Activities require iOS 16.1 or later.")
            return
        }

        // The user can disable Live Activities globally; respect that.
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            call.reject("Live Activities are disabled. Enable them in Settings → RugbyCoach.AI.")
            return
        }

        // Parse + validate the incoming match payload.
        let parsed: ParsedMatch
        do {
            parsed = try parseMatch(call)
        } catch let error as ValidationError {
            call.reject(error.message)
            return
        } catch {
            call.reject("Invalid match data: \(error.localizedDescription)")
            return
        }

        // Edge case: an activity for this match is already live. Rather than erroring,
        // we transparently update it — this makes the JS side idempotent and avoids
        // duplicate activities if startMatch() is called twice.
        if let existing = activities[parsed.matchId] {
            Task { await pushUpdate(to: existing, with: parsed.contentState, call: call, started: false) }
            return
        }

        let attributes = RugbyMatchAttributes(
            matchId: parsed.matchId,
            homeTeam: parsed.homeTeam,
            awayTeam: parsed.awayTeam
        )

        do {
            // `Activity.request` is how an app starts a Live Activity from the foreground.
            let activity: Activity<RugbyMatchAttributes>
            if #available(iOS 16.2, *) {
                // iOS 16.2+ wraps the state in `ActivityContent` and supports `staleDate`,
                // which tells the system when the content should be considered out of date.
                activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: parsed.contentState, staleDate: nil),
                    pushType: nil // nil = locally-updated activity (no APNs push token needed)
                )
            } else {
                // iOS 16.1 used the older `contentState:` initializer.
                activity = try Activity.request(
                    attributes: attributes,
                    contentState: parsed.contentState,
                    pushType: nil
                )
            }

            activities[parsed.matchId] = activity
            call.resolve([
                "started": true,
                "matchId": parsed.matchId,
                "activityId": activity.id
            ])
        } catch {
            // Most common failure here is exceeding the system limit on concurrent
            // activities, or the feature being unavailable.
            call.reject("Failed to start Live Activity: \(error.localizedDescription)")
        }
    }

    // MARK: - updateMatchActivity

    /// Pushes new scores / clock / status into the already-running activity.
    @objc func updateMatchActivity(_ call: CAPPluginCall) {
        guard #available(iOS 16.1, *) else {
            call.reject("Live Activities require iOS 16.1 or later.")
            return
        }

        let parsed: ParsedMatch
        do {
            parsed = try parseMatch(call)
        } catch let error as ValidationError {
            call.reject(error.message)
            return
        } catch {
            call.reject("Invalid match data: \(error.localizedDescription)")
            return
        }

        // Edge case: nothing to update because the activity isn't running.
        guard let activity = activities[parsed.matchId] else {
            call.reject("No running Live Activity for matchId \(parsed.matchId). Call startMatch() first.")
            return
        }

        Task { await pushUpdate(to: activity, with: parsed.contentState, call: call, started: false) }
    }

    // MARK: - endMatchActivity

    /// Gracefully closes the Live Activity. JS passes just `{ matchId }`, but we also
    /// accept the full match payload so the final frame can show the closing score.
    @objc func endMatchActivity(_ call: CAPPluginCall) {
        guard #available(iOS 16.1, *) else {
            call.reject("Live Activities require iOS 16.1 or later.")
            return
        }

        guard let matchId = call.getString("matchId"), !matchId.isEmpty else {
            call.reject("Missing required field: matchId")
            return
        }

        guard let activity = activities[matchId] else {
            // Already gone — treat as success so the JS caller doesn't have to care.
            call.resolve(["ended": true, "matchId": matchId, "alreadyEnded": true])
            return
        }

        // Build the final content frame. Prefer fields supplied on the end call;
        // otherwise fall back to whatever the activity is currently showing.
        let finalState = finalContentState(from: call, current: activity)

        Task {
            if #available(iOS 16.2, *) {
                // `.default` dismissal lets the system keep the final frame briefly,
                // then remove it — the expected behaviour for a finished match.
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .default
                )
            } else {
                await activity.end(using: finalState, dismissalPolicy: .default)
            }
            await MainActor.run {
                self.activities[matchId] = nil
                call.resolve(["ended": true, "matchId": matchId])
            }
        }
    }

    // MARK: - Shared update helper

    @available(iOS 16.1, *)
    private func pushUpdate(to activity: Activity<RugbyMatchAttributes>,
                            with state: RugbyMatchAttributes.ContentState,
                            call: CAPPluginCall,
                            started: Bool) async {
        if #available(iOS 16.2, *) {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        } else {
            await activity.update(using: state)
        }
        await MainActor.run {
            call.resolve([
                "updated": true,
                "started": started,
                "matchId": activity.attributes.matchId,
                "activityId": activity.id
            ])
        }
    }

    @available(iOS 16.1, *)
    private func finalContentState(from call: CAPPluginCall,
                                   current activity: Activity<RugbyMatchAttributes>) -> RugbyMatchAttributes.ContentState {
        // Read the currently-displayed state. `Activity.content` is iOS 16.2+, so fall
        // back to the (deprecated) `contentState` accessor on 16.1.
        let now: RugbyMatchAttributes.ContentState
        if #available(iOS 16.2, *) {
            now = activity.content.state
        } else {
            now = activity.contentState
        }
        let homeScore = call.getInt("homeScore") ?? now.homeScore
        let awayScore = call.getInt("awayScore") ?? now.awayScore
        let matchTime = call.getString("matchTime") ?? now.matchTime
        let halfNumber = call.getInt("halfNumber") ?? now.halfNumber
        return RugbyMatchAttributes.ContentState(
            homeScore: homeScore,
            awayScore: awayScore,
            matchTime: matchTime,
            matchStatus: RugbyMatchStatus.finished.rawValue,
            halfNumber: halfNumber,
            startDate: now.startDate
        )
    }

    // MARK: - Parsing & validation

    private struct ParsedMatch {
        let matchId: String
        let homeTeam: String
        let awayTeam: String
        let contentState: RugbyMatchAttributes.ContentState
    }

    private struct ValidationError: Error { let message: String }

    /// Parses and validates the JS payload into strongly-typed values, throwing a
    /// `ValidationError` with a human-readable message on any bad/missing field.
    @available(iOS 16.1, *)
    private func parseMatch(_ call: CAPPluginCall) throws -> ParsedMatch {
        guard let matchId = call.getString("matchId"), !matchId.isEmpty else {
            throw ValidationError(message: "Missing required field: matchId")
        }
        guard let homeTeam = call.getString("homeTeam"), !homeTeam.isEmpty else {
            throw ValidationError(message: "Missing required field: homeTeam")
        }
        guard let awayTeam = call.getString("awayTeam"), !awayTeam.isEmpty else {
            throw ValidationError(message: "Missing required field: awayTeam")
        }

        // Scores default to 0 (kickoff) if omitted; reject negatives outright.
        let homeScore = call.getInt("homeScore") ?? 0
        let awayScore = call.getInt("awayScore") ?? 0
        guard homeScore >= 0, awayScore >= 0 else {
            throw ValidationError(message: "Scores cannot be negative.")
        }

        let halfNumber = call.getInt("halfNumber") ?? 1
        guard (1...2).contains(halfNumber) else {
            throw ValidationError(message: "halfNumber must be 1 or 2.")
        }

        let matchTime = call.getString("matchTime") ?? "00:00"
        guard isValidClock(matchTime) else {
            throw ValidationError(message: "matchTime must be formatted as MM:SS (e.g. \"23:45\").")
        }

        let statusRaw = call.getString("matchStatus") ?? RugbyMatchStatus.live.rawValue
        guard let status = RugbyMatchStatus(rawValue: statusRaw) else {
            throw ValidationError(message: "matchStatus must be one of: live, paused, finished.")
        }

        // Derive the timer reference instant so the lock screen can tick on its own:
        // startDate = now − elapsedSeconds(matchTime).
        let elapsed = seconds(fromClock: matchTime)
        let startDate = Date().addingTimeInterval(-Double(elapsed))

        let state = RugbyMatchAttributes.ContentState(
            homeScore: homeScore,
            awayScore: awayScore,
            matchTime: matchTime,
            matchStatus: status.rawValue,
            halfNumber: halfNumber,
            startDate: startDate
        )

        return ParsedMatch(matchId: matchId, homeTeam: homeTeam, awayTeam: awayTeam, contentState: state)
    }

    /// Validates a "MM:SS" (or "M:SS" / "MMM:SS") clock string.
    private func isValidClock(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let _ = Int(parts[0]),
              let secs = Int(parts[1]),
              (0..<60).contains(secs) else { return false }
        return true
    }

    /// Converts "MM:SS" into a total number of seconds.
    private func seconds(fromClock value: String) -> Int {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let m = Int(parts[0]),
              let s = Int(parts[1]) else { return 0 }
        return m * 60 + s
    }
}
