import XCTest
@testable import stir

// Every expected value here comes from tools/auto-sensitivity-sim.py, the
// reference implementation of stir.md part nine.
final class AutoSensitivityTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60
    private typealias A = AutoSensitivity

    /// Night n of a run: listening starts eight hours after the night does,
    /// and the night ends a minute after the alarm.
    private func night(_ n: Int, step: Int, detectedAfterMinutes: Double?, windowMinutes: Double = 30) -> NightFacts {
        let startedAt = base.addingTimeInterval(Double(n + 1) * day)
        let listening = startedAt.addingTimeInterval(8 * 60 * 60)
        let upBy = listening.addingTimeInterval(windowMinutes * 60)
        if let minutes = detectedAfterMinutes {
            let fired = listening.addingTimeInterval(minutes * 60)
            return NightFacts(startedAt: startedAt, upBy: upBy, endedAt: fired.addingTimeInterval(60),
                              listeningStartedAt: listening, alarmFiredAt: fired, triggeredBy: .sound,
                              sensitivity: A.ladder[step])
        }
        return NightFacts(startedAt: startedAt, upBy: upBy, endedAt: upBy.addingTimeInterval(60),
                          listeningStartedAt: listening, alarmFiredAt: upBy, triggeredBy: .upBy,
                          sensitivity: A.ladder[step])
    }

    /// Runs nights one at a time, evaluating after each, as the app does.
    /// Returns every action and the state after the first one that isn't none.
    private func run(from start: AutoSensitivityState, nights count: Int,
                     detectedAfterMinutes: (Int) -> Double?) -> (actions: [AutoSensitivityAction], state: AutoSensitivityState) {
        var state = start
        var history: [NightFacts] = []
        var actions: [AutoSensitivityAction] = []
        for n in 0..<count {
            let facts = night(n, step: state.step, detectedAfterMinutes: detectedAfterMinutes(n))
            history.append(facts)
            let (next, action) = A.evaluate(state, nights: history, now: facts.endedAt.addingTimeInterval(60))
            state = next
            actions.append(action)
            if action != .none { break }
        }
        return (actions, state)
    }

    private func settling(at step: Int = 2) -> AutoSensitivityState {
        A.starting(at: A.ladder[step], now: base)
    }

    private func settled(at step: Int = 2) -> AutoSensitivityState {
        var state = settling(at: step)
        state.phase = .settled
        return state
    }

    private func expect(_ actions: [AutoSensitivityAction], _ action: AutoSensitivityAction, onNight n: Int,
                        file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actions.count, n, "decided on night \(actions.count), expected \(n)", file: file, line: line)
        XCTAssertEqual(actions.last, action, file: file, line: line)
        XCTAssertTrue(actions.dropLast().allSatisfy { $0 == .none }, file: file, line: line)
    }

    // MARK: - sums and boundaries

    func testBoundaries() {
        XCTAssertEqual(A.acceptProblem, 2.8904, accuracy: 0.0001)
        XCTAssertEqual(A.acceptOK, -2.2513, accuracy: 0.0001)
    }

    func testOneNightsContribution() {
        XCTAssertEqual(A.tooSensitive((true, 5.0 / 60)), -1.9014, accuracy: 0.0001)
        XCTAssertEqual(A.notSensitive((true, 5.0 / 60)), -1.0403, accuracy: 0.0001)
        XCTAssertEqual(A.tooSensitive((true, 0.5 / 60)), 0.7986, accuracy: 0.0001)
        XCTAssertEqual(A.notSensitive((false, 0.5)), 0.35, accuracy: 0.0001)
        XCTAssertEqual(A.tooSensitive((false, 0.5)), -18.0, accuracy: 0.0001)
    }

    // MARK: - evidence (decision 62)

    private func facts(trigger: AlarmTrigger, listening: Date?, fired: Date?, upBy: Date, ended: Date) -> NightFacts {
        NightFacts(startedAt: base, upBy: upBy, endedAt: ended, listeningStartedAt: listening,
                   alarmFiredAt: fired, triggeredBy: trigger, sensitivity: 0.5)
    }

    func testMotionCountsTheMinutesButNoDetection() {
        let listening = base.addingTimeInterval(8 * 60 * 60)
        let evidence = A.evidence(facts(trigger: .motion, listening: listening, fired: listening.addingTimeInterval(12 * 60),
                                        upBy: listening.addingTimeInterval(30 * 60), ended: listening.addingTimeInterval(13 * 60)))
        XCTAssertEqual(evidence?.detected, false)
        XCTAssertEqual(evidence?.hours ?? -1, 0.2, accuracy: 1e-9)
    }

    func testUpByEndsAtUpByAndEndedByHandEndsWhenItEnded() {
        let listening = base.addingTimeInterval(8 * 60 * 60)
        let upBy = listening.addingTimeInterval(30 * 60)
        let fallback = A.evidence(facts(trigger: .upBy, listening: listening, fired: upBy, upBy: upBy,
                                        ended: upBy.addingTimeInterval(10 * 60)))
        XCTAssertEqual(fallback?.detected, false)
        XCTAssertEqual(fallback?.hours ?? -1, 0.5, accuracy: 1e-9)

        let byHand = A.evidence(facts(trigger: .none, listening: listening, fired: nil, upBy: upBy,
                                      ended: listening.addingTimeInterval(6 * 60)))
        XCTAssertEqual(byHand?.detected, false)
        XCTAssertEqual(byHand?.hours ?? -1, 0.1, accuracy: 1e-9)
    }

    func testSoundIsADetectionAtTheAlarm() {
        let listening = base.addingTimeInterval(8 * 60 * 60)
        let evidence = A.evidence(facts(trigger: .sound, listening: listening, fired: listening.addingTimeInterval(3 * 60),
                                        upBy: listening.addingTimeInterval(30 * 60), ended: listening.addingTimeInterval(4 * 60)))
        XCTAssertEqual(evidence?.detected, true)
        XCTAssertEqual(evidence?.hours ?? -1, 0.05, accuracy: 1e-9)
    }

    func testNoListeningIsNoEvidence() {
        XCTAssertNil(A.evidence(facts(trigger: .none, listening: nil, fired: nil, upBy: base, ended: base)))
    }

    func testNightsAtAnotherStepOrBeforeSinceDoNotCount() {
        let state = settling()
        let otherStep = night(0, step: 3, detectedAfterMinutes: nil)
        var early = night(1, step: 2, detectedAfterMinutes: nil)
        early.startedAt = base.addingTimeInterval(-day)
        let (next, action) = A.evaluate(state, nights: [otherStep, early], now: base.addingTimeInterval(3 * day))
        XCTAssertEqual(action, .none)
        XCTAssertEqual(next, state)
    }

    // MARK: - settling (decision 64)

    func testSilentNightsStepUpOnTheNinth() {
        let (actions, state) = run(from: settling(), nights: 20) { _ in nil }
        expect(actions, .stepUp, onNight: 9)
        XCTAssertEqual(state.step, 3)
        XCTAssertEqual(state.phase, .settling)
        XCTAssertFalse(state.questionAsked)
    }

    func testDetectionAMinuteInAsksOnTheSixth() {
        let (actions, state) = run(from: settling(), nights: 20) { _ in 1 }
        expect(actions, .ask, onNight: 6)
        XCTAssertTrue(state.questionAsked)
        XCTAssertEqual(state.step, 2)
    }

    func testDetectionThirtySecondsInAsksOnTheFourth() {
        let (actions, _) = run(from: settling(), nights: 20) { _ in 0.5 }
        expect(actions, .ask, onNight: 4)
    }

    func testDetectionFiveMinutesInSettlesOnTheThird() {
        let (actions, state) = run(from: settling(), nights: 20) { _ in 5 }
        expect(actions, .settle, onNight: 3)
        XCTAssertEqual(state.phase, .settled)
    }

    func testTheLowestStepNeverAsks() {
        let (actions, state) = run(from: settling(at: 0), nights: 20) { _ in 1 }
        expect(actions, .settle, onNight: 6)
        XCTAssertTrue(state.questionAsked)
    }

    func testTheTopStepNeverStepsUp() {
        let (actions, state) = run(from: settling(at: 5), nights: 20) { _ in nil }
        expect(actions, .settle, onNight: 9)
        XCTAssertEqual(state.step, 5)
    }

    func testSixtyUndecidedNightsSettle() {
        let (actions, _) = run(from: settling(), nights: 80) { n in n % 4 == 3 ? 5 : nil }
        expect(actions, .settle, onNight: 60)
    }

    func testTheQuestionIsNeverAskedTwiceAtAStep() {
        var state = settling()
        var history: [NightFacts] = []
        var actions: [AutoSensitivityAction] = []
        for n in 0..<40 {
            let facts = night(n, step: state.step, detectedAfterMinutes: 1)
            history.append(facts)
            let (next, action) = A.evaluate(state, nights: history, now: facts.endedAt.addingTimeInterval(60))
            state = next
            actions.append(action)
        }
        XCTAssertEqual(actions.filter { $0 == .ask }.count, 1, "\(actions)")
        XCTAssertEqual(actions.firstIndex(of: .ask), 5)
    }

    // MARK: - settled (decision 68)

    func testSettledAsksOnTheSeventhEarlyDetection() {
        let (actions, state) = run(from: settled(), nights: 20) { _ in 0.5 }
        expect(actions, .ask, onNight: 7)
        XCTAssertEqual(state.phase, .settled)
    }

    func testASilentNightResetsTheSettledSum() {
        let (actions, _) = run(from: settled(), nights: 20) { n in n == 6 ? nil : 0.5 }
        expect(actions, .ask, onNight: 14)
    }

    func testSettledStepsUpOnTheThirteenthSilentNight() {
        let (actions, state) = run(from: settled(), nights: 20) { _ in nil }
        expect(actions, .stepUp, onNight: 13)
        XCTAssertEqual(state.step, 3)
        XCTAssertEqual(state.phase, .settling)
    }

    // MARK: - answers and the ladder (decisions 65, 67)

    func testYesStepsDownAndCapsTheLadder() {
        var asked = settling(at: 3)
        asked.questionAsked = true
        let now = base.addingTimeInterval(day)
        let state = A.answer(asked, yes: true, now: now)
        XCTAssertEqual(state, AutoSensitivityState(step: 2, maxStep: 2, phase: .settling, since: now, questionAsked: false))

        let later = AutoSensitivityState(step: 2, maxStep: 2, phase: .settling, since: base, questionAsked: false)
        let (actions, _) = run(from: later, nights: 20) { _ in nil }
        expect(actions, .settle, onNight: 9)
    }

    func testNoChangesNothingAndYesAtTheLowestStepChangesNothing() {
        var asked = settling(at: 3)
        asked.questionAsked = true
        XCTAssertEqual(A.answer(asked, yes: false, now: base.addingTimeInterval(day)), asked)

        var lowest = settling(at: 0)
        lowest.questionAsked = true
        XCTAssertEqual(A.answer(lowest, yes: true, now: base.addingTimeInterval(day)), lowest)
    }

    func testNearestStep() {
        XCTAssertEqual(A.nearestStep(to: 0.15), 0)
        XCTAssertEqual(A.nearestStep(to: 0.5), 2)
        XCTAssertEqual(A.nearestStep(to: 0.85), 4)
        XCTAssertEqual(A.nearestStep(to: 1.0), 5)
        XCTAssertEqual(A.nearestStep(to: 0.3), 1)
        XCTAssertEqual(A.nearestStep(to: 0.95), 5)
        // ties go toward medium
        XCTAssertEqual(A.nearestStep(to: 0.4125), 2)
        XCTAssertEqual(A.nearestStep(to: 0.2375), 1)
        XCTAssertEqual(A.nearestStep(to: 0.7625), 3)
    }

    // MARK: - a seeded simulation (the script's operating characteristics)

    /// SplitMix64: small, fast, and the same sequence on every run
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func uniform() -> Double {
            Double(next() >> 11) / Double(1 << 53)
        }
        mutating func gaussian(mean: Double, sd: Double) -> Double {
            let u1 = max(uniform(), .leastNonzeroMagnitude)
            let u2 = uniform()
            return mean + sd * (-2 * Foundation.log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    /// As the script's simulated_night: the rate varies night to night, the
    /// first detection is exponential, and a 30-minute window falls back to up by.
    private func outcomes(rate: Double, people: Int, generator: inout SeededGenerator) -> [AutoSensitivityAction: Int] {
        var tally: [AutoSensitivityAction: Int] = [:]
        for _ in 0..<people {
            let (actions, _) = run(from: settling(), nights: A.settlingNightCap + 1) { _ in
                let nightly = rate * Foundation.exp(generator.gaussian(mean: -0.125, sd: 0.5))
                let hours = -Foundation.log(1 - generator.uniform()) / nightly
                return hours < 0.5 ? hours * 60 : nil
            }
            tally[actions.last ?? .none, default: 0] += 1
        }
        return tally
    }

    /// Evidence toward too sensitive grows only on a detection, so the question
    /// can only ever follow a night stir was set off by sound (decision 67)
    func testEveryAskFollowsANightSetOffBySound() {
        var generator = SeededGenerator(state: 67)
        var asks = 0
        for rate in [25.0, 54, 90] {
            for _ in 0..<300 {
                var state = settling()
                var history: [NightFacts] = []
                for n in 0..<120 {
                    let nightly = rate * Foundation.exp(generator.gaussian(mean: -0.125, sd: 0.5))
                    let hours = -Foundation.log(1 - generator.uniform()) / nightly
                    let windowHours = [10.0, 20, 30, 45, 60, 90][Int(generator.uniform() * 6)] / 60
                    let facts = night(n, step: state.step,
                                      detectedAfterMinutes: hours < windowHours ? hours * 60 : nil,
                                      windowMinutes: windowHours * 60)
                    history.append(facts)
                    let (next, action) = A.evaluate(state, nights: history, now: facts.endedAt.addingTimeInterval(60))
                    if action == .ask {
                        asks += 1
                        XCTAssertEqual(facts.triggeredBy, .sound, "asked after a night set off by \(facts.triggeredBy)")
                        state = A.answer(next, yes: generator.uniform() < 0.5, now: facts.endedAt.addingTimeInterval(120))
                    } else {
                        state = next
                    }
                }
            }
        }
        XCTAssertGreaterThan(asks, 100, "the simulation should ask often enough to test anything")
    }

    func testSimulatedSleepersSettleAsTheSpecSays() {
        var generator = SeededGenerator(state: 1815)
        let people = 1000

        let medianMover = outcomes(rate: 11, people: people, generator: &generator)
        XCTAssertGreaterThanOrEqual(medianMover[.settle, default: 0], 970, "11/hr: \(medianMover)")

        let olderAdult = outcomes(rate: 2.1, people: people, generator: &generator)
        XCTAssertGreaterThanOrEqual(olderAdult[.settle, default: 0], 970, "2.1/hr: \(olderAdult)")

        let missed = outcomes(rate: 0.3, people: people, generator: &generator)
        XCTAssertGreaterThanOrEqual(missed[.stepUp, default: 0], 920, "0.3/hr: \(missed)")

        let noisyRoom = outcomes(rate: 90, people: people, generator: &generator)
        XCTAssertGreaterThanOrEqual(noisyRoom[.ask, default: 0], 950, "90/hr: \(noisyRoom)")
    }
}
