//
//  AssignmentRule.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation
import SwiftData

@Model
final class AssignmentRule {
    var contextType: String
    var contextValue: String
    @Relationship(deleteRule: .nullify)
    var project: Project?
    var createdAt: Date
    var lastUsedAt: Date

    init(
        contextType: String,
        contextValue: String,
        project: Project?,
        createdAt: Date = .now,
        lastUsedAt: Date = .now,
    ) {
        self.contextType = contextType
        self.contextValue = contextValue
        self.project = project
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

extension AssignmentRule {
    var effectiveLastUsedAt: Date {
        max(lastUsedAt, createdAt)
    }

    var contextLabel: String {
        switch AssignmentContextType(rawValue: contextType) {
        case .app:
            "App"
        case .domain:
            "Dominio"
        case .file:
            "Archivo"
        case .none:
            "Contexto"
        }
    }
}
