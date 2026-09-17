# Combined App Spec — white noise + smart wake

**Status:** Approved 2026-07-28. Ships as a yolo-alarm update; reverse-alarm is retired (App Store sunset is Tim's identity-required task).
**Superseded by:** [`spec/stir.md`](spec/stir.md), 2026-09-15. Kept as the record of the white-noise merge.
**Base:** `yolo-alarm` repo. `reverse-alarm` is a fork of it; we port its one unique service (`WhiteNoisePlayer` + fade logic) into yolo-alarm and retire the reverse-alarm codebase.

## The product

One overnight session that replaces running both apps. **The only nightly input is the "up by" time** — the moment the fallback alarm fires no matter what. Everything else counts back from it using configured durations:

```
                                windowStart = upBy − windowDuration
bedtime ──────────────────────────► windowStart ─────────► upBy
   │  white noise (all night)  │ fade │  quiet gap  │ listening │ alarm
                               ▲      ▲             ▲
                    fade begins│      │fade complete│calibration + mic/motion
                               │      │= windowStart − quietGap
```

1. **Start session** at bedtime: set "up by", tap start. White noise loops all night.
2. **Fade-out** begins at `windowStart − quietGap − fadeOutMinutes` and completes at `windowStart − quietGap`.
3. **Quiet gap** (default 30 min, configured in settings): silence. This also guarantees the mic calibration baseline isn't polluted by white noise.
4. **Window start** (`upBy − windowDuration`): existing yolo behavior unchanged — calibrate, then listen for stirring (sound + motion).
5. **Wake:** stirring detected → gentle alarm; "up by" reached → fallback alarm fires regardless.

The wake window duration (default 30 min, matching yolo's current 6:30–7:00 default) is a set-once config in settings, alongside quiet gap and fade duration. The nightly flow is: one time picker, one button.

### No-alarm mode (gentlest wake)

A nightly toggle on the setup screen: **alarm on / off**. With the alarm off, the absence of white noise *is* the wake signal — reverse-alarm's original product, preserved as a mode:

```
bedtime ─────────────────────────────► upBy
   │  white noise (all night)  │ fade │ silence — you notice, you're up
```

- Fade completes exactly at `wakeUpBy`; no quiet gap, no wake window, no fallback alarm.
- The mic is never activated in this mode (privacy: mic permission isn't even needed for an alarm-off night).
- Session screen stays up through the fade and offers dismiss, like reverse-alarm's PlayingView did.
- Requires `whiteNoiseEnabled`; the setup screen disables the alarm-off toggle when white noise is off (a session with neither is nothing).

White noise is optional per session (toggle). With it off, the app behaves exactly like today's yolo alarm.

## Settings model (merged `AlarmSettings`)

Keep everything yolo-alarm has today **except** `wakeWindowStart`/`wakeWindowEnd`, which are replaced:

| Field | Type | Default | Notes |
|---|---|---|---|
| `wakeUpBy` | `Date` | 7:00 AM | **replaces** `wakeWindowStart`/`End`; the one nightly input |
| `wakeWindowMinutes` | `Int` | `30` | settings-level config, 10–90; `windowStart` is derived: `upBy − windowMinutes` |
| `alarmEnabled` | `Bool` | `true` | nightly toggle; off = no-alarm mode (fade-to-silence wake) |
| `whiteNoiseEnabled` | `Bool` | `true` | per-session toggle lives on setup screen |
| `whiteNoiseSound` | `WhiteNoiseSound` | `.oceanWaves` | reverse-alarm's enum, ported as-is |
| `whiteNoiseVolume` | `Float` | `0.7` | independent of alarm volume |
| `whiteNoiseCustomSoundId` | `UUID?` | `nil` | see CustomSoundManager note |
| `fadeOutMinutes` | `Int` | `10` | reverse-alarm's existing range (5–60) |
| `quietGapMinutes` | `Int` | `30` | 0–120; the "specified amount of time before listening" |

`wakeTime` from reverse-alarm is likewise dropped — `wakeUpBy` plays that role. `recalculateWakeWindow` becomes `recalculateWakeUpBy` (same next-occurrence logic on a single time); all phase boundaries are computed from it, never stored. Settings migration: existing yolo users' stored `wakeWindowEnd` time-of-day becomes `wakeUpBy`, and the stored window length (end − start) seeds `wakeWindowMinutes`.

## Audio architecture

Single `AVAudioSession` (`.playAndRecord`, `.mixWithOthers`, `defaultToSpeaker`) owned by `AudioMonitor`'s engine for the entire session — exactly what yolo does today. Changes:

- `WhiteNoisePlayer` currently sets its own `.playback` session; strip that out and have it play through/alongside the shared session. It must never deactivate the session (its current `setActive(false)` on stop would kill monitoring).
- The engine runs from session start (already true in yolo). Detection evaluation still begins only at window start.
- Privacy copy (`NSMicrophoneUsageDescription`, PRIVACY.md, site) needs updating: mic session is technically active from bedtime, even though nothing is evaluated or recorded before the window.

## CustomSoundManager

Now serves two slots: custom alarm sound (existing) and custom white noise (ported). The files were identical between repos; extend with a slot/category discriminator rather than duplicating the manager.

## UI

- **SetupView:** the two window pickers collapse to a single "up by" time picker plus the white-noise toggle — the nightly surface is one picker, one button. A caption shows the derived timeline for tonight (e.g. "white noise until 6:00 · listening from 6:30 · up by 7:00").
- **SettingsView:** gains wake window duration, quiet gap, fade duration, white noise sound/volume pickers.
- **MonitoringView** absorbs reverse-alarm's PlayingView: one night screen with a phase indicator (playing → fading → quiet → listening → alarm) instead of two separate screens. `AppScreen.playing` from reverse-alarm is not ported; phases are state within monitoring.
- **Live Activity:** add the pre-window phases (white noise / fading / quiet) to the existing attributes.
- **Onboarding:** one new card explaining the night timeline.

## Edge cases the build must handle

- Session started *inside* the fade or quiet gap (late bedtime): skip straight to the correct phase.
- Session started with less than `fadeOut + quietGap` before window start: compress fade, or skip white noise entirely if inside the gap — never let white noise overlap the window.
- White noise disabled: timeline collapses to today's yolo behavior.
- Audio interruption (call, Siri) during white noise: reuse AudioMonitor's existing interruption recovery; resume white noise at the correct phase for the current time, not where playback left off.
- "Up by" recalculation across midnight (next-occurrence logic, as today) anchors every phase boundary; all derived times are computed from it at evaluation time, never stored.
- Changing `wakeWindowMinutes`/`quietGapMinutes` in settings mid-session: either recompute the live timeline or lock config for the running session — build picks one and is consistent.

## Resolved decisions (Tim, 2026-07-28)

1. **Identity:** ships as a yolo-alarm update; reverse-alarm retired. App Store sunset is Tim's task.
2. **No-alarm mode:** yes — see "No-alarm mode" section above.
3. **Themes/haptics:** yolo's existing settings apply globally; nothing phase-specific.
