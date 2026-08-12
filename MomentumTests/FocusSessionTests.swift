import Foundation
import SwiftData
import Testing
@testable import Momentum

@Suite("DurationFormat")
struct DurationFormatTests {
    @Test func chronometerUnderOneHour() {
        #expect(DurationFormat.chronometer(65) == "01:05")
        #expect(DurationFormat.chronometer(0) == "00:00")
        #expect(DurationFormat.chronometer(3599) == "59:59")
    }

    @Test func chronometerOverOneHour() {
        #expect(DurationFormat.chronometer(3600) == "1:00:00")
        #expect(DurationFormat.chronometer(3661) == "1:01:01")
    }

    @Test func summaryFormatting() {
        #expect(DurationFormat.summary(12) == "12s")
        #expect(DurationFormat.summary(125) == "2m")
        #expect(DurationFormat.summary(3725) == "1h 02m")
    }
}

@Suite("SessionTotals")
@MainActor
struct SessionTotalsTests {
    @Test func overlappingFocusRespectsPause() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = FocusSession(
            startAt: start,
            endAt: start.addingTimeInterval(100),
            pausedDuration: 20,
            lastHeartbeatAt: start.addingTimeInterval(100)
        )
        let seconds = SessionTotals.overlappingFocusSeconds(
            session: session,
            rangeStart: start,
            rangeEnd: start.addingTimeInterval(100),
            now: start.addingTimeInterval(100)
        )
        #expect(abs(seconds - 80) < 0.001)
    }

    @Test func overlappingPartialRangeScales() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = FocusSession(
            startAt: start,
            endAt: start.addingTimeInterval(100),
            pausedDuration: 0,
            lastHeartbeatAt: start.addingTimeInterval(100)
        )
        let seconds = SessionTotals.overlappingFocusSeconds(
            session: session,
            rangeStart: start,
            rangeEnd: start.addingTimeInterval(50),
            now: start.addingTimeInterval(100)
        )
        #expect(abs(seconds - 50) < 0.001)
    }
}

@Suite("FocusSessionController")
@MainActor
struct FocusSessionControllerTests {
    private func makeController(clock: @escaping () -> Date = Date.init) throws -> (FocusSessionController, ModelContainer) {
        let schema = Schema([Project.self, FocusSession.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let controller = FocusSessionController(
            modelContext: context,
            idleMonitor: IdleMonitor(idleThreshold: 60),
            clock: clock
        )
        controller.isIdlePauseEnabled = false
        return (controller, container)
    }

    @Test func startStopPersistsDuration() throws {
        var now = Date(timeIntervalSince1970: 5_000)
        let (controller, _) = try makeController { now }
        let project = controller.createProject(name: "Alpha")
        controller.start(project: project)
        #expect(controller.phase == .running)
        now = now.addingTimeInterval(90)
        let finished = controller.stop(offerNotePrompt: false)
        #expect(finished != nil)
        #expect(controller.phase == .idle)
        #expect(abs((finished?.duration(at: now) ?? -1) - 90) < 0.01)
    }

    @Test func startWhileRunningStopsPrevious() throws {
        var now = Date(timeIntervalSince1970: 8_000)
        let (controller, _) = try makeController { now }
        let a = controller.createProject(name: "A")
        let b = controller.createProject(name: "B")
        controller.start(project: a)
        now = now.addingTimeInterval(30)
        controller.start(project: b)
        #expect(controller.activeProject?.name == "B")
        let sessionsA = controller.sessions(for: a)
        #expect(sessionsA.count == 1)
        #expect(sessionsA[0].endAt != nil)
        #expect(abs(sessionsA[0].duration(at: now) - 30) < 0.01)
    }

    @Test func stopWithoutSessionIsNoOp() throws {
        let (controller, _) = try makeController()
        #expect(controller.stop(offerNotePrompt: false) == nil)
        #expect(controller.phase == .idle)
    }

    @Test func recoverOpenSessionsOnInit() throws {
        let schema = Schema([Project.self, FocusSession.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let project = Project(name: "Recover")
        context.insert(project)
        let start = Date(timeIntervalSince1970: 9_000)
        let heartbeat = start.addingTimeInterval(40)
        let open = FocusSession(startAt: start, endAt: nil, lastHeartbeatAt: heartbeat, project: project)
        context.insert(open)
        try context.save()

        let controller = FocusSessionController(modelContext: context)
        #expect(controller.phase == .idle)
        let sessions = controller.sessions(for: project)
        #expect(sessions.count == 1)
        #expect(sessions[0].endAt == heartbeat)
        #expect(sessions[0].wasInterrupted == true)
    }

    @Test func idlePauseExcludesTime() throws {
        var now = Date(timeIntervalSince1970: 10_000)
        let schema = Schema([Project.self, FocusSession.self])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        let idle = IdleMonitor(idleThreshold: 1)
        let controller = FocusSessionController(modelContext: context, idleMonitor: idle, clock: { now })
        controller.isIdlePauseEnabled = true
        let project = controller.createProject(name: "Idle")
        controller.start(project: project)
        now = now.addingTimeInterval(20)
        // Simulate idle via private path: call handle through monitor callback
        idle.onIdleStateChange?(true)
        #expect(controller.phase == .pausedIdle)
        now = now.addingTimeInterval(50)
        idle.onIdleStateChange?(false)
        #expect(controller.phase == .running)
        now = now.addingTimeInterval(10)
        let finished = controller.stop(offerNotePrompt: false)
        // 20 + 10 focus, 50 paused
        #expect(abs((finished?.duration(at: now) ?? -1) - 30) < 0.01)
        #expect(abs((finished?.pausedDuration ?? -1) - 50) < 0.01)
    }

    @Test func noteIsTrimmedToEightyCharacters() throws {
        let (controller, _) = try makeController()
        let project = controller.createProject(name: "Note")
        controller.start(project: project)
        let finished = controller.stop(note: String(repeating: "a", count: 100), offerNotePrompt: false)
        #expect(finished?.note?.count == 80)
    }
}

@Suite("DateBounds")
struct DateBoundsTests {
    @Test func lastSevenDaysWindow() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents()
        components.year = 2026
        components.month = 8
        components.day = 12
        components.hour = 15
        let date = calendar.date(from: components)!
        let start = DateBounds.startOfLastDays(7, from: date, calendar: calendar)
        let expected = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: date))!
        #expect(start == expected)
    }
}
