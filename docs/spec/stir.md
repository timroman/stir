# stir

**status:** proposed, 15 september 2026. parts one through three describe stir 1.0.1 as it shipped. parts four through nine propose new work, and none of it is built. part nine, auto sensitivity, is the 1.1 build; history, suggestions, Health and Siri follow it.
**supersedes:** [`combined-app-spec.md`](../combined-app-spec.md), approved 28 july 2026, which specified merging white noise into the alarm. it stays as the record of that decision.

---

## why stir exists

stir replaced a subscription. for years the owner paid for a sleep app to get one feature — it listened for him stirring and woke him gently — and then built that feature himself, alongside white noise that fades to silence before morning.

what makes stir look the way it does is a second reason, in the owner's words from the [site](https://timroman.github.io/stir/):

> seeing the time at night stresses me out. wake at 2 am and the clock says *you're in the middle of the night*; wake at 5 and it says *you didn't sleep long enough*; wake at 6:40 and it says *it's almost over*. none of that information helps — it just costs you the rest of the night.

so the night screen withholds a number the phone could show trivially. that is a judgment about information, and it runs against the direction most software is moving in, where the answer to any question is to measure more of it.

this spec now proposes showing some of what stir records. that is exactly where a feature like this goes wrong, and the owner described how:

> my Apple Watch began to feel like the fitness metrics were more of a reflection of how frequently i wore my watch rather than what i was doing when my watch was on, because it had no intelligent way to account for the fact that a day reading zero meant i didn't wear my watch, instead of thinking it meant it was a day where i literally did nothing. so then you get in this weird situation where the stats aren't very accurate and the reminders are reminding you for the wrong things.

> it doesn't matter if all the metrics came back poorly — if i feel good in the morning, i wanna take on the day in a positive manner, rather than feeling good, seeing shitty stats, and then being worried about it all day.

the failure has a name in the clinical literature. [Baron and colleagues](https://jcsm.aasm.org/doi/10.5664/jcsm.6472) called it orthosomnia in 2017, describing patients for whom sleep tracker data became "a perfectionistic quest for the ideal sleep in order to optimize daytime function."

the wider concern is the owner's too:

> if there's one thing that scares me as a technologist right now, it's to think that we could use pure logic and reasoning and infinite data to solve this chaos theory problem, or end up like the prime radiant — but lose complete sight of our humanity and what makes us happy, even if sometimes strategic ambiguity means burying our heads in the sand.

and the conclusion he draws from it, which is also the argument of [taste is the new skill](https://pureinference.com/posts/gBiTnpHm/taste-is-the-new-skill): when building is no longer the hard part, "our taste needs to guide what can be done and whether it should be done." every feature below is easy to build. the principles in part one are the part that is not, and most of them say what stir will not do.

---

## part one — the principles

these govern every surface stir has and every feature proposed here. a feature that fails one is not built, however easy it is.

**1. the night shows nothing to calculate with.**
no clock, no countdown, no status bar, no progress. the night screen carries the real sun and moon. anyone who reads the sun can tell roughly what time it is — that is accepted, because it cannot be read to the minute and it answers only if you ask it.

**2. honesty with the data stir has.**
stir counts clean runs — nights that ran the way a night is designed to (decision 31) — and nothing else. a night without stir — travel, a different alarm, forgetting — is not recorded, not averaged, and not held against anything. there are no streaks and nothing is gamified. a streak is a count of absences, and the owner on the rest:

> streaks are "device use" shaming, which frankly we should all be trying to minimize. it's counterproductive. streaks and gamification are actually terrible for our health — especially when they're about our health, they masquerade as intelligence when they're really product adoption.

**3. describe, never judge.**
"most nights you started between 10:30 and 11:05", never "poor consistency". no scores, no grades, no red or green, no good or bad.

**4. nothing arrives unasked.**
no notification, reminder, widget or summary, and nothing on the setup screen, the night screen, the alarm screen or the lock screen. history is opened when somebody wants it. the morning belongs to how you feel. there is one exception, and only on auto sensitivity: a single question after the alarm, asked when stir cannot tell on its own (decision 67).

**5. no projections.**
stir never predicts how today will go, how rested you are, or what a night meant.

**6. record only what stir did.**
stir knows when a night started, when and why it woke you, and how the night ended. it does not know when you fell asleep, how well you slept, or what it heard, and it never claims to.

**7. nothing that changes how you are woken happens without your say.**
stir can suggest a change. only you apply one. an alarm has to be predictable, and a quiet change that ends in an oversleep leaves no way to find out why.

choosing auto sensitivity is saying so, for that one setting (part nine). on its own, auto only ever makes stir more sensitive, which cannot cause an oversleep — "up by" still holds. it becomes less sensitive only when you answer yes. settings always shows where it is, and it touches nothing else.

**8. everything stays on the phone.**
no accounts, no analytics, no servers. data leaves the phone only where you send it, and only facts go (part six).

---

## part two — the product as shipped

### the night

```
                                         window start = up by − wake window
start ────────────────────────────────────► window start ─────────► up by
  │  white noise                   │ fade │ quiet gap │ listening │ alarm
                                   ▲      ▲           ▲
                          fade begins     fade ends   calibrate for 30s,
                                                      then listen for sound
                                                      and motion
```

**9. one nightly input: the time you need to be up by.**
everything else is set once in settings and counted back from it: a wake window of 10–90 minutes, a quiet gap of 0–120, a fade of 5–60, all in 5-minute steps. two presets cover most people: gentle (fade 10, gap 30, window 30) and quick (5, 5, 15). *(28 july, 2 august)*

**10. white noise always plays when it is enabled.**
including on a night started inside the fade or the gap. it fades in over 3 seconds after a half-second pause for the audio route to settle, and a late start gets at least 2 minutes of fade. calibration waits until the white noise has stopped, so the room is never measured over stir's own sound. *(2 august)*

**11. no-alarm mode.**
with the alarm off, the fade ends exactly at "up by" and the silence is the wake. the microphone is never activated. a night needs white noise or the alarm, so turning white noise off locks the alarm on. *(28 july)*

### listening

**12. stirring is signal processing, not a model.**
when the window opens, stir measures the room for 30 seconds and sets a threshold at the baseline plus a multiple of its variation — the multiple is `5.0 − 3.0 × sensitivity`, and the variation has a 3 dB floor so a very still room cannot make it hair-trigger. sound must stay above the threshold for 3 consecutive readings. motion wakes you if the phone rotates more than 0.15 radians, about 8.5°, sampled at 10 Hz.

**13. the microphone is evaluated only inside the wake window.**
the audio session runs all night because that is what keeps stir alive in the background, but nothing is measured before the window opens and no audio is ever stored.

**14. "up by" is a promise.**
if nothing stirs you, the alarm sounds at "up by". on iOS 26 and later, an AlarmKit system alarm is scheduled 2 minutes after it, and it fires through Silent mode, Focus and a closed app. ending the night or stopping the alarm cancels it. *(28 july)*

### the screens

**15. the night screen is black, with the real sun and moon on their daily rings.**
positions come from on-device astronomy — the low-precision series suncalc uses, accurate to about 1° — and a coarse location, cached so the sky still draws offline. the share of each ring above the horizon line is the share of the day that body is up. *(28–30 july)*

**16. the status bar and home indicator are hidden on the night screen.**
the status bar clock was the last time signal left on a screen designed to have none. *(18 august)*

**17. the night ends with a hold.**
hold for 1.2 seconds on a 120×60 pt target; a hairline fills as you hold. taps do nothing, so a brushed phone keeps its night and its backstop. a finished no-alarm night ends on a tap, because it has nothing left to lose. *(8 september; see part three)*

**18. the display stays on through the night only if the night has seen a charger.**
a phone left unplugged lets its display sleep. the alarm screen always keeps the display on. *(18 and 21 august)*

**19. the alarm rises from silence to your volume over 60 seconds, and the screen's dawn rises with it.**
volume maps straight from the slider; the gentleness is the ramp, not a ceiling. haptics ramp over the same minute. *(2 and 18 august)*

**20. a low phone volume is caught before the night starts.**
below 30%, stir says so and lets you start anyway. media volume is the one setting stir can read but cannot set. *(18 august)*

**21. sound previews play at the volume the sound will use**, through the same kind of audio session the night uses. *(18 august)*

### sounds

**22. the night sounds are synthesized. two of the wake tones are not.**
white, pink and brown noise, fan, wind and ocean waves, from `tools/synthesize-sounds.py`. two of the four wake tones, singing bowl and dawn, come from the same script. imported audio works in either slot. rain was generated and cut for not passing the ear test. *(30 july, 2 august)*

gentle chime and soft bells do not. they arrived in the first commit of the app stir grew out of, in december 2025, when the sounds folder held a placeholder note telling its author to add royalty-free sounds from freesound.org, Pixabay or Mixkit. which one they came from, and under what licence, was never recorded, and the files carry no author or title of their own. the folder's own note claimed every sound was synthesized until 16 september 2026, which was never true of these two *(see open 9)*.

**23. the night sounds loop gaplessly.**
each file is built so its end joins its start sample for sample, with an equal-power seam, and it plays on the player's own repeat. *(21 august)*

**24. the night sounds are high-passed at 45 Hz before they are normalized**, so their level is set by what a phone speaker can actually play. *(8 september)*

### the record

**25. diagnostics go to the unified log**, under `com.pureinference.stir`, at levels written to disk, with values unredacted. a night can be reconstructed the next morning with `log collect` and no debugger attached. *(21 august)*

**26. each night writes a record of how it ended** — when it started, "up by", when the alarm fired, when it ended, and whether it ended by hand or by stopping the alarm — shown on the technical details screen. only the most recent night is kept. *(21 august)*

### the edges

**27. every permission is asked for up front, in onboarding**, each with what it is for, so no prompt interrupts a night. the button reads "continue"; the system alert is the only place the decision is made. the microphone is required; location and the backup alarm are optional. *(30 july, 18 august)*

**28. the audio background mode is the app.**
white noise plays all night with stir in the background and the screen off, and the listening session and the alarm run from the background too. App Review questioned the declaration on 18 august 2026; build 4 was approved after a screen recording of a backgrounded night. *(18–23 august)*

**29. iPhone only.** iPad was never designed or tested for. *(30 july)*

**30. free, open source, and lowercase.** no accounts, no analytics, no advertising. the rule is that every word stir shows is lowercase, except the names of things that belong to somebody else. three error messages still break it (open 9).

---

## part three — what broke

the decisions above were not the first attempt at most of them. these are the ones that looked right and were not, and what it cost to find out.

**the night screen used to tell the time.**
on 28 july the moon travelled an arc as "now" and the sun crested into the wake window. by the end of the same day every time correlate was gone. on 2 august a sky gradient that warmed toward morning went too, because a color that changes with the hour is a clock.

**the alarm was capped at 5% of its volume.**
a code comment justified it — "AVAudioPlayer is very loud" — against the wrong reference. with both sliders at 0.7, the white noise you fell asleep to was about 17 times louder than the alarm meant to wake you. the preview played at a fixed 0.6, so the one control for judging loudness showed neither sound. withdrawn 18 august.

**the loops dipped at the seam, twice.**
the generator joined each file's end to its start with a linear crossfade. uncorrelated noise adds as power rather than amplitude, so halfway through the blend the level falls to 0.707 — a 3 dB hole in the first 2 seconds of every file. the player then crossfaded again at runtime, landing on the same hole, and together they measured −4.85 dB. both seams became equal-power, and the runtime crossfade was removed, because a file that joins by construction needs none. withdrawn 21 august.

**the night screen went dark an hour in.**
the display was held on only while the battery reported it was charging. Optimized Battery Charging pauses at 80%, and a paused charger stops reporting it. on 20 august the battery reached 80% at 23:41, the power source flipped at 23:49:03, and the display went off 21 seconds later. the check now latches for the night. the next night the display stayed on from 22:21 until 07:13, a minute after the night ended. withdrawn 21 august.

**`print` left nothing behind.**
it writes to standard error, which only an attached debugger sees, so the first overnight failure had no evidence from stir at all — it was reconstructed from the power daemon's log. 93 calls moved to the unified log. withdrawn 21 august.

**a brushed phone ended the night.**
stop was a single tap, and ending the night also cancelled the backstop. the first fix, on 22 august, required a second tap within 5 seconds — chosen over a confirmation sheet, which would have lit a dark room. then a user on an iPhone 15 reported that the stop button did not work. UI tests reproduced two causes: the target measured 30×33 pt, under Apple's 44 pt minimum, so a tap aimed in the dark could miss with no feedback at all; and taps more than 5 seconds apart re-armed indefinitely — three taps at 6-second intervals never ended the night. it had worked for everyone who tapped quickly. replaced by a hold on 8 september.

**brown noise, fan and wind were silent on a phone.**
the beds are built as 1/f spectra over a 302-second window, so the frequency bins nearest zero got gains in the hundreds, and peak normalization scaled each file by sub-bass that no phone speaker can play. above 500 Hz, brown noise measured −66.1 dB, wind −68.9 and fan −60.7, against white noise's −19.1. high-passing before normalizing brought them to −28.2, −31.3 and −34.2. fan also needed its 58 Hz motor hum turned down from 0.06 to 0.012: once the sub-bass was gone, the hum set the peak instead. reported by users after launch; fixed 8 september.

**the haptics buzzed after the alarm was stopped.**
the haptic engine shares the app's audio session — an earlier version gave it its own, which silenced the alarm on device (29 july). stopping the alarm deactivated the session, which stopped the engine, whose restart handler found it still meant to be running and played one more pattern about a second later. haptics now stop first. withdrawn 22 august.

**App Review could not find the background audio.**
the reviewer notes walked through a short session and never said to leave the app. stir 1.0.0 (3) was rejected on 18 august for the background mode and for an onboarding button that read "allow". the notes now make backgrounding its own labelled step, and they record the approval.

**the screenshot upload duplicated every image.**
fastlane verifies a screenshot upload before App Store Connect has finished indexing it, decides it failed, deletes only the incomplete screenshots and uploads all of them again. four screenshots arrived as eight. the release lane no longer touches screenshots.

---

## part four — history

a way to see how consistent your nights are, and nothing else.

consistency rather than duration is the choice principles 3 and 5 already force, and it is also where the research points. in 60,997 UK Biobank participants, [sleep regularity predicted all-cause mortality better than sleep duration](https://academic.oup.com/sleep/article/47/1/zsad253/7280269) (Windred et al., *SLEEP*, 2024). that study measured sleep and wake from actigraphy; stir measures when a night starts and ends, which is coarser, and history says so rather than borrowing the study's claims.

**31. history keeps one record per clean run.**
a clean run is a night that reached its end the way stir is designed to end one:

- the alarm sounded and was stopped, whatever set it off
- a no-alarm night reached silence
- it was ended by hand inside its wake window, before the alarm — you were up before stir

and that started at least three hours before "up by", so that it is a night rather than a test or a nap *(open 10)*. a late bedtime is a clean run: leaving late nights out would make consistency look better than it is, which is the opposite of honest.

the record extends the one in decision 26 with four fields:

- **what set off the alarm:** sound, motion, the "up by" time, or nothing (ended by hand, or a no-alarm night)
- **the phone's media volume when the alarm started**
- **when listening started:** when the room calibration finished, which is later than the window opening whenever white noise was still fading (decision 62)
- **the sensitivity used that night:** the setting, not anything measured (decision 71)

**32. the line is drawn at the record, not in a policy.**
a record holds what stir did. no sound levels, no motion samples, no calibration values, no location, no inferred sleep. each of those is individually defensible — auto sensitivity would like to have the sound levels — and together they are a sleep tracker. a feature that needs one of them is a different feature and gets its own decision. the sensitivity used is a setting and when listening started is something stir did, so both sit inside the line.

**33. a record is written when a clean run ends, and only then.**
a night that did not run cleanly is not written to history at all, rather than stored and filtered out. a night stir never finished, because the app was killed or crashed, leaves nothing either *(see open 1)*. the most recent night, clean or not, still shows on the technical details screen, and the unified log keeps every night for diagnosis.

**34. the unit is clean runs, not days.**
every figure reads "across your last 14 nights", counting only clean runs, even when 14 of them span three weeks. there is no calendar, and a gap is never drawn as a gap.

**35. what history shows, and nothing more:**

- **lights out:** when your nights started, as the time most of them began and how widely they varied
- **up:** when your nights ended, in the same form
- **what set off the alarm:** how many nights it was sound, motion, or the "up by" time, and for sound and motion how early in the window. stir cannot tell whose sound or movement it was, so history says what set the alarm off and never who (decision 57)
- **how long the alarm rang** before you stopped it

written as sentences — "most nights you started between 10:30 and 11:05" — above a plain list of recent nights.

**36. one late night does not rewrite the week.**
the typical time and its spread come from the middle of your nights, not the extremes, so a single 2am start reads as one night rather than as your pattern.

**37. a night ended by hand before its wake window is not a clean run.**
it does not appear in history. a night ended by hand inside the window, before the alarm, is a clean run, and the list says you were up before stir.

**38. history is in settings, and nowhere else.**
never the setup screen, the night screen, the alarm screen, the lock screen, the Live Activity, or a notification.

**39. history can be cleared**, all of it, from the same screen, and it is gone. no archive, no undo.

**40. history lives in stir's own storage on the phone**, and is included in the phone's backup the way the settings are. the App Store privacy label does not change: Apple defines collecting as transmitting data off the device, and ["data that is processed only on device is not 'collected'"](https://developer.apple.com/app-store/app-privacy-details/). the privacy policy gains one sentence saying history exists and stays on the phone.

---

## part five — suggestions

settings are hard to tune by feel, and history can see what feel cannot. stir cannot, however, see why. sensitivity is not among the suggestions: auto sensitivity tunes it (part nine).

**41. stir suggests; you apply.**
a suggestion says what stir saw, what it would change, and changes nothing until you tap. dismissed, it does not return for 14 nights. suggestions appear only inside history.

**42. a suggestion is offered only when the change is safe whatever caused what stir saw.**
stir cannot tell you stirring from a dog. so it never proposes a change that is right for one explanation and harmful for another.

- **a longer wake window**, when sound or motion set off the alarm on few of your last 14 nights. whether the window was too short, the sensitivity too low, or nothing stirred, a longer window gives stir more chances and moves "up by" nowhere.
- **turning the phone's volume up**, when media volume was under 30% on most of your last 10 alarms. on 22 august 2026 the owner's alarm started at 25%.
- **nothing about sensitivity.** on auto, stir tunes it with evidence a suggestion would not have (part nine). set by hand, it is yours.

*(corrected 15 september: this decision said a false wake at 5am was worse than a gentle one at 6:45. stir listens only inside the wake window, so a false trigger can wake you at most one window's length early.)*

**43. no suggestion before 14 nights.** before that, a suggestion is reacting to a week.

**44. an applied change starts with the next night**, never the one running.

**45. no question at the alarm, but one.**
asking "did someone else set it off?" as the alarm is stopped puts a question at the one moment principle 4 keeps clear. it also asks the person who was asleep to explain what happened while they were, so the answer would be a guess, stored as a fact. *(see open 11)*

the one question stir asks is auto sensitivity's "was that too sensitive?" (decision 67). it asks the person woken how being woken felt, which they do know. it is asked only when the evidence cannot decide on its own, and the answer is acted on, not stored.

---

## part six — health

**46. stir can write the time a night lasted to Health**, as sleep analysis samples marked *in bed*, from the start of the night to its end. it is off by default and turned on in settings, which is where the permission is asked — never in onboarding.

**47. write only.** stir asks to write to Health and never to read from it. nothing comes back into stir.

**48. only facts go.**
*in bed*, never *asleep*, because stir cannot know when you fell asleep. nothing derived. once data is in Health, Apple's own features decide what to do with it, which is exactly why stir sends nothing it inferred.

**49. Health gets the clean runs history keeps**, and nothing else.

---

## part seven — siri

**50. "hey siri, start stir" starts the night with your saved "up by" time.** one phrase, no follow-up. most nights share a wake time, so this is the one that gets used.

**51. "hey siri, start stir at a new time" asks when you need to be up by, then starts the night.**
a time cannot be spoken inside the phrase. App Shortcut phrases accept only a closed set of values, and Apple's DTS engineer has confirmed that capturing an arbitrary spoken value has ["no way to do this in the invocation phase"](https://developer.apple.com/forums/thread/759909). neither WWDC26 session on the subject changes that: [App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/) adds no domain for alarms or time, and [the advanced App Intents session](https://developer.apple.com/videos/play/wwdc2026/343/) does not touch phrase parameters.

**52. no list of times standing in for a time.**
the only way to put a time inside a phrase is a closed list of times. it would push against Siri's limits on phrase variants, match spoken numbers poorly, and fail for 7:40.

**53. Siri reads the time back before the night starts.** "seven thirteen" and "seven thirty" are one mishearing apart, and the mistake would surface at 7:13.

**54. Siri opens stir.**
iOS does not let an app start the microphone from the background, and a night opens its audio session the moment it starts. on a locked phone that means Face ID. at bedtime that is fine; it is not a dark-screen voice command.

**55. the low-volume check is spoken.** a Siri start skips the setup screen and its alert, so Siri says the volume is low and asks whether to start anyway.

**56. a phone that has not finished onboarding opens onboarding**, not a night.

---

## part eight — shared rooms

a partner getting up or a child at the door sets stir off the same way you would. when a friend asked about it, the owner's answer was part of the story: at least one of you woke up naturally.

**57. stir hears the room, not a person.**
it does not try to tell people apart. doing that would mean learning voices or breathing, which needs a model and stored audio, and stir has neither (decisions 12 and 13). so the alarm is gentle whoever sets it off — it still rises from silence over a minute — and history names what set it off, never who.

**58. withdrawn the same day: low sensitivity was to ask sound to last about two seconds.**
the owner's objection was right. two seconds of sound is activity nobody sleeps through, so it would have filtered out the brief stirring — a roll, the covers — that stir exists to catch, along with the coughs and doors it was aimed at. how long a sound lasts cannot tell you from somebody else. low already makes the only honest trade there is: a higher threshold, which catches less and is set off less.

**59. the listening settings say what counts.**
the note under motion detection says anyone moving the phone sets it off, and that a phone on your side of the bed, on the nightstand, avoids most of it. distance does real work, because the threshold is set against the room's own baseline.

each sensitivity also says roughly what it is tuned for, in a note under the picker that changes with the choice. the axis is how much of the room's sound comes and goes, not how loud it is: steady sound — a fan, an air conditioner — is measured into the baseline during calibration, and what sets stir off by mistake is sound that arrives and leaves.

- **high** — alone, in a quiet or steady room. the threshold sits about 7 dB above the baseline, near enough to hear a person roll over or move the covers. on 22 august 2026 the owner's room calibrated at −53.2 dB, high set the threshold at −45.8, and stir woke him at −42.7, rolling over.
- **medium** — some sound that comes and goes: occasional traffic, a partner who sleeps still. about 10.5 dB above the baseline.
- **low** — a lot of it: a shared bed, pets, children nearby. about 14 dB above the baseline.
- **auto** — for not knowing yet. stir finds the setting over the first nights, and the note says which of the three it is closest to (part nine).

those figures hold in the stillest room stir can calibrate, where the variation is at its 3 dB floor; a room that varies more gets a proportionally higher threshold at every setting. the descriptions are rough, and so far only high has a real night behind it.

---

## part nine — auto sensitivity

sensitivity is the one setting nobody can tune by feel, because you are asleep for the part that matters. set too low, stir leaves you to "up by" every morning without saying so. set too high, it is set off by the room, which at 6:40 feels exactly like a gentle wake. auto sensitivity finds the setting from the nights themselves: it settles, then goes silent.

this part is the 1.1 build. its numbers were derived rather than chosen, and the working is in `tools/auto-sensitivity-sim.py`, which runs every rule below as written.

**60. auto is a choice, and the default for new installs.**
the sensitivity picker becomes auto, low, medium and high. a new install starts on auto, at medium. an existing install keeps the setting it has: choosing auto is the say principle 7 asks for, and an update is not somebody choosing. picking low, medium or high turns auto off.

**61. auto reads how often stir hears something, not where in the window.**
the owner's first model was the right intuition. a well-set stir wakes you at scattered moments across the window, and wakes piling up at the start or at "up by" mean the setting is wrong. counted literally, though, it misfires.

when stirring comes at a steady rate, the first moment stir hears it is not scattered evenly. it bunches toward the start, and by how much depends on the window. someone moving at the median rate sets stir off in the first minute on 17% of nights. an older sleeper at 2.1 shifts an hour reaches "up by" through a 30-minute window on 35% of nights with detection working perfectly, and through a 10-minute window on 70%. so any count of "too many at an edge" is wrong for some window length, and the window is the user's to choose (decision 9).

the measure that holds for any window, including one that changes every night, is a rate: detections divided by the hours stir spent listening. the edges still move it — early wakes raise the rate, "up by" lowers it — but weighed by how long stir listened.

**62. one night's evidence.**
a night gives evidence only if it is a clean run (decision 31), at the step auto is on, since auto last started over (decision 69). listening time begins at `listeningStartedAt`, when the room calibration finished — not when the window opened, because calibration waits for white noise to fade (decision 10) and then takes 30 seconds. listening time ends:

- **set off by sound:** at the alarm, with one detection
- **set off by motion:** at the alarm, with no detection. motion says nothing about how sound is set, but the minutes before it still count.
- **"up by":** at "up by", with no detection
- **ended by hand inside the window, before the alarm:** when it ended, with no detection

a night whose listening never began gives no evidence.

**63. the bounds come from how people move in their sleep.**

- **the floor is 1.05 detections an hour.** position shifts decline with age, down to 2.1 an hour at ages 65–80 (De Koninck et al., 1992). a whole-body shift is the stirring a phone on a nightstand can hear, so stir detecting less than half of what the stillest group does means stir is missing the sleeper.
- **the ceiling is 18 an hour.** healthy adults make a median of 11 movements an hour, flat across the night — 10, 10 and 11 by thirds — and the normal range in the last third tops out at 18 (Montini et al., 2024). stir detecting more than that is hearing something besides the sleeper.
- **a problem is three times past a bound.** 0.35 an hour or less is not sensitive enough; 54 an hour or more is too sensitive. the gap between each bound and its problem rate is what keeps a sleeper near a bound from being moved back and forth.

**64. settling: two sequential tests, one per side.**
this is what the owner called calibration. it is named settling here because calibration already names the 30 seconds at the start of each window.

each side is a sequential probability ratio test (Wald, 1945), the standard way to decide between two rates with as few observations as possible. every night adds to both sides:

`evidence = (detected ? ln(r1 ÷ r0) : 0) − (r1 − r0) × hours listened`

here r0 is the bound and r1 is the problem rate, per hour: 18 and 54 on the too-sensitive side, 1.05 and 0.35 on the not-sensitive side. a side decides the first time its running sum reaches `ln(0.9 ÷ 0.05)` = 2.8904, which means a problem, or `ln(0.1 ÷ 0.95)` = −2.2513, which means fine. those set a 5% chance of acting when nothing is wrong and a 10% chance of missing a real problem. a side that has decided stays decided until auto starts over.

- too sensitive decided → the question (decision 67)
- not sensitive decided → one step up (decision 66)
- both sides fine → settled (decision 68)
- 60 nights without both deciding → settled

simulated with 4,000 people per row, whose rate varies from night to night, on a 30-minute window:

| who | settles as | nights: median / 90% within |
|---|---|---|
| stir misses them, 0.3 an hour | steps up 96% | 13 / 27 |
| older adult, 2.1 an hour | settled 100% | 5 / 11 |
| young adult, 3.6 an hour | settled 100% | 4 / 6 |
| median mover, 11 an hour | settled 100% | 3 / 4 |
| top of normal, 18 an hour | settled 98% | 3 / 7 |
| restless, 25 an hour | settled 90%, asked 10% | 4 / 11 |
| noisy room, 54 an hour | asked 80% | 6 / 14 |
| noisy room, 90 an hour | asked 98% | 5 / 8 |

a window that changes every night between 10 and 90 minutes gives the same results to within a point.

**65. six steps, one at a time.**
auto moves along sensitivity values 0.15, 0.325, 0.5, 0.675, 0.85 and 1.0: low, medium and high as they are today, a step between each, and one above high. in the stillest room the steps are about 1.6 dB apart, so no single step jumps from missing you to hearing the room. the step above high is what "not sensitive enough at high" needs, and it stays inside the range the threshold formula was built for (decision 12): 2.0 times the variation, 6 dB in the stillest room.

auto starts at medium on a new install. when someone switches to it, it starts at the step nearest their current setting, and a tie goes toward medium. settings shows auto, with a note naming the nearest of low, medium and high.

**66. not sensitive enough: one step up, silently.**
nobody can answer "was stir sensitive enough?" about a night they slept through, and the evidence on this side is unambiguous: stir heard nothing. so stir steps up, from the next night (decision 44), and starts settling again at the new step. at the top step, or at the highest step a yes allows (decision 67), there is nowhere to go, and that side stays silent.

**67. too sensitive: one question.**
a noisy room and a restless sleeper look the same to stir, and only the person woken can tell them apart. so when this side decides, stir asks, on the alarm screen after the alarm is stopped: "was that too sensitive?" — yes or no, in the owner's words.

- **yes** steps down one, from the next night, and makes that step the highest auto will reach from then on. without that cap, a room where one step misses you and the next hears the room would step up, ask, step down and step up again indefinitely. in simulation the cap ends that pattern after one question.
- **no** changes nothing, and the question is not asked again at this step. restless is how some people sleep.
- **the question counts as asked the moment it is shown.** leaving it unanswered counts as no, and the same evidence never produces it twice.
- **at the lowest step it is not asked,** because a yes could change nothing.

the question can only follow a night stir was set off by sound, because evidence toward too sensitive grows only when stir detects something. so it always appears after an alarm, and never after a night ended by hand, a no-alarm night, or "up by".

**68. then silence.**
once settled, stir watches both sides with a CUSUM (Page, 1954), the standard test for a rate that has changed. it takes the same nightly evidence and keeps a running sum that never drops below zero. at 5.5 on the too-sensitive side it asks (decision 67); at 4.5 on the not-sensitive side it steps up. the question side has the higher threshold because a question interrupts a morning and a step does not.

with the window changing nightly between 10 and 90 minutes, a sleeper sitting exactly on the ceiling is asked for no reason about once every 1,577 nights, and one sitting exactly on the floor is stepped up for no reason about once every 307. a typical sleeper never is. a real change — a new fan, a new partner, a new season — is caught in a median of 15 nights on the question side and 18 on the other.

**69. starting over.**
auto starts settling again, with no evidence, after a step up, after a yes, and when someone switches to it. choosing low, medium or high ends auto. choosing auto again starts fresh at the nearest step, with every step open again. a change never applies to the night that is running (decision 44).

**70. auto touches sensitivity and nothing else.**
not the volume, the wake window, "up by", motion detection or white noise. each of those is a choice about the morning, not something a rate can measure.

**71. auto keeps its working state in settings, and reads the record.**
its state is the step, the highest step allowed, whether it is settling or settled, when that began, and whether the question has been asked at this step. that state is not history; it is how a setting is set. the evidence is recomputed from the night records each time a clean run ends, so there are no stored sums to drift. the record gains two fields for it (decision 31): when listening started, and the sensitivity used. the answer to the question is acted on and not recorded.

**72. every evaluation goes to the unified log** (decision 25): the step, the phase, how many nights counted, each night's evidence, both sides' sums, and what auto did. any morning's decision can be checked with `log collect` and recomputed by hand.

**73. the reference is in the repository.**
`tools/auto-sensitivity-sim.py` implements these decisions with these constants. the evaluator's unit tests take their expected values from it, and a change to a constant changes the spec, the script and the code in the same commit.

**74. what auto cannot know.**

- the bounds count movements seen on video and in muscle activity, not movements heard by a phone, and a phone hears only some of them. the floor is the number most exposed. a sleeper whose movements stir mostly cannot hear gets stepped up, which is the right direction, and ends at the top step.
- the people behind the ceiling slept without blankets so they could be filmed, while stir mostly hears covers.
- both studies are small: ten people per age group in one, fifty people for one night each in the other.
- a restless sleeper above the normal range is asked once about 10% of the time, and answers no.
- stir cannot learn how its bounds do across users, because nothing leaves the phone (principle 8). the check is the owner's nights, and anyone who reads their own log.

---

## part ten — what this does not build

- no sleep score, readiness measure, or prediction of the day
- no streaks, goals, badges, points, or counts of nights missed — nothing gamified
- no notifications, reminders or widgets for history
- no charts of hours slept
- no reading from Health, and nothing written to it as *asleep*
- no automatic changes to settings, except sensitivity on auto — and never the volume, the wake window or "up by"
- no morning check-in or rating. auto sensitivity's one question is about the alarm, and is asked only when the evidence cannot decide
- no stored audio, sound levels, motion data or location history
- no telling whose voice, breathing or movement stir heard
- no accounts, cloud sync, or export other than Health
- no Apple Watch app
- no alternative night faces or planets on the sky — raised in august, and parked: a sky that holds two bodies is the design, and a third ring is the start of a chart

---

## part eleven — open

**1. nights stir never finished.** writing the record when a night starts would let history show an interrupted night, which would help diagnose an overnight failure — and it would turn a missing night into a visible one, against principle 2. probably: the unified log keeps it, history does not.

**2. the thresholds in 42 and 43** — 14 nights, "few", "most" — are proposals, not measurements. they want a month of real history before they are set.

**3. whether history ever charts.** a plain list of nights describes; a dot per night on a time axis might show consistency at a glance, or might become the thing that gets checked.

**4. a Siri start during a running night.** update "up by" if the wake window has not opened, and otherwise say the night is already running — or refuse either way.

**5. the Live Activity.** all night it shows "up by 7:30 am", a status and a sound-level meter on the lock screen. that is the time you chose rather than the time now, and the lock screen shows a clock regardless — but it is the one stir surface that shows anything during the night, and principle 4 has not been held against it.

**6. resolved:** Health gets only clean runs (decision 49), and a night ended before its wake window is not one.

**7. the rules before part six is built.** App Review has requirements for health data (section 5.1.3 of the guidelines) that need reading, and the privacy policy needs a Health sentence. `PRIVACY.md` is already out of date: dated december 2025, it predates location and the backstop, and it does not match the privacy section on the site.

**8. storage.** SwiftData is the platform's path; a file in stir's container is smaller. history is one small record a night, so either holds a lifetime. the choice is about how the record migrates when it gains a field, not about size.

**9. the provenance of two wake tones.** *(the other two corrections here shipped in 1.1: the `NightArcFace.swift` comment and the technical details screen no longer claim nothing tells the time, and the three sound import errors are lowercase.)*

gentle chime and soft bells cannot be shown to be licensed (decision 22). that matters twice over: the repository is MIT, and the binary ships them. the options are to replace both with generated tones, which `tools/synthesize-sounds.py` can build the way it builds singing bowl and dawn, to establish the licence of the files as they are, or to drop them. the first also answers "we need more sounds anyway", and is the only one that makes the folder's claim true rather than narrower. which sounds ship is the owner's ear, so this is a product decision before it is a build.

**10. resolved: the shortest night that counts is three hours**, from start to "up by" (decision 31). a session started a few minutes before "up by" — a test, a nap — is not a night, and a late bedtime is. check it against real history once there is some.

**11. marking a night someone else set off.** a question at the alarm is out (decision 45), but the need behind it is real: history should be able to know when it was not you. the version that keeps the morning clear is a mark on the night in history, made whenever you look — "someone else set this off" — after a partner mentions getting up at 6:30. a marked night stays a clean run, and drops out of what set off the alarm and out of suggestions. stir never guesses the mark.

---

## effort

held loosely. auto sensitivity, with the record it reads, the evaluator and its tests: about a day, then fourteen nights on the owner's phone before release. history, including the screen and tests: about half a day. suggestions: a few hours. Health: a few hours, after the review reading in open 7. Siri: a couple of hours and a test on a device. the privacy policy, `PRIVACY.md` and the store copy change alongside parts four and six.

---

## sources

- Tim Roman, [taste is the new skill](https://pureinference.com/posts/gBiTnpHm/taste-is-the-new-skill), Pure Inference, 2026
- Baron KG, Abbott S, Jao N, Manalo N, Mullen R. [orthosomnia: are some patients taking the quantified self too far?](https://jcsm.aasm.org/doi/10.5664/jcsm.6472) *Journal of Clinical Sleep Medicine* 13(2):351–354, 2017
- Windred DP et al. [sleep regularity is a stronger predictor of mortality risk than sleep duration](https://academic.oup.com/sleep/article/47/1/zsad253/7280269). *SLEEP* 47(1), 2024
- De Koninck J, Lorrain D, Gagnon P. [sleep positions and position shifts in five age groups: an ontogenetic picture](https://pubmed.ncbi.nlm.nih.gov/1579788/). *Sleep* 15(2):143–149, 1992. read from the abstract; the full text was not accessible. ten people per age group, filmed a frame every 8 seconds, so brief shifts may be undercounted.
- Montini A, Loddo G, Zenesini C, Mainieri G, Baldelli L, Mignani F, Mondini S, Provini F. [physiological movements during sleep in healthy adults across all ages](https://doi.org/10.1093/sleep/zsae138). *SLEEP* 47(9), 2024. fifty adults aged 20–70, one video-polysomnography night each, sleeping without blankets; movements found by muscle activity and video, not sound.
- Wald A. sequential tests of statistical hypotheses. *Annals of Mathematical Statistics* 16(2):117–186, 1945
- Page ES. continuous inspection schemes. *Biometrika* 41(1/2):100–115, 1954
- Apple, [app privacy details on the App Store](https://developer.apple.com/app-store/app-privacy-details/)
- Apple Developer Forums, [Siri not recognizing the parameter in the phrase](https://developer.apple.com/forums/thread/759909)
- Apple, WWDC26: [build intelligent Siri experiences with App Schemas](https://developer.apple.com/videos/play/wwdc2026/240/) and [explore advanced App Intents features for Siri and Apple Intelligence](https://developer.apple.com/videos/play/wwdc2026/343/)
