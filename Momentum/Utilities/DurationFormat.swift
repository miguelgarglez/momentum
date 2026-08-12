import Foundation

enum DurationFormat: Sendable {
    /// Menu-bar style: `MM:SS` under one hour, otherwise `H:MM:SS`.
    nonisolated static func chronometer(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Compact summary for menus/lists: `1h 05m`, `42m`, `12s`.
    nonisolated static func summary(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        if minutes > 0 {
            return String(format: "%dm", minutes)
        }
        return String(format: "%ds", seconds)
    }
}
