# stir 1.1 — build

**status:** proposed, 15 september 2026. builds part nine of [`stir.md`](stir.md), auto sensitivity, together with the night record it reads and the corrections in its open 9. history, suggestions, Health and Siri are 1.2; their planned phases are kept below under "1.2, as planned". new sounds come after that, and start as a product decision, not a build.

**decisions this assumes.** confirm on review:

- **1.1 is auto sensitivity alone.** history, Health and Siri read the same record, but auto needs none of them, and a smaller release reaches the fourteen-night device check sooner.
- **new installs start on auto; existing installs keep their setting** (stir.md decision 60).
- **the shortest night that counts is three hours** before "up by" (open 10, decision 31).
- **the record is stored with SwiftData** (open 8).
- **the question is "was that too sensitive?", answered yes or no** — the owner's words, 15 september.

every constant and rule in phases 2 to 4 is in stir.md decisions 60–74 and in `tools/auto-sensitivity-sim.py`. where this document and the script disagree, the build stops and the spec is fixed first.

---

## how the work runs

- one branch and one pull request per phase, off `main`. nothing goes to `main` directly.
- tests are the gate. a phase merges with its unit and UI tests green on an iPhone 15 simulator, and after any device check the phase names.
- boot the simulator and wait for it before testing: `xcrun simctl bootstatus <udid> -b`. a unit test host launched while the simulator is still booting logs "test daemon not ready" and fails as "the test runner hung before establishing connection" — a slow full build hides it, and a fast incremental one exposes it.
- one decision per commit: `scope: decision — reason`.
- the owner merges, and the owner submits to App Review.
- a phase that finds the spec wrong stops and says so. the spec changes before the code does.
- research and the reasoning behind a decision are written into `docs/spec/`, next to the decision. a derivation that can be run lives in `tools/`.
- customer-facing copy is drafted in the pull request and is the owner's to approve before merge.

---

## phase 0 — test target and corrections

**work**

- a unit test target, `stir-tests`, beside `stir-uitests` in `project.yml` and in the `stir` scheme's test action.
- the three `CustomSoundError` messages in `CustomSoundManager.swift`, lowercased.
- the comment in `NightArcFace.swift` corrected: the sun's position is solar time. the technical details copy corrected to match stir.md principle 1.
- `PRIVACY.md` brought in line with the privacy section on the site, and lowercased.
- shared rooms (stir.md decision 59): the motion detection note in settings says anyone moving the phone sets it off, and where to put the phone. the note under the sensitivity picker changes with the choice to say what low, medium and high are tuned for. auto's note arrives in phase 3.

**done when** `stir-tests` runs in `xcodebuild test`; no user-facing string in `stir/` or `stir-widgets/` is capitalized apart from proper nouns; and a UI test shows low, medium and high each with its own note.

---

## phase 1 — the night record

the record is what auto sensitivity reads now, and what history, Health and suggestions read in 1.2. it is settled before anything reads it.

### schema

`NightRecord`, a SwiftData model. these fields and no others:

| field | type | why |
|---|---|---|
| `startedAt` | `Date` | lights out |
| `endedAt` | `Date` | up |
| `upBy` | `Date` | the promise that night |
| `windowStart` | `Date?` | the wake window as it was that night; `nil` on a no-alarm night (decision 37) |
| `listeningStartedAt` | `Date?` | when room calibration finished; `nil` if listening never began (decision 62) |
| `alarmFiredAt` | `Date?` | |
| `triggeredBy` | `AlarmTrigger` | `sound`, `motion`, `upBy`, `none` — what set off the alarm, never who (decision 57) |
| `ending` | `NightEnding` | `stopped`, `alarmDismissed`, `completed` |
| `sensitivity` | `Float` | the `sensitivityValue` the night started with (decision 71) |
| `alarmVolume` | `Float?` | media volume when the alarm started (decision 31) |
| `startedLocalMinute` | `Int` | minutes after local midnight when the night started |
| `endedLocalMinute` | `Int` | minutes after local midnight when it ended |

the two local-minute fields let a night read in the time it happened, where it happened, without storing a time zone, which would be a coarse record of where somebody was (decision 32). a field added later is a decision in `stir.md` first.

### a bug this fixes

when a finished no-alarm night is dismissed, `MonitoringView.endNight()` calls `stopMonitoring()`, which records `stopped` — the same as a night ended by hand. `AppState` gains `completeNight()`, which records `completed`, and `endNight()` calls it when the phase is `.complete`. `SessionRecord.Ending` gains `completed` too, labelled "finished", so the technical details screen tells the truth.

### work

- `AppState.startMonitoring` captures `settings.sensitivityValue` for the night. the record takes it from there, never from settings at the end of the night.
- `MonitoringView` reports the first `.listening` state each night from `audioMonitor.$monitoringState` to `AppState.markListeningStarted()`, which keeps the first time it is called and ignores the rest.
- `triggerAlarm` carries its reason from its three callers: the sound monitor, the motion monitor, and the "up by" fallback in `MonitoringView.tick()`.
- `AlarmPlayer` hands back the media volume it already reads when the alarm starts.
- `AppState.recordSessionEnd` keeps writing `lastSessionRecord` for every night, clean or not. alongside it, and only for a clean run, it writes a `NightRecord`.
- one function, `isCleanRun`, decides a clean run, so auto sensitivity, and later history and Health, share one definition. a night is a clean run when `upBy − startedAt` is at least `minimumNightLength` (3 hours, one named constant) and one of these holds:
  - `ending == .alarmDismissed`
  - `ending == .completed`
  - `ending == .stopped`, with `windowStart` set, `endedAt ≥ windowStart`, and `alarmFiredAt == nil`
- storage sits behind a `NightStore` protocol with `add(_:)` and `all()` (oldest first): a SwiftData implementation for the app, an in-memory one for tests. the model container is created in `StirApp`.
- no migration. the store starts empty in 1.1.

### tests (unit)

- each trigger reaches the record.
- `listeningStartedAt` is the first listening transition, not a later one, and is `nil` when the night ended during calibration.
- `sensitivity` is the value at the start of the night, even if settings change before it ends.
- a finished no-alarm night records `completed`, with `windowStart` and `listeningStartedAt` both `nil`.
- a night that never ends writes nothing.
- a night ended by hand before its wake window writes no `NightRecord`, and still updates `lastSessionRecord`.
- a night ended by hand inside its window, before the alarm, is a clean run.
- a night started 2 hours 59 minutes before "up by" writes no `NightRecord`; 3 hours exactly is a clean run.
- a test fails if `NightRecord` gains a stored field not in the table above, so the line in decision 32 is enforced by the build rather than remembered.

---

## phase 2 — the evaluator

pure functions with no UI and no storage, so every judgment auto makes is under test. one file, `stir/Models/AutoSensitivity.swift`.

### types

- `NightFacts`: a value type with the record fields the evaluator reads — `startedAt`, `upBy`, `endedAt`, `listeningStartedAt`, `alarmFiredAt`, `triggeredBy`, `sensitivity`. built from a `NightRecord`, so the evaluator never touches SwiftData.
- `AutoSensitivityState: Codable, Equatable`: `step: Int`, `maxStep: Int`, `phase: Phase` (`.settling`, `.settled`), `since: Date`, `questionAsked: Bool`.
- `AutoSensitivityAction`: `.none`, `.stepUp`, `.ask`, `.settle`.

### constants (stir.md decisions 63–65, 68)

| name | value |
|---|---|
| `ladder` | `[0.15, 0.325, 0.5, 0.675, 0.85, 1.0]` |
| `startStep` | `2` |
| `okLow`, `tooLow` | `1.05`, `0.35` detections per hour |
| `okHigh`, `tooHigh` | `18.0`, `54.0` detections per hour |
| `acceptProblem` | `ln(0.9 / 0.05)` = 2.8904 |
| `acceptOK` | `ln(0.1 / 0.95)` = −2.2513 |
| `settlingNightCap` | `60` |
| `settledThresholdTooSensitive` | `5.5` |
| `settledThresholdNotSensitive` | `4.5` |

### functions — each mirrors the function of the same name in the script

- `evidence(_ night: NightFacts) -> (detected: Bool, hours: Double)?` — decision 62. `nil` without `listeningStartedAt`. the end is `alarmFiredAt` for sound and motion, `upBy` for `upBy`, `endedAt` for `none`. hours never go below zero.
- `tooSensitive(_:)` and `notSensitive(_:)` — one night's contribution: `(detected ? ln(r1 / r0) : 0) − (r1 − r0) × hours`.
- `nearestStep(to value: Float) -> Int` — the nearest ladder index. two indices within 0.0001 of the same distance are a tie, and a tie goes to whichever index is closer to `startStep`.
- `starting(at value: Float, now: Date) -> AutoSensitivityState` — step `nearestStep(to: value)`, `maxStep` 5, `.settling`, `since` now, `questionAsked` false.
- `evaluate(_ state:, nights: [NightFacts], now: Date) -> (AutoSensitivityState, AutoSensitivityAction)` — the nights that count have `startedAt > state.since` and `abs(sensitivity − ladder[step]) < 0.001`, and give evidence. none counting → `.none`.
  - **settling:** the too-sensitive side is fine if `questionAsked`, and otherwise decided by a sequential test over the counting nights in order: the first time the running sum reaches `acceptProblem` it is a problem, and the first time it reaches `acceptOK` it is fine. the not-sensitive side is decided the same way, and counts as fine if it decides a problem while `step == maxStep`. then, in this order:
    1. too sensitive is a problem → `questionAsked = true`; if `step > 0`, return `.ask`; otherwise treat that side as fine and continue.
    2. not sensitive is a problem → step up: `step + 1`, `.settling`, `since = now`, `questionAsked = false` → `.stepUp`.
    3. both sides fine, or at least `settlingNightCap` nights counting → `.settled`, `since = now` → `.settle`.
    4. otherwise → `.none`.
  - **settled:** a CUSUM over the counting nights (`S = max(0, S + x)`), firing if `S` ever reaches the threshold.
    1. if not `questionAsked` and the too-sensitive side fires → `questionAsked = true`; if `step > 0`, return `.ask`.
    2. if `step < maxStep` and the not-sensitive side fires → step up as above → `.stepUp`.
    3. otherwise → `.none`.
- `answer(_ state:, yes: Bool, now: Date) -> AutoSensitivityState` — decision 67. no, or yes at step 0, returns the state unchanged. yes → `step − 1`, `maxStep = step − 1`, `.settling`, `since = now`, `questionAsked = false`.
- each call to `evaluate` logs one line to `Logger.session` (decision 72): step, phase, nights counted, each night's `(detected, hours)`, both sums, and the action.

### tests (unit) — expected values from `tools/auto-sensitivity-sim.py`

sums and boundaries:

- `acceptProblem` = 2.8904 and `acceptOK` = −2.2513, to four places.
- detection at 5 minutes: too-sensitive −1.9014, not-sensitive −1.0403. detection at 30 seconds: too-sensitive 0.7986. a silent 30-minute night: not-sensitive 0.35, too-sensitive −18.0.

evidence:

- motion at 12 minutes into listening → `(false, 0.2)`.
- `upBy` ends at `upBy`; `none` ends at `endedAt`; no `listeningStartedAt` → `nil`.
- a night at a different step, or started before `since`, does not count.

settling, from `starting(at: 0.5)`, one night at a time:

- silent 30-minute nights → `.none` for 8 nights, `.stepUp` on the 9th, to step 3.
- a detection 1 minute in each night → `.ask` on the 6th, with `questionAsked` true and the step unchanged.
- a detection 30 seconds in each night → `.ask` on the 4th.
- a detection 5 minutes in each night → `.settle` on the 3rd.
- at step 0, a detection 1 minute in each night → no `.ask`; `.settle` on the 6th.
- at step 5, silent 30-minute nights → no `.stepUp`; `.settle` on the 9th.
- three silent 30-minute nights and then a detection 5 minutes in, repeated → `.settle` on the 60th night, by the cap.
- after `.ask`, further detection nights never produce `.ask` again at that step.

settled:

- a detection 30 seconds in each night → `.ask` on the 7th.
- six such nights, one silent 30-minute night, then more → `.ask` on the 14th night, because the silent night resets the sum to zero.
- silent 30-minute nights → `.stepUp` on the 13th.

answers and the ladder:

- yes at step 3 → step 2, `maxStep` 2, settling. then nine silent 30-minute nights → `.settle`, not `.stepUp`.
- no → state unchanged. yes at step 0 → state unchanged.
- `nearestStep`: 0.15 → 0, 0.5 → 2, 0.85 → 4, 1.0 → 5, 0.3 → 1, 0.95 → 5. ties: 0.4125 → 2, 0.2375 → 1, 0.7625 → 3.

a seeded simulation, the last test in the file. a SplitMix64 generator in the test target, with nights drawn as in the script's `simulated_night` (nightly rate × e^N(−0.125, 0.5), first detection exponential, 30-minute windows), 1,000 people per case, settling at one step:

- 11 detections an hour → `.settle` in at least 97%
- 2.1 an hour → `.settle` in at least 97%
- 0.3 an hour → `.stepUp` in at least 92%
- 90 an hour → `.ask` in at least 95%

---

## phase 3 — auto in settings, and at the end of the night

### work

- `AlarmSettings` gains `sensitivityMode: SensitivityMode` (`.auto`, `.manual`) and `autoSensitivity: AutoSensitivityState?`.
  - decoding: `sensitivityMode` missing → `.manual`, and `autoSensitivity` missing → `nil`, so an existing install keeps its setting (decision 60).
  - `AlarmSettings.default`: `.auto`, `sensitivityValue` 0.5, `autoSensitivity = starting(at: 0.5, now:)`.
- `sensitivityLabel` becomes the nearest of low (0.15), medium (0.5) and high (0.85). a tie within 0.0001 goes to medium, so 0.325 and 0.675 read as medium.
- the sensitivity picker in `WakeSettingsView` is segmented: auto, low, medium, high.
  - choosing auto: `.auto`, `autoSensitivity = starting(at: current value)`, and `sensitivityValue = ladder[step]`.
  - choosing low, medium or high: `.manual`, `autoSensitivity = nil`, and the value 0.15, 0.5 or 0.85.
  - choosing auto while already on auto changes nothing.
- the note under the picker on auto names `sensitivityLabel` and says whether it is still settling. the owner writes the words.
- `AppState.recordSessionEnd`, after writing a clean run's `NightRecord` on auto: evaluate over every record in the store, oldest first, save the new state, and:
  - `.stepUp` → `settings.sensitivityValue = ladder[step]`, which the next night picks up in `MonitoringView.startSessionAsync`
  - `.ask` → `sensitivityQuestionPending = true` (not persisted; see phase 4)
- the technical details screen shows auto's state: the step's value, settling or settled, and how many nights count. the owner writes the words.

### tests

- unit: a settings blob saved by 1.0.1 decodes as `.manual` with its value unchanged. a fresh install is `.auto` at 0.5.
- unit: switching from high to auto starts at step 4; from auto back to medium clears the state.
- unit: a clean run on auto that reaches `.stepUp` changes `sensitivityValue` for the next night, and a night already running keeps the value it started with.
- unit: an unclean night on auto evaluates nothing. a night on manual evaluates nothing.
- UI: the picker shows four choices, and auto shows its note.

---

## phase 4 — the question

### work

- `AppState.dismissAlarm` records the night as it does now. if `sensitivityQuestionPending`, the screen stays `.alarm` with `askingSensitivity` set; otherwise it goes to `.setup` as it does now.
- the state saved in phase 3 already has `questionAsked` set before the question is shown. leaving the app with the question open is therefore a no (decision 67), and nothing about the question needs persisting.
- `AlarmView`: once stopped, the alarm, haptics, Live Activity and backstop stop exactly as they do now. if `askingSensitivity`, the stop button gives way to "was that too sensitive?" with yes and no.
- either answer calls `AppState.answerSensitivityQuestion(yes:)`: it applies `answer`, sets `sensitivityValue = ladder[step]` on a yes, saves, logs, and goes to `.setup`.
- a DEBUG launch override, `-askSensitivity`, opens the alarm screen with the question pending, for the UI test.

### tests

- unit: yes at step 2 gives step 1, `maxStep` 1, and `sensitivityValue` 0.325. no leaves state and value unchanged.
- unit: `.ask` is only ever returned while the night being recorded was set off by sound. across the seeded simulation's nights, every `.ask` follows a `sound` night.
- UI: with `-askSensitivity`, stopping the alarm shows the question, and tapping no lands on setup. without it, stopping lands on setup directly.

---

## phase 5 — fourteen nights

**device check, before release.** the owner sleeps on auto for at least fourteen nights on a build from `main`. each morning the unified log line for that night's evaluation is recomputed by hand from the night evidence it lists, using decision 64's formula. the check passes when:

- every logged action matches the recomputation
- no night was lost: every clean run appears in the log with its evidence
- any step or question that happened is one the owner agrees with

a step or question the owner judges wrong stops the release and goes back to the spec.

---

## release — 1.1

- marketing version 1.1.0, build 6.
- release notes in the owner's words.
- the App Store privacy label is unchanged (stir.md decision 40). the privacy policy, `PRIVACY.md` and the site gain one sentence, in the owner's words: stir keeps a short record of each night on the phone, and uses it to tune sensitivity.
- the App Review notes are unchanged: 1.1 adds no permission and no capability.

---

## effort

held loosely, since estimates here have run high. phase 0: about an hour. phase 1: about two hours. phase 2: two to three hours, mostly the tests. phase 3: two hours. phase 4: an hour. then fourteen nights.

---

## 1.2, as planned

kept as written on 15 september, before auto sensitivity became the 1.1 build. each becomes its own phase in a 1.2 build spec, which re-reads the decisions they cite first.

### reading the record

pure functions over `[NightRecord]`, with no UI.

**`NightSummary`**, over the most recent 14 records — nights, not days (decision 34):

- **lights out** and **up:** the median, and the range from the 10th to the 90th percentile, rounded to 5 minutes. with 14 nights that sets aside the single earliest and latest night (decision 36).
- **what set off the alarm:** a count by `triggeredBy`, and for sound and motion, how many minutes after `windowStart` it happened.
- **alarm ring:** `endedAt − alarmFiredAt`, on `alarmDismissed` nights.
- **up before stir:** `stopped` inside the window, before any alarm.
- **too few nights:** under 3 records, no sentences at all, only the list.

**the two traps:** lights out is measured in minutes from noon, so 10:40pm and 12:20am are 100 minutes apart; up is measured from midnight. summaries read the stored local minutes and never convert `startedAt` using today's time zone.

**tests:** one per rule; 10:40pm and 12:20am summarize as 100 minutes apart; a night on each side of a daylight-saving change keeps its local times; 14 records spread across 30 days summarize as 14 consecutive nights; one 2am start among thirteen near 10:45pm leaves the range unmoved; a no-alarm night counts toward lights out and up, and not toward what set off the alarm.

### the history screen

- settings gains a `history` row, above technical details (decision 38).
- the summary as sentences, then recent nights as a plain list, newest first: date, lights out, up, and how the night ended, in words.
- an empty state that says there are no nights yet, and nothing that suggests there should be more.
- `clear history` at the foot, confirmed once, removes every record (decision 39). on auto, clearing also starts auto over (decision 69), since its evidence is gone.
- **tests (UI):** history opens from settings; it appears on no other screen; clearing leaves the empty state.

### Health

- **before it starts:** App Review guideline 5.1.3 read in full, and a Health sentence written for the privacy policy, `PRIVACY.md` and the site.
- the HealthKit capability and entitlement, and `NSHealthUpdateUsageDescription`, lowercase.
- a `health` toggle in settings, off by default. turning it on asks to write sleep analysis and asks to read nothing (decision 47).
- one `inBed` sample per clean run, from `startedAt` to `endedAt` (decisions 46, 48, 49).
- access denied or revoked: the toggle turns itself off and says so.
- **tests (unit, against a protocol standing in for `HKHealthStore`):** one sample per kept night; nothing with the toggle off or for an unclean night; no read authorization ever requested. **device check:** a real night appears in Health as in bed, and as nothing else.

### Siri

- `StartNightIntent`, opening the app, and an `AppShortcutsProvider` with `start \(.applicationName)` and `start \(.applicationName) at a new time`, which asks for the time (decisions 50, 51).
- it starts the night through the same path in `AppState` as the setup screen's button.
- Siri reads the time back (decision 53), and below 30% media volume says so and asks whether to start anyway (decision 55).
- not onboarded: open onboarding and start nothing (decision 56).
- a night already running: before its window, move "up by" and say so; inside it, say the night is already running and change nothing.
- **tests:** the intent's start path matches the button's; not onboarded starts nothing; a running night inside its window is unchanged; Xcode's App Shortcuts preview recognizes both phrases. **device check:** both phrases from a locked phone, including one deliberately misheard time.

---

## after 1.2

- **suggestions** (stir.md part five): a build spec once history has run for a month, so the thresholds in decisions 42 and 43 come from real nights.
- **sounds:** a new part of `stir.md` first — which sounds, what each is for, and where each comes from, including gentle chime and soft bells — and then a build.
