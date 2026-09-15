import Foundation
import os

// Auto sensitivity (stir.md part nine, decisions 60–74): settle, then silence.
//
// Pure functions over night records, so every judgment is under test. Each one
// mirrors the function of the same name in tools/auto-sensitivity-sim.py, and
// the tests take their expected values from that script. A constant changes in
// the spec, the script and here, in the same commit, or not at all.

/// The parts of a night record the evaluator reads — a value, so the evaluator
/// never touches SwiftData.
struct NightFacts: Equatable {
    var startedAt: Date
    var upBy: Date
    var endedAt: Date
    var listeningStartedAt: Date?
    var alarmFiredAt: Date?
    var triggeredBy: AlarmTrigger
    var sensitivity: Float
}

extension NightFacts {
    init(_ record: NightRecord) {
        self.init(startedAt: record.startedAt, upBy: record.upBy, endedAt: record.endedAt,
                  listeningStartedAt: record.listeningStartedAt, alarmFiredAt: record.alarmFiredAt,
                  triggeredBy: record.triggeredBy, sensitivity: record.sensitivity)
    }
}

/// How a setting is set, not history (decision 71). Kept in settings.
struct AutoSensitivityState: Codable, Equatable {
    enum Phase: String, Codable {
        case settling
        case settled
    }

    var step: Int
    /// The highest step auto may reach; lowered by a yes (decision 67)
    var maxStep: Int
    var phase: Phase
    /// Only nights started after this count
    var since: Date
    /// The question has been shown at this step, so it is not shown again
    var questionAsked: Bool
}

enum AutoSensitivityAction: String {
    case none
    case stepUp
    case ask
    case settle
}

enum AutoSensitivity {
    typealias Evidence = (detected: Bool, hours: Double)

    // MARK: - constants (decisions 63, 64, 65, 68)

    static let ladder: [Float] = [0.15, 0.325, 0.5, 0.675, 0.85, 1.0]
    static let startStep = 2

    /// Detections per hour of listening. The floor is half De Koninck's 2.1
    /// position shifts an hour at 65–80; a problem is three times past it.
    static let okLow = 1.05
    static let tooLow = 0.35
    /// The top of Montini's normal range in the last third of the night; a
    /// problem is three times past it.
    static let okHigh = 18.0
    static let tooHigh = 54.0

    /// Wald's boundaries for a 5% chance of acting when nothing is wrong and a
    /// 10% chance of missing a real problem
    static let acceptProblem: Double = Foundation.log(0.9 / 0.05)
    static let acceptOK: Double = Foundation.log(0.1 / 0.95)
    static let settlingNightCap = 60

    /// A question interrupts a morning and a step does not, so asking takes
    /// more evidence
    static let settledThresholdTooSensitive = 5.5
    static let settledThresholdNotSensitive = 4.5

    // MARK: - one night (decision 62)

    /// Whether stir detected sound, and how many hours it listened first. nil
    /// when listening never began.
    static func evidence(_ night: NightFacts) -> Evidence? {
        guard let listeningStartedAt = night.listeningStartedAt else { return nil }
        let end: Date
        let detected: Bool
        switch night.triggeredBy {
        case .sound:
            end = night.alarmFiredAt ?? night.endedAt
            detected = true
        case .motion:
            // Says nothing about how sound is set, but the minutes before it count
            end = night.alarmFiredAt ?? night.endedAt
            detected = false
        case .upBy:
            end = night.upBy
            detected = false
        case .none:
            // Ended by hand inside the window, before the alarm
            end = night.endedAt
            detected = false
        }
        return (detected, max(0, end.timeIntervalSince(listeningStartedAt) / 3600))
    }

    /// One night's contribution to the too-sensitive side (decision 64)
    static func tooSensitive(_ evidence: Evidence) -> Double {
        logLikelihoodRatio(evidence, problemRate: tooHigh, boundRate: okHigh)
    }

    /// One night's contribution to the not-sensitive side (decision 64)
    static func notSensitive(_ evidence: Evidence) -> Double {
        logLikelihoodRatio(evidence, problemRate: tooLow, boundRate: okLow)
    }

    private static func logLikelihoodRatio(_ evidence: Evidence, problemRate r1: Double, boundRate r0: Double) -> Double {
        let detection: Double = evidence.detected ? Foundation.log(r1 / r0) : 0
        return detection - (r1 - r0) * evidence.hours
    }

    // MARK: - the ladder (decision 65)

    /// The nearest step; a tie goes to whichever is closer to medium.
    static func nearestStep(to value: Float) -> Int {
        let distances = ladder.map { abs(Double($0) - Double(value)) }
        let nearest = distances.min() ?? 0
        let tied = ladder.indices.filter { distances[$0] - nearest < 0.0001 }
        return tied.min { abs($0 - startStep) < abs($1 - startStep) } ?? startStep
    }

    static func starting(at value: Float, now: Date) -> AutoSensitivityState {
        AutoSensitivityState(step: nearestStep(to: value), maxStep: ladder.count - 1,
                             phase: .settling, since: now, questionAsked: false)
    }

    // MARK: - the evaluator (decisions 64–69)

    /// The evidence from the nights that count: started after `since`, at the
    /// step auto is on, with listening that began (decision 62)
    static func countedEvidence(_ state: AutoSensitivityState, nights: [NightFacts]) -> [Evidence] {
        nights
            .filter { $0.startedAt > state.since && abs($0.sensitivity - ladder[state.step]) < 0.001 }
            .compactMap(evidence)
    }

    private enum Verdict {
        case problem
        case fine
    }

    /// Wald's sequential test: decided the first time the running sum reaches
    /// a boundary, and never again
    private static func sequentialTest(_ values: [Double]) -> Verdict? {
        var sum = 0.0
        for value in values {
            sum += value
            if sum >= acceptProblem { return .problem }
            if sum <= acceptOK { return .fine }
        }
        return nil
    }

    /// Page's CUSUM: a running sum that never drops below zero
    private static func cusumFires(_ values: [Double], threshold: Double) -> Bool {
        var sum = 0.0
        for value in values {
            sum = max(0, sum + value)
            if sum >= threshold { return true }
        }
        return false
    }

    /// Reads the nights that count and says what auto does. `nights` are clean
    /// runs, oldest first.
    static func evaluate(_ state: AutoSensitivityState, nights: [NightFacts],
                         now: Date) -> (AutoSensitivityState, AutoSensitivityAction) {
        let counted = countedEvidence(state, nights: nights)
        let result = decide(state, counted: counted, now: now)
        logEvaluation(state, counted: counted, result: result)
        return result
    }

    private static func decide(_ state: AutoSensitivityState, counted: [Evidence],
                               now: Date) -> (AutoSensitivityState, AutoSensitivityAction) {
        guard !counted.isEmpty else { return (state, .none) }
        var next = state

        switch state.phase {
        case .settling:
            var tooSensitiveVerdict = state.questionAsked ? .fine : sequentialTest(counted.map(tooSensitive))
            var notSensitiveVerdict = sequentialTest(counted.map(notSensitive))
            if notSensitiveVerdict == .problem && state.step >= state.maxStep {
                notSensitiveVerdict = .fine   // nowhere higher to go
            }
            if tooSensitiveVerdict == .problem {
                next.questionAsked = true
                if next.step > 0 { return (next, .ask) }
                tooSensitiveVerdict = .fine   // the lowest step: a yes could change nothing
            }
            if notSensitiveVerdict == .problem {
                return (steppedUp(next, now: now), .stepUp)
            }
            if (tooSensitiveVerdict == .fine && notSensitiveVerdict == .fine) || counted.count >= settlingNightCap {
                next.phase = .settled
                next.since = now
                return (next, .settle)
            }
            return (next, .none)

        case .settled:
            if !next.questionAsked && cusumFires(counted.map(tooSensitive), threshold: settledThresholdTooSensitive) {
                next.questionAsked = true
                if next.step > 0 { return (next, .ask) }
            }
            if next.step < next.maxStep && cusumFires(counted.map(notSensitive), threshold: settledThresholdNotSensitive) {
                return (steppedUp(next, now: now), .stepUp)
            }
            return (next, .none)
        }
    }

    private static func steppedUp(_ state: AutoSensitivityState, now: Date) -> AutoSensitivityState {
        AutoSensitivityState(step: state.step + 1, maxStep: state.maxStep,
                             phase: .settling, since: now, questionAsked: false)
    }

    /// Decision 67: yes steps down one and makes that the highest step; no, or
    /// yes at the lowest step, changes nothing.
    static func answer(_ state: AutoSensitivityState, yes: Bool, now: Date) -> AutoSensitivityState {
        guard yes, state.step > 0 else { return state }
        return AutoSensitivityState(step: state.step - 1, maxStep: state.step - 1,
                                    phase: .settling, since: now, questionAsked: false)
    }

    // MARK: - the log (decision 72)

    private static func logEvaluation(_ state: AutoSensitivityState, counted: [Evidence],
                                      result: (AutoSensitivityState, AutoSensitivityAction)) {
        let nights = counted
            .map { evidence -> String in
                let kind = evidence.detected ? "sound" : "none"
                return "(\(kind) \(String(format: "%.4f", evidence.hours))h)"
            }
            .joined(separator: " ")
        let tooValues = counted.map(tooSensitive)
        let notValues = counted.map(notSensitive)
        let tooSum: Double
        let notSum: Double
        if state.phase == .settling {
            tooSum = tooValues.reduce(0, +)
            notSum = notValues.reduce(0, +)
        } else {
            tooSum = tooValues.reduce(0) { max(0, $0 + $1) }
            notSum = notValues.reduce(0) { max(0, $0 + $1) }
        }
        let before = "step \(state.step) (\(ladder[state.step])), max \(state.maxStep), \(state.phase.rawValue)"
        let sums = "too sensitive \(String(format: "%.4f", tooSum)), not sensitive \(String(format: "%.4f", notSum))"
        let after = "\(result.1.rawValue), step \(result.0.step)"
        Logger.session.notice("auto sensitivity: \(before, privacy: .public), \(counted.count, privacy: .public) nights \(nights, privacy: .public) — \(sums, privacy: .public) → \(after, privacy: .public)")
    }
}
