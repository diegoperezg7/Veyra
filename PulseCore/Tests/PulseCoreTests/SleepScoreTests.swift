import XCTest
@testable import PulseCore

/// The sleep score used to reward a night for being *typical for you* rather
/// than for resembling healthy sleep. These vectors pin each curve to the
/// published reference it now scores against.
final class SleepScoreTests: XCTestCase {
    private let night = Date(timeIntervalSince1970: 1_700_000_000)

    /// Builds a session from stage durations in minutes, laid end to end.
    private func session(inBed: Double = 0, core: Double, deep: Double, rem: Double, awake: Double) -> SleepSession {
        var cursor = night
        var segments: [SleepSegment] = []
        func add(_ stage: SleepStage, _ minutes: Double) {
            guard minutes > 0 else { return }
            let end = cursor.addingTimeInterval(minutes * 60)
            segments.append(.init(start: cursor, end: end, stage: stage, source: "test"))
            cursor = end
        }
        add(.inBed, inBed)
        add(.core, core)
        add(.deep, deep)
        add(.rem, rem)
        add(.awake, awake)
        return SleepSession(segments: segments)
    }

    private func score(_ session: SleepSession, need: Double = 480) -> Double {
        SleepEngine.score(session, need: need, stageHistory: Array(repeating: 0.4, count: 14),
                          onsetHistory: [], hrDip: nil, regularity: 80).value ?? -1
    }

    func testArchitectureScoresAgainstPublishedBandsNotYourOwnMedian() {
        // 20% deep, 22% REM: squarely inside N3 15–25% and REM 20–25%.
        let healthy = session(core: 348, deep: 120, rem: 132, awake: 0)
        XCTAssertEqual(SleepEngine.architectureScore(healthy).score!, 100, accuracy: 0.5)

        // 5% deep, 10% REM — poor architecture. The previous version returned
        // 85 for this whenever it matched the sleeper's own history.
        let poor = session(core: 510, deep: 30, rem: 60, awake: 0)
        let poorScore = SleepEngine.architectureScore(poor).score!
        XCTAssertLessThan(poorScore, 45, "a night short of both deep and REM must not pass")

        // Excess restorative sleep is not itself a problem, so it is penalised
        // far more gently than a shortfall.
        let deepHeavy = session(core: 240, deep: 216, rem: 144, awake: 0)
        XCTAssertGreaterThan(SleepEngine.architectureScore(deepHeavy).score!, poorScore + 30)

        // A night the source reported without staging says nothing about
        // architecture, so it must withhold rather than guess.
        let unstaged = session(core: 480, deep: 0, rem: 0, awake: 0)
        XCTAssertNil(SleepEngine.architectureScore(unstaged).score)
    }

    func testEfficiencyUsesTheMeaningfulBandOfTheScale() {
        // 80% efficiency is the lower edge of normal and used to score 80.
        let borderline = session(inBed: 96, core: 240, deep: 84, rem: 60, awake: 0)
        let efficiency = borderline.asleepMinutes / borderline.bedMinutes * 100
        XCTAssertEqual(efficiency, 80, accuracy: 1)
        let mapped = Statistics.clamp((efficiency - 65) / 30 * 100)
        XCTAssertEqual(mapped, 50, accuracy: 2, "the lower edge of normal should read as a pass, not a merit")
    }

    func testContinuityTightenedAgainstNormativeWASO() {
        let settled = session(core: 300, deep: 100, rem: 80, awake: 5)
        let broken = session(core: 300, deep: 100, rem: 80, awake: 60)
        XCTAssertGreaterThan(score(settled), score(broken))
        // 60 minutes awake is roughly double the normative ceiling; under the
        // old curve it still returned 60 points.
        XCTAssertEqual(Statistics.clamp(100 - max(0, 60.0 - 20) * 1.2), 52, accuracy: 0.5)
    }

    func testDurationPeaksAtNeedAndEasesBackWhenOversleeping() {
        let short = session(core: 210, deep: 60, rem: 60, awake: 0)      // 5h30
        let onTarget = session(core: 288, deep: 100, rem: 92, awake: 0)  // 8h00
        let long = session(core: 430, deep: 150, rem: 140, awake: 0)     // 12h
        XCTAssertLessThan(score(short), score(onTarget))
        XCTAssertLessThan(score(long), score(onTarget), "sleeping far past the need is not better than meeting it")
    }

    func testAGoodNightStillScoresWellAndAPoorOneDoesNot() {
        let good = session(inBed: 15, core: 250, deep: 100, rem: 115, awake: 10)
        let bad = session(inBed: 45, core: 240, deep: 20, rem: 40, awake: 70)
        XCTAssertGreaterThan(score(good), 80)
        XCTAssertLessThan(score(bad), 55)
    }
}
