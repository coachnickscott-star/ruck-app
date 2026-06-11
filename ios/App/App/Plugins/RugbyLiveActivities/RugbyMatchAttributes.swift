//
//  RugbyMatchAttributes.swift
//  RugbyCoach.AI
//
//  Shared ActivityKit data model for the live match Live Activity.
//
//  ⚠️ TARGET MEMBERSHIP IS CRITICAL ⚠️
//  This single file MUST belong to BOTH targets:
//    1. "App"                    (the Capacitor host app — produces & updates the activity)
//    2. "RugbyLiveActivityWidget" (the Widget Extension — renders the activity UI)
//  Select the file in Xcode → File Inspector → "Target Membership" and tick BOTH boxes.
//  If only one target has it, the app and the widget will see two *different* types and
//  the Live Activity will silently never appear.
//

import Foundation
import ActivityKit

/// `ActivityAttributes` is the ActivityKit contract for a Live Activity.
///
/// It has two parts:
///   • The *static* attributes (properties on the struct itself) — set ONCE when the
///     activity starts and never change for the life of the activity. Good for things
///     like the match id and the two team names.
///   • The *dynamic* `ContentState` (a nested struct) — the part you push updates to.
///     Scores, the clock, the half and the status all live here because they change
///     while the match is in progress.
@available(iOS 16.1, *)
public struct RugbyMatchAttributes: ActivityAttributes {

    /// The live, push-updatable portion of the activity.
    /// Must be `Codable` & `Hashable` — ActivityKit requires it.
    public struct ContentState: Codable, Hashable {
        /// Home team's current score.
        public var homeScore: Int
        /// Away team's current score.
        public var awayScore: Int

        /// Pre-formatted "MM:SS" elapsed time. Always present and always correct,
        /// used as the source of truth and as the fallback when the match is not live.
        public var matchTime: String

        /// Raw match status string: "live", "paused" or "finished".
        /// Stored as String (not the enum) so it survives JSON round-tripping cleanly.
        public var matchStatus: String

        /// Current half: 1 or 2.
        public var halfNumber: Int

        /// The wall-clock instant at which the match clock read 00:00.
        ///
        /// This is the trick that lets the lock screen tick every second *without*
        /// the app pushing an update every second. SwiftUI's `Text(timerInterval:)`
        /// renders a self-updating timer purely on-device. We recompute this on every
        /// `update` (startDate = now − elapsed) so the timer can never drift out of sync.
        ///
        /// Only used for display while `matchStatus == "live"`; when paused/finished we
        /// show the static `matchTime` string instead.
        public var startDate: Date

        public init(homeScore: Int,
                    awayScore: Int,
                    matchTime: String,
                    matchStatus: String,
                    halfNumber: Int,
                    startDate: Date) {
            self.homeScore = homeScore
            self.awayScore = awayScore
            self.matchTime = matchTime
            self.matchStatus = matchStatus
            self.halfNumber = halfNumber
            self.startDate = startDate
        }

        /// Convenience typed accessor for the status.
        public var status: RugbyMatchStatus {
            RugbyMatchStatus(rawValue: matchStatus) ?? .live
        }
    }

    // MARK: - Static attributes (fixed for the life of the activity)

    /// Stable unique identifier for the match. Used to find the right activity to
    /// update / end when several could theoretically exist.
    public var matchId: String
    /// Home team display name.
    public var homeTeam: String
    /// Away team display name.
    public var awayTeam: String

    public init(matchId: String, homeTeam: String, awayTeam: String) {
        self.matchId = matchId
        self.homeTeam = homeTeam
        self.awayTeam = awayTeam
    }
}

/// Strongly-typed match status. Kept separate from the attributes so it can be reused
/// by the plugin for validation and by the widget for branching the UI.
public enum RugbyMatchStatus: String, Codable, CaseIterable {
    case live
    case paused
    case finished
}
