//
//  AssignmentResult.swift
//  Momentum
//
//  Created by Codex on 23/11/25.
//

import Foundation

enum AssignmentContextType: String {
    case app
    case domain
    case file
}

struct AssignmentContext: Equatable {
    let type: AssignmentContextType
    let value: String
}

enum AssignmentResult {
    case assigned(Project, usedRule: Bool)
    case conflict(AssignmentContext, candidates: [Project])
    case none
}
