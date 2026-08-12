import Foundation
import SwiftData

@Model
final class FocusSession {
    var startAt: Date
    var endAt: Date?
    var note: String?
    var wasInterrupted: Bool
    /// Accumulated idle-pause time that should not count toward focus.
    var pausedDuration: TimeInterval
    /// Updated while the session is open so crash recovery does not over-count.
    var lastHeartbeatAt: Date
    var project: Project?

    init(
        startAt: Date = Date(),
        endAt: Date? = nil,
        note: String? = nil,
        wasInterrupted: Bool = false,
        pausedDuration: TimeInterval = 0,
        lastHeartbeatAt: Date = Date(),
        project: Project? = nil
    ) {
        self.startAt = startAt
        self.endAt = endAt
        self.note = note
        self.wasInterrupted = wasInterrupted
        self.pausedDuration = pausedDuration
        self.lastHeartbeatAt = lastHeartbeatAt
        self.project = project
    }

    var isOpen: Bool { endAt == nil }

    func duration(at reference: Date = Date()) -> TimeInterval {
        let end = endAt ?? reference
        return max(0, end.timeIntervalSince(startAt) - pausedDuration)
    }
}
