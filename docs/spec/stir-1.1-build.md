# stir 1.1 — build

**status:** built, 29 september 2026. what 1.1 actually became is below. it started as auto sensitivity (stir.md part nine) with the night record underneath; auto was built, tested, put on TestFlight, and withdrawn before release — the record, the sounds and the fixes are what ship.

## what 1.1 ships

- **sounds that are ours.** ten generated wake tones and six sleep beds, every one built by `tools/synthesize-sounds.py` (stir.md decision 22). gentle chime and soft bells replaced two mp3s of unknown origin that had shipped since december 2025 while the folder claimed everything was synthesized; deep bowl, temple bells, wind chimes, music box, marimba and first light are new.
- **no importing your own sounds** (decision 75). the file picker, the stored copy and its error paths are gone; anyone who had an imported sound selected falls back to the named tone they chose before it.
- **the night record** (decision 31), invisible in 1.1: one row per clean run, which history and Health read in 1.2. records have to start accumulating before history can show anything.
- **a low battery warning** before a night starts, and the volume check narrowed to nights nothing will play (decisions 20, 76).
- **the sensitivity notes** under the picker, saying what each setting is tuned for (decision 59).
- **corrections:** lowercase sound import errors, the night screen no longer claiming nothing tells the time, `PRIVACY.md` matching the site, and the privacy policy saying stir keeps a record of each night on the phone.

## what 1.1 fixed after it reached TestFlight

each of these was found on a real phone, and each lived in glue no test reached:

- **build 7 crashed every clean night.** the night store kept only its database context, and a context does not keep its container alive, so the first save — stopping the alarm — trapped on a nil container. every test built the store the safe way. the store now holds its own container, and a test builds it exactly the way the app does.
- **the lock screen widget outlived the night.** ending a night ended only the activity held in memory, which a crash or a relaunch loses. stir now ends every activity ActivityKit reports, at launch, before a night starts, and when one ends.
- **the backup alarm outlived the night.** cancelling is asynchronous and stir could die mid-cancel, so a system alarm fired for a night already over. the night's end is now recorded synchronously, before the cancel is attempted, and the next launch finishes the job — while a backstop whose night never ended is left to fire, which is the whole point of it.

## how the work runs

- one branch per phase, and one pull request for the release, off `main`. nothing goes to `main` directly.
- tests are the gate, on an iPhone simulator: `xcodebuild build-for-testing`, then `xcodebuild test-without-building`, against a booted simulator (`xcrun simctl bootstatus <udid> -b`). shut the simulator down afterwards — a UI test can leave the app running, and the alarm loops for ever.
- **two unsolved flakes, both in the test runner rather than in stir.** the unit test host intermittently hangs before a single test runs, logging "test daemon not ready" while the run fails as "the test runner hung before establishing connection". separately, a UI test can die mid-test with "Restarting after unexpected exit, crash, or test timeout" and no crash report for the app and no failed assertion. neither has ever coincided with a real failure; both pass on a rerun. rerun once, and if it repeats, boot a different simulator. the tell for a genuine failure is an assertion line — `<file>.swift:<line>: error:` — or a crash report naming stir's own frames.
- one decision per commit: `scope: decision — reason`.
- the owner merges, and the owner submits to App Review.
- a phase that finds the spec wrong stops and says so. the spec changes before the code does.
- research and the reasoning behind a decision are written into `docs/spec/`, next to the decision. a derivation that can be run lives in `tools/`.
- customer-facing copy is drafted in the pull request and is the owner's to approve before merge.

## what the tests cover, and what they do not

68 tests on an iPhone simulator: the night record and which nights count as clean runs, the start-of-night checks, the backstop's launch rule, that every sound in the picker resolves to a file, and the UI paths for stopping a night and reading the sensitivity notes.

they do not cover the detector itself — the 30-second calibration, the threshold, the three-consecutive-readings rule — which has no tests at all and is the layer between "sound in the room" and "a detection". that is the next thing worth building, and it needs no microphone: a sequence of decibel readings in, a trigger decision out. three of 1.1's bugs lived in glue the tests never reached.

## release — 1.1

- marketing version 1.1.0, build 12.
- release notes in the owner's words.
- the App Store privacy label is unchanged (stir.md decision 40). the privacy policy, `PRIVACY.md` and the site gained one sentence: stir keeps a short record of each night on the phone.
- the App Review notes are unchanged: 1.1 adds no permission and no capability.

## after 1.1

- **history** (stir.md part four): the summary and the screen, reading the records 1.1 has been keeping. with the record already shipped, this is the screen and its tests.
- **Health** (part six), after App Review guideline 5.1.3 is read in full.
- **Siri** (part seven).
- **suggestions** (part five), once history has run for a month so the thresholds in decisions 42 and 43 come from real nights.
- **the detector tests** described above.
