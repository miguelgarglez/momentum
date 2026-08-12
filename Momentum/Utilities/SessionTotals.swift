import Foundation

enum SessionTotals {
    static func seconds(
        in sessions: [FocusSession],
        from start: Date,
        to end: Date,
        now: Date = Date()
    ) -> TimeInterval {
        sessions.reduce(0) { partial, session in
            partial + overlappingFocusSeconds(session: session, rangeStart: start, rangeEnd: end, now: now)
        }
    }

    /// Distributes a session's counted focus time across a calendar range by wall-clock overlap.
    /// Paused duration is treated as evenly excluded from the whole session span.
    static func overlappingFocusSeconds(
        session: FocusSession,
        rangeStart: Date,
        rangeEnd: Date,
        now: Date = Date()
    ) -> TimeInterval {
        let sessionEnd = session.endAt ?? now
        let overlapStart = max(session.startAt, rangeStart)
        let overlapEnd = min(sessionEnd, rangeEnd)
        guard overlapEnd > overlapStart else { return 0 }

        let wall = sessionEnd.timeIntervalSince(session.startAt)
        guard wall > 0 else { return 0 }

        let focus = max(0, wall - session.pausedDuration)
        let overlapWall = overlapEnd.timeIntervalSince(overlapStart)
        return focus * (overlapWall / wall)
    }
}
