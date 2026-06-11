/**
 * rugby-live-activities.ts
 *
 * TypeScript bridge for the native `RugbyLiveActivities` Capacitor plugin.
 *
 * This wraps the Swift plugin (RugbyLiveActivitiesPlugin.swift) so the web/JS layer
 * of RugbyCoach.AI can start, update and end a Lock Screen / Dynamic Island
 * Live Activity during a live match.
 *
 * Live Activities are iOS 16.1+ only. On Android, the web, or older iOS the methods
 * resolve to safe no-ops (see the `isAvailable()` guard) so your match code never has
 * to branch on platform.
 *
 * If you use TypeScript in this project, import from here. If the app is plain JS in
 * www/index.html, see INTEGRATION_EXAMPLE.md for a compiled/inline version.
 */

import { registerPlugin, Capacitor } from '@capacitor/core';

/* -------------------------------------------------------------------------- */
/*  Types                                                                      */
/* -------------------------------------------------------------------------- */

/** Match status mirrored from the native `RugbyMatchStatus` enum. */
export type MatchStatus = 'live' | 'paused' | 'finished';

/** Half indicator: 1st or 2nd half. */
export type HalfNumber = 1 | 2;

/**
 * The full match payload sent to the native layer.
 *
 * `matchTime` is the authoritative clock as a "MM:SS" string (e.g. "23:45"); the
 * native side derives a self-ticking timer from it so the Lock Screen stays accurate
 * between updates.
 */
export interface MatchData {
  /** Stable unique id for this match (used to target update/end). */
  matchId: string;
  /** Home team display name. */
  homeTeam: string;
  /** Away team display name. */
  awayTeam: string;
  /** Home team score. */
  homeScore: number;
  /** Away team score. */
  awayScore: number;
  /** Elapsed match time formatted as "MM:SS". */
  matchTime: string;
  /** Current status of the match. */
  matchStatus: MatchStatus;
  /** Current half (1 or 2). */
  halfNumber: HalfNumber;
}

export interface StartResult {
  started: boolean;
  matchId: string;
  activityId?: string;
}

export interface UpdateResult {
  updated: boolean;
  matchId: string;
  activityId?: string;
}

export interface EndResult {
  ended: boolean;
  matchId: string;
  alreadyEnded?: boolean;
}

export interface SupportResult {
  /** True only on iOS 16.1+ with Live Activities enabled in Settings. */
  supported: boolean;
  /** Human-readable reason when `supported` is false. */
  reason: string;
}

/**
 * The raw native interface as exposed by Capacitor. You normally use the
 * `RugbyLiveActivities` wrapper below rather than this directly.
 */
export interface RugbyLiveActivitiesPlugin {
  startMatchActivity(options: MatchData): Promise<StartResult>;
  updateMatchActivity(options: MatchData): Promise<UpdateResult>;
  endMatchActivity(options: { matchId: string } & Partial<MatchData>): Promise<EndResult>;
  isSupported(): Promise<SupportResult>;
}

/* -------------------------------------------------------------------------- */
/*  Plugin registration                                                        */
/* -------------------------------------------------------------------------- */

/**
 * `registerPlugin` matches the `jsName` declared in the Swift `CAPBridgedPlugin`
 * conformance ("RugbyLiveActivities"). The web fallback returns a stub whose methods
 * resolve to harmless values, so calling them off-device never throws.
 */
const Native = registerPlugin<RugbyLiveActivitiesPlugin>('RugbyLiveActivities', {
  web: () => {
    const noop = async () => ({});
    return {
      startMatchActivity: noop,
      updateMatchActivity: noop,
      endMatchActivity: noop,
      isSupported: async () => ({ supported: false, reason: 'Not running on iOS' }),
    } as unknown as RugbyLiveActivitiesPlugin;
  },
});

/* -------------------------------------------------------------------------- */
/*  Friendly wrapper                                                           */
/* -------------------------------------------------------------------------- */

/**
 * High-level helper around the native plugin. Handles platform guarding and basic
 * client-side validation so callers get clear errors before hitting the bridge.
 */
export class RugbyLiveActivities {
  /** Cached support result so we don't re-query the bridge on every timer tick. */
  private static supportCache: SupportResult | null = null;

  /** True if we're on a platform that can show Live Activities at all (iOS native). */
  static isAvailable(): boolean {
    return Capacitor.getPlatform() === 'ios' && Capacitor.isNativePlatform();
  }

  /** Queries (and caches) whether the device actually supports & has enabled them. */
  static async isSupported(): Promise<SupportResult> {
    if (!this.isAvailable()) {
      return { supported: false, reason: 'Live Activities require an iOS device.' };
    }
    if (this.supportCache) return this.supportCache;
    this.supportCache = await Native.isSupported();
    return this.supportCache;
  }

  /** Launches the Live Activity for a match. Returns null if unsupported. */
  static async startMatch(matchData: MatchData): Promise<StartResult | null> {
    if (!this.isAvailable()) return null;
    this.validate(matchData);
    try {
      return await Native.startMatchActivity(matchData);
    } catch (err) {
      console.warn('[RugbyLiveActivities] startMatch failed:', err);
      throw err;
    }
  }

  /**
   * Updates the running activity with new scores / time / status.
   *
   * This is safe to call frequently from the match timer loop. To respect ActivityKit's
   * update budget, throttle calls so you only push when something visible changes (see
   * INTEGRATION_EXAMPLE.md) rather than on every 100ms tick.
   */
  static async updateMatch(matchData: MatchData): Promise<UpdateResult | null> {
    if (!this.isAvailable()) return null;
    this.validate(matchData);
    try {
      return await Native.updateMatchActivity(matchData);
    } catch (err) {
      console.warn('[RugbyLiveActivities] updateMatch failed:', err);
      throw err;
    }
  }

  /** Gracefully closes the activity at full time. */
  static async endMatch(matchId: string, finalData?: Partial<MatchData>): Promise<EndResult | null> {
    if (!this.isAvailable()) return null;
    if (!matchId) throw new Error('endMatch requires a matchId.');
    try {
      return await Native.endMatchActivity({ matchId, ...finalData });
    } catch (err) {
      console.warn('[RugbyLiveActivities] endMatch failed:', err);
      throw err;
    }
  }

  /** Lightweight client-side validation that mirrors the native checks. */
  private static validate(m: MatchData): void {
    if (!m.matchId) throw new Error('matchId is required.');
    if (!m.homeTeam || !m.awayTeam) throw new Error('homeTeam and awayTeam are required.');
    if (m.homeScore < 0 || m.awayScore < 0) throw new Error('Scores cannot be negative.');
    if (!/^\d{1,3}:[0-5]\d$/.test(m.matchTime)) {
      throw new Error('matchTime must be "MM:SS", e.g. "23:45".');
    }
    if (m.halfNumber !== 1 && m.halfNumber !== 2) throw new Error('halfNumber must be 1 or 2.');
    if (!['live', 'paused', 'finished'].includes(m.matchStatus)) {
      throw new Error('matchStatus must be live, paused or finished.');
    }
  }
}

export default RugbyLiveActivities;
