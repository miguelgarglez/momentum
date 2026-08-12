import Foundation
import SwiftData

@Model
final class Project {
    var name: String
    var colorHex: String
    var createdAt: Date
    var lastUsedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \FocusSession.project)
    var sessions: [FocusSession]

    init(
        name: String,
        colorHex: String = "#5B8DEF",
        createdAt: Date = Date(),
        lastUsedAt: Date = Date()
    ) {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.sessions = []
    }
}
