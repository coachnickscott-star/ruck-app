//
//  RugbyLiveActivitiesWidget.swift
//  RugbyLiveActivityWidget (Widget Extension target)
//
//  SwiftUI presentation for the rugby match Live Activity:
//    • Lock Screen / banner view
//    • Dynamic Island — compact (leading/trailing), minimal, and expanded regions
//
//  TARGET MEMBERSHIP: this file belongs to the "RugbyLiveActivityWidget" target ONLY.
//  The shared model `RugbyMatchAttributes.swift` must be a member of BOTH this target
//  and the "App" target.
//

import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Brand palette

/// Rugby-pitch green accent + supporting colours. Defined once so the lock screen and
/// the Dynamic Island stay visually consistent.
private enum RugbyTheme {
    /// Pitch green — the primary brand accent.
    static let pitchGreen   = Color(red: 0.18, green: 0.55, blue: 0.28)
    static let pitchGreenLt = Color(red: 0.30, green: 0.72, blue: 0.40)
    /// Live indicator red.
    static let liveRed      = Color(red: 0.90, green: 0.22, blue: 0.21)
    /// Paused amber.
    static let pausedAmber  = Color(red: 0.98, green: 0.62, blue: 0.11)
}

// MARK: - Widget / Activity configuration

@available(iOS 16.1, *)
struct RugbyLiveActivitiesWidget: Widget {
    var body: some WidgetConfiguration {
        // `ActivityConfiguration` binds our shared attributes type to the UI. ActivityKit
        // calls these closures whenever the app pushes a new `ContentState`.
        ActivityConfiguration(for: RugbyMatchAttributes.self) { context in

            // ---- LOCK SCREEN / BANNER PRESENTATION ----
            RugbyLockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85)) // dark, sits well on the Lock Screen
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in

            // ---- DYNAMIC ISLAND PRESENTATION ----
            DynamicIsland {

                // EXPANDED (long-press) — full match details across the regions.
                DynamicIslandExpandedRegion(.leading) {
                    TeamColumn(name: context.attributes.homeTeam,
                               score: context.state.homeScore,
                               alignment: .leading)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TeamColumn(name: context.attributes.awayTeam,
                               score: context.state.awayScore,
                               alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        StatusBadge(state: context.state)
                        Text("–")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        ClockView(state: context.state, font: .system(size: 18, weight: .semibold, design: .rounded))
                        Text("·").foregroundColor(.secondary)
                        Text(halfLabel(for: context.state))
                            .font(.caption.weight(.semibold))
                            .foregroundColor(RugbyTheme.pitchGreenLt)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 2)
                }

            } compactLeading: {
                // COMPACT LEADING — just the running score "H-A".
                Text("\(context.state.homeScore)-\(context.state.awayScore)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            } compactTrailing: {
                // COMPACT TRAILING — the match clock.
                ClockView(state: context.state, font: .system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundColor(RugbyTheme.pitchGreenLt)
            } minimal: {
                // MINIMAL — when sharing the island with another activity. Score only.
                Text("\(context.state.homeScore)-\(context.state.awayScore)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(RugbyTheme.pitchGreenLt)
            }
            .widgetURL(URL(string: "rugbycoach://match/\(context.attributes.matchId)")) // deep-link back into the app
            .keylineTint(RugbyTheme.pitchGreen)
        }
    }
}

// MARK: - Lock Screen view

@available(iOS 16.1, *)
private struct RugbyLockScreenView: View {
    let context: ActivityViewContext<RugbyMatchAttributes>

    var body: some View {
        VStack(spacing: 10) {

            // Top row: LIVE badge + half indicator
            HStack {
                LiveIndicator(state: context.state)
                Spacer()
                Text(halfLabel(for: context.state))
                    .font(.caption.weight(.bold))
                    .foregroundColor(RugbyTheme.pitchGreenLt)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(RugbyTheme.pitchGreen.opacity(0.22))
                    .clipShape(Capsule())
            }

            // Score row: HOME  score  –  score  AWAY
            HStack(alignment: .center, spacing: 12) {
                TeamColumn(name: context.attributes.homeTeam,
                           score: context.state.homeScore,
                           alignment: .leading)

                Text("–")
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .foregroundColor(.white.opacity(0.5))

                TeamColumn(name: context.attributes.awayTeam,
                           score: context.state.awayScore,
                           alignment: .trailing)
            }

            // Clock row
            ClockView(state: context.state,
                      font: .system(size: 30, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        // Subtle pitch-green gradient wash so the banner feels on-brand in dark mode.
        .background(
            LinearGradient(
                colors: [RugbyTheme.pitchGreen.opacity(0.28), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }
}

// MARK: - Reusable pieces

/// A team name stacked above its score, left- or right-aligned.
@available(iOS 16.1, *)
private struct TeamColumn: View {
    let name: String
    let score: Int
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundColor(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(score)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .contentTransition(.numericText()) // animates the digit when the score changes
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

/// The match clock. While the match is *live* it uses `Text(timerInterval:)`, which the
/// system ticks every second on-device — so the time stays accurate even between the
/// app's pushed updates. When paused/finished it shows the static "MM:SS" string.
@available(iOS 16.1, *)
private struct ClockView: View {
    let state: RugbyMatchAttributes.ContentState
    let font: Font

    var body: some View {
        Group {
            if state.status == .live {
                // countsDown:false → counts UP from startDate. The far-future end keeps
                // it running for the whole match. Monospaced digits stop layout jitter.
                Text(timerInterval: state.startDate...Date.distantFuture,
                     countsDown: false)
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
            } else {
                Text(state.matchTime)
                    .monospacedDigit()
            }
        }
        .font(font)
    }
}

/// Pulsing dot + "LIVE" / "PAUSED" / "FULL TIME" badge.
@available(iOS 16.1, *)
private struct LiveIndicator: View {
    let state: RugbyMatchAttributes.ContentState
    @State private var pulse = false

    private var tint: Color {
        switch state.status {
        case .live:     return RugbyTheme.liveRed
        case .paused:   return RugbyTheme.pausedAmber
        case .finished: return .gray
        }
    }

    private var label: String {
        switch state.status {
        case .live:     return "LIVE"
        case .paused:   return "PAUSED"
        case .finished: return "FULL TIME"
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 8, height: 8)
                // Gentle pulse to draw the eye while live. Disabled when not live.
                .scaleEffect(pulse && state.status == .live ? 1.0 : 0.6)
                .opacity(pulse && state.status == .live ? 1.0 : 0.5)
                .animation(
                    state.status == .live
                        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                        : .default,
                    value: pulse
                )
            Text(label)
                .font(.caption2.weight(.heavy))
                .foregroundColor(tint)
                .tracking(1.0)
        }
        .onAppear { pulse = true }
    }
}

/// Compact status badge used inside the Dynamic Island expanded center region.
@available(iOS 16.1, *)
private struct StatusBadge: View {
    let state: RugbyMatchAttributes.ContentState
    var body: some View {
        LiveIndicator(state: state)
    }
}

// MARK: - Helpers

@available(iOS 16.1, *)
private func halfLabel(for state: RugbyMatchAttributes.ContentState) -> String {
    if state.status == .finished { return "FT" }
    // Half-time is represented by the app pausing between halves; we surface the
    // current half number, and "HT" if explicitly paused on half 1's end.
    return state.halfNumber == 1 ? "1st Half" : "2nd Half"
}

// MARK: - Xcode previews
//
// Previews let you iterate on the design without running a full match. In Xcode 15+,
// select the canvas and use the Live Activity preview traits below.

@available(iOS 16.2, *)
struct RugbyLiveActivitiesWidget_Previews: PreviewProvider {
    static let attributes = RugbyMatchAttributes(
        matchId: "preview-1",
        homeTeam: "Saracens",
        awayTeam: "Harlequins"
    )
    static let liveState = RugbyMatchAttributes.ContentState(
        homeScore: 17,
        awayScore: 12,
        matchTime: "23:45",
        matchStatus: "live",
        halfNumber: 1,
        startDate: Date().addingTimeInterval(-1425) // 23:45 ago
    )

    static var previews: some View {
        attributes
            .previewContext(liveState, viewKind: .content)
            .previewDisplayName("Lock Screen")

        attributes
            .previewContext(liveState, viewKind: .dynamicIsland(.compact))
            .previewDisplayName("Island — Compact")

        attributes
            .previewContext(liveState, viewKind: .dynamicIsland(.expanded))
            .previewDisplayName("Island — Expanded")

        attributes
            .previewContext(liveState, viewKind: .dynamicIsland(.minimal))
            .previewDisplayName("Island — Minimal")
    }
}
