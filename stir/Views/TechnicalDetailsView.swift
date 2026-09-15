import SwiftUI

// How the app actually works, for the curious. Reachable from settings and
// from onboarding.
struct TechnicalDetailsView: View {
    var body: some View {
        List {
            // Only appears once a night has actually run; the answer to "what
            // happened last night?" without needing a Mac attached
            if let last = SessionRecord.last {
                Section {
                    LabeledContent("started", value: last.startedText)
                    LabeledContent("alarm", value: last.alarmText)
                    LabeledContent("ended", value: last.endedText)
                    LabeledContent("how", value: last.ending.label)
                } header: {
                    Text("last night")
                } footer: {
                    Text("the session ran \(last.lengthText).")
                }
            }

            Section {
                Text("set the one time that matters — when you need to be up by. white noise plays while you fall asleep and through the night, then fades to silence. after a quiet gap, stir starts listening. when it hears or feels you naturally stirring inside your wake window, it wakes you gently. if the window closes without a stir, the alarm sounds at your \"up by\" time no matter what.")
            } header: {
                Text("one session, all night")
            }

            Section {
                Text("when your wake window opens, stir samples the room for 30 seconds to learn its baseline sound level and how much it naturally varies. the wake trigger is set a few standard deviations above that baseline — tuned by your sensitivity setting — so a furnace hum or distant traffic never fires it, but the rustle of you turning over does. the sound must stay above the trigger for several readings in a row before the alarm starts. if motion detection is on, picking up or bumping the phone wakes you too.")
            } header: {
                Text("how listening works")
            }

            Section {
                Text("the night screen stays black all night — no clock, no countdown, nothing that glows brighter as morning comes. the only things on screen are the real sun and moon on their rings. anyone who reads the sun can tell roughly what time it is, but never to the minute, and only if you go looking.")
            } header: {
                Text("the night screen")
            }

            Section {
                Text("the two rings are the real sun and moon. each ring is that body's complete daily lap around you — the part above the horizon line is sky, the dimmed part below is its path under the earth. the share of a ring above the line is exactly the share of the day that body spends up: the sun's ring rides high in summer and low in winter, one slow sweep per year. the moon's ring makes that same sweep every 27 days, and the full moon always rides opposite the sun — low in summer, high in winter.\n\nthe bodies sit at their true positions, computed on your device from your approximate location. when the moon touches the horizon line here, it is rising or setting outside your window. nothing on the night screen represents the clock — only the sky and the heavens.")
            } header: {
                Text("the rings")
            }

            Section {
                Text("on iOS 26 and later, starting a session also schedules a system backup alarm two minutes after your \"up by\" time. it fires through silent mode, focus, and even if the app is closed overnight — and it's cancelled the moment you stop the session or dismiss the alarm yourself.")
            } header: {
                Text("the backstop")
            }

            Section {
                Text("everything happens on your device. the microphone is only evaluated during your wake window, and nothing is ever recorded or sent anywhere. in no-alarm mode the microphone is never activated at all. your approximate location is used only to place the sun and moon, and it never leaves your phone.")
            } header: {
                Text("privacy")
            }
        }
        .navigationTitle("technical details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        TechnicalDetailsView()
    }
}
