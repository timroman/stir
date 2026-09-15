# stir 1.1 — build

**status:** proposed, 15 september 2026. builds parts four, six and seven of [`stir.md`](stir.md), and the corrections in its open 9. suggestions (part five) are 1.2, with their own build spec once there is a month of real history to set their thresholds. new sounds come after 1.1 and start as a product decision, not a build.

**decisions this assumes.** the owner said build on 15 september with the recommended defaults — confirm on review:

- history has no charts in 1.1: sentences and a plain list (stir.md open 3)
- a night stir never finished stays out of history; the unified log keeps it (open 1)
- a Siri start during a running night moves "up by" if the wake window has not opened, and otherwise says the night is already running and changes nothing (open 4)
- history is stored with SwiftData (open 8)

**set by the owner, 15 september:** history counts clean runs only (stir.md principle 2, decisions 31, 33, 37). the shortest night that counts is still open (stir.md open 10); phase 1 holds it as a single named constant until it is decided.

---

## how the work runs

stir had no build process written down. this is the one it has been using, recorded so it stays the same.

- one branch and one pull request per phase, off `main`. nothing goes to `main` directly.
- tests are the gate. a phase merges with its unit and UI tests green on an iPhone 15 simulator, and after any device check the phase names.
- one decision per commit: `scope: decision — reason`.
- the owner merges, and the owner submits to App Review.
- a phase that finds the spec wrong stops and says so. the spec changes before the code does.

---

## phase 0 — test target and corrections

**work**

- a unit test target, `stir-tests`, beside `stir-uitests` in `project.yml` and in the `stir` scheme's test action. stir has only UI tests today, and phases 1, 2, 4 and 5 are mostly logic.
- the three `CustomSoundError` messages in `CustomSoundManager.swift`, lowercased.
- the comment in `NightArcFace.swift` corrected: the sun's position is solar time. the technical details copy corrected to match stir.md principle 1 — the owner's words to approve.
- `PRIVACY.md` brought in line with the privacy section on the site, and lowercased.

**done when** `stir-tests` runs in `xcodebuild test`, and no user-facing string in `stir/` or `stir-widgets/` is capitalized apart from proper nouns.

---

## phase 1 — the night record

the record is what history, Health and 1.2's suggestions all read, and what users will have months of. it is settled before anything reads it.

### schema

`NightRecord`, a SwiftData model. these fields and no others:

| field | type | why |
|---|---|---|
| `startedAt` | `Date` | lights out |
| `endedAt` | `Date` | up |
| `upBy` | `Date` | the promise that night |
| `windowStart` | `Date?` | the wake window as it was that night; `nil` on a no-alarm night. stored because settings change, and stir.md decision 37 needs the window that applied |
| `alarmFiredAt` | `Date?` | |
| `wokeBy` | `WakeReason` | `sound`, `motion`, `upBy`, `none` |
| `ending` | `NightEnding` | `stopped`, `alarmDismissed`, `completed` |
| `alarmVolume` | `Float?` | media volume when the alarm started (decision 31) |
| `startedLocalMinute` | `Int` | minutes after local midnight when the night started |
| `endedLocalMinute` | `Int` | minutes after local midnight when it ended |

the two local-minute fields let a night read in the time it happened, where it happened, without storing a time zone. a time zone is a coarse record of where somebody was, and decision 32 keeps location out of the record.

a field added later is a decision in `stir.md` first.

### a bug this fixes

when a finished no-alarm night is dismissed, `MonitoringView.endNight()` calls `stopMonitoring()`, which records `stopped` — the same as a night ended by hand. history would count every no-alarm night as ended early. `completed` exists for this.

### work

- `triggerAlarm` carries its reason from the three places that call it: the sound monitor, the motion monitor, and the "up by" fallback in `MonitoringView.tick()`.
- `AlarmPlayer` hands back the media volume it already reads when the alarm starts.
- `AppState.recordSessionEnd` keeps writing the single `lastSessionRecord`, which the technical details screen shows for every night, clean or not. alongside it, and only for a clean run (decisions 31, 33), it writes a `NightRecord`.
- whether a night is a clean run is decided in one function, so history, Health and 1.2's suggestions share one definition.
- no migration. history starts empty in 1.1; the night in `lastSessionRecord` is diagnostics, not history.

### tests (unit)

- each wake reason reaches the record.
- a finished no-alarm night records `completed`, with `windowStart` `nil`.
- a night that never ends writes nothing.
- a night ended by hand before its wake window writes no `NightRecord`, and still updates `lastSessionRecord`.
- a night ended by hand inside its window, before the alarm, is a clean run.
- a night started less than the minimum before "up by" writes no `NightRecord`; a late bedtime above it is a clean run.
- a test fails if `NightRecord` gains a stored field not in the table above, so the line in decision 32 is enforced by the build, not remembered.

---

## phase 2 — reading the record

pure functions over `[NightRecord]`, with no UI, so every judgment stir makes about the numbers is under test.

### `NightSummary`

over the most recent 14 records — nights, not days (decision 34):

- **lights out** and **up**: the median, and the range from the 10th to the 90th percentile, rounded to 5 minutes. with 14 nights that range sets aside the single earliest and latest night, which is what "most nights" means and what keeps one late night from rewriting the week (decision 36).
- **how you woke**: a count by `wokeBy`, and for sound and motion, how many minutes after `windowStart` it happened.
- **alarm ring**: `endedAt − alarmFiredAt`, on `alarmDismissed` nights.
- **up before stir**: `stopped` inside the window before any alarm, which the list says in those words.
- **too few nights**: under 3 records, no sentences at all — only the list. a spread of two nights describes nothing.

### the two traps

- **midnight.** lights out at 10:40pm and at 12:20am are 100 minutes apart, not 22 hours. lights out is measured in minutes from noon, so the evening and the small hours are one continuous range. up is measured from midnight.
- **daylight saving and travel.** summaries read the stored local minutes. they never convert `startedAt` using today's time zone.

### tests (unit)

one per rule above, and:

- 10:40pm and 12:20am summarize as 100 minutes apart.
- a night on each side of a daylight-saving change keeps its local times.
- 14 records spread across 30 days summarize as 14 consecutive nights.
- one 2am start among thirteen near 10:45pm leaves the range unmoved.
- a no-alarm night counts toward lights out and up, and not toward how you woke.

---

## phase 3 — the history screen

### work

- settings gains a `history` row, above technical details (decision 38).
- the screen: the summary as sentences, then recent nights as a plain list, newest first. each row gives the date, lights out, up, and how the night ended, in words.
- an empty state that says there are no nights yet, and nothing that suggests there should be more.
- `clear history` at the foot, confirmed once, removes every record (decision 39).
- the copy is the owner's to approve before merge. decision 35's sentences are the starting point.

### tests (UI)

- history opens from settings.
- history appears on no other screen: setup, night, or alarm.
- clearing leaves the empty state.

---

## phase 4 — Health

**before this phase starts:** App Review guideline 5.1.3, "health and health research", read in full; and a Health sentence written for the privacy policy, `PRIVACY.md` and the site.

### work

- the HealthKit capability and entitlement in `project.yml`, and `NSHealthUpdateUsageDescription`, lowercase.
- a `health` toggle in settings, off by default. turning it on asks to write sleep analysis and asks to read nothing (decision 47).
- for every clean run history keeps, one `inBed` sample from `startedAt` to `endedAt` (decisions 46, 48, 49).
- access denied or later revoked: the toggle turns itself off and says so. no retry, and no prompt outside settings.

### tests (unit, against a protocol standing in for `HKHealthStore`)

- one `inBed` sample per kept night, with the right interval.
- nothing written with the toggle off, or for a night that is not a clean run.
- no read authorization is ever requested.

**device check:** a real night appears in Health as in bed, and as nothing else.

---

## phase 5 — Siri

### work

- `StartNightIntent`, opening the app when run, and an `AppShortcutsProvider` with two phrases: `start \(.applicationName)` and `start \(.applicationName) at a new time`. the second asks for the time (decisions 50, 51).
- the intent starts the night through the same path in `AppState` as the setup screen's button — not a copy of it.
- before starting, Siri says the time it will use (decision 53), and below 30% media volume says so and asks whether to start anyway (decision 55).
- not finished onboarding: open onboarding, start nothing (decision 56).
- a night already running: before its wake window, move "up by" and say so; inside it, say the night is already running and change nothing.

### tests

- unit: the intent's start path sets "up by" and starts a night exactly as the button does; not onboarded starts nothing; a running night inside its window is unchanged.
- Xcode's App Shortcuts preview recognizes both phrases.
- **device check:** both phrases from a locked phone, including one deliberately misheard time, which the read-back has to expose.

---

## release — 1.1

- marketing version 1.1.0, build 6.
- release notes in the owner's words.
- the App Store privacy label is unchanged (stir.md decision 40). the privacy policy changes, for history and for Health.
- the App Review notes gain one line for Health: what is written, and that nothing is read.

---

## effort

held loosely; estimates here have run high. phase 0: an hour. phase 1: about two hours, mostly the clean-run tests. phase 2: two to three hours, mostly the tests. phase 3: two hours. phase 4: two hours, after the guideline. phase 5: two hours and a session on a device. about a day and a half.

---

## after 1.1

- **1.2, suggestions.** a build spec once history has run for a month, so the thresholds in stir.md decisions 42 and 43 come from real nights.
- **sounds.** a new part of `stir.md` first — which sounds, what each is for, and where each comes from, including gentle chime and soft bells — and then a build.
