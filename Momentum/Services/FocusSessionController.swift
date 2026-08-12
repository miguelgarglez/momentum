import Foundation
import SwiftData

@MainActor
@Observable
final class FocusSessionController {
    enum Phase: Equatable {
        case idle
        case running
        case pausedIdle
    }

    private(set) var phase: Phase = .idle
    private(set) var activeSession: FocusSession?
    private(set) var activeProject: Project?
    private(set) var displayedElapsed: TimeInterval = 0
    /// When true, the UI should offer an optional note after stop.
    private(set) var pendingNoteSession: FocusSession?

    var isIdlePauseEnabled = true
    var idleThreshold: TimeInterval = 5 * 60 {
        didSet { idleMonitor.idleThreshold = idleThreshold }
    }

    private let modelContext: ModelContext
    private let idleMonitor: IdleMonitor
    private var displayTimer: Timer?
    private var heartbeatTimer: Timer?
    private var pauseStartedAt: Date?
    private var clock: () -> Date

    init(
        modelContext: ModelContext,
        idleMonitor: IdleMonitor = IdleMonitor(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.modelContext = modelContext
        self.idleMonitor = idleMonitor
        self.clock = clock
        self.idleMonitor.idleThreshold = idleThreshold
        self.idleMonitor.onIdleStateChange = { [weak self] isIdle in
            self?.handleIdleChange(isIdle)
        }
        recoverOpenSessions()
    }

    var isFocusing: Bool {
        phase == .running || phase == .pausedIdle
    }

    // MARK: - Commands

    func start(project: Project) {
        let now = clock()
        if isFocusing {
            _ = stop(note: nil, offerNotePrompt: false, at: now)
        }

        let session = FocusSession(
            startAt: now,
            lastHeartbeatAt: now,
            project: project
        )
        modelContext.insert(session)
        project.lastUsedAt = now
        save()

        activeSession = session
        activeProject = project
        pauseStartedAt = nil
        phase = .running
        displayedElapsed = 0

        startDisplayTimer()
        startHeartbeat()
        if isIdlePauseEnabled {
            idleMonitor.start()
        }
        refreshElapsed()
    }

    @discardableResult
    func stop(note: String? = nil, offerNotePrompt: Bool = true, at date: Date? = nil) -> FocusSession? {
        guard let session = activeSession else { return nil }
        let now = date ?? clock()

        finalizePauseIfNeeded(at: now)
        session.endAt = now
        session.lastHeartbeatAt = now
        if let note {
            let trimmed = String(note.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
            session.note = trimmed.isEmpty ? nil : trimmed
        }
        save()

        let finished = session
        tearDownRuntime()
        if offerNotePrompt, finished.note == nil {
            pendingNoteSession = finished
        }
        return finished
    }

    func attachNote(_ note: String, to session: FocusSession) {
        let trimmed = String(note.prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
        session.note = trimmed.isEmpty ? nil : trimmed
        save()
        if pendingNoteSession?.persistentModelID == session.persistentModelID {
            pendingNoteSession = nil
        }
    }

    func dismissNotePrompt() {
        pendingNoteSession = nil
    }

    func toggleLastProject() {
        if isFocusing {
            stop()
            return
        }
        guard let project = mostRecentlyUsedProject() else { return }
        start(project: project)
    }

    func handleAppWillTerminate() {
        guard isFocusing, let session = activeSession else { return }
        let now = clock()
        finalizePauseIfNeeded(at: now)
        session.endAt = now
        session.lastHeartbeatAt = now
        session.wasInterrupted = true
        save()
        tearDownRuntime()
    }

    // MARK: - Queries

    func allProjects() -> [Project] {
        let descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    func mostRecentlyUsedProject() -> Project? {
        allProjects().first
    }

    func createProject(name: String, colorHex: String = ProjectColorPalette.defaultHex) -> Project {
        let project = Project(name: name.trimmingCharacters(in: .whitespacesAndNewlines), colorHex: colorHex)
        modelContext.insert(project)
        save()
        return project
    }

    func deleteProject(_ project: Project) {
        if activeProject?.persistentModelID == project.persistentModelID {
            _ = stop(note: nil, offerNotePrompt: false)
        }
        modelContext.delete(project)
        save()
    }

    func renameProject(_ project: Project, to name: String) {
        project.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    func setProjectColor(_ project: Project, hex: String) {
        project.colorHex = hex
        save()
    }

    func sessions(for project: Project) -> [FocusSession] {
        project.sessions.sorted { $0.startAt > $1.startAt }
    }

    func todaySeconds(for project: Project, now: Date = Date()) -> TimeInterval {
        let start = DateBounds.startOfDay(now)
        let end = DateBounds.endOfDay(now)
        return SessionTotals.seconds(in: project.sessions, from: start, to: end, now: effectiveNow(now))
    }

    func weekSeconds(for project: Project, now: Date = Date()) -> TimeInterval {
        let start = DateBounds.startOfLastDays(7, from: now)
        let end = DateBounds.endOfDay(now)
        return SessionTotals.seconds(in: project.sessions, from: start, to: end, now: effectiveNow(now))
    }

    func todaySecondsTotal(now: Date = Date()) -> TimeInterval {
        allProjects().reduce(0) { $0 + todaySeconds(for: $1, now: now) }
    }

    // MARK: - Internals

    private func effectiveNow(_ now: Date) -> Date {
        // While focusing, include live elapsed via open session endAt nil + pausedDuration.
        now
    }

    private func recoverOpenSessions() {
        let descriptor = FetchDescriptor<FocusSession>(
            predicate: #Predicate { $0.endAt == nil }
        )
        let openSessions = (try? modelContext.fetch(descriptor)) ?? []
        for session in openSessions {
            session.endAt = session.lastHeartbeatAt
            session.wasInterrupted = true
        }
        if !openSessions.isEmpty {
            save()
        }
    }

    private func handleIdleChange(_ isIdle: Bool) {
        guard isIdlePauseEnabled else { return }
        let now = clock()
        if isIdle {
            guard phase == .running else { return }
            pauseStartedAt = now
            phase = .pausedIdle
            refreshElapsed()
        } else {
            guard phase == .pausedIdle else { return }
            finalizePauseIfNeeded(at: now)
            phase = .running
            refreshElapsed()
            heartbeat()
        }
    }

    private func finalizePauseIfNeeded(at now: Date) {
        guard let pauseStartedAt, let session = activeSession else { return }
        session.pausedDuration += max(0, now.timeIntervalSince(pauseStartedAt))
        self.pauseStartedAt = nil
        session.lastHeartbeatAt = now
        save()
    }

    private func refreshElapsed() {
        guard let session = activeSession else {
            displayedElapsed = 0
            return
        }
        var paused = session.pausedDuration
        let now = clock()
        if let pauseStartedAt {
            paused += max(0, now.timeIntervalSince(pauseStartedAt))
        }
        displayedElapsed = max(0, now.timeIntervalSince(session.startAt) - paused)
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshElapsed()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.heartbeat()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func heartbeat() {
        guard let session = activeSession else { return }
        // Do not advance heartbeat into idle pause wall time beyond pause start.
        if let pauseStartedAt {
            session.lastHeartbeatAt = pauseStartedAt
        } else {
            session.lastHeartbeatAt = clock()
        }
        // Keep pausedDuration persisted if we were mid-pause? leave as-is until resume/stop.
        save()
    }

    private func tearDownRuntime() {
        idleMonitor.stop()
        displayTimer?.invalidate()
        displayTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        activeSession = nil
        activeProject = nil
        pauseStartedAt = nil
        phase = .idle
        displayedElapsed = 0
    }

    private func save() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("SwiftData save failed: \(error)")
        }
    }
}
