import Foundation

struct ProjectFormDraft {
    struct DomainEntryResult {
        let added: [String]
        let rejected: [String]
    }

    var name: String
    var colorHex: String
    var iconName: String
    var selectedAppIDs: Set<String>
    var manualApps: String
    var domainEntry: String
    var assignedDomains: [String]
    var assignedFiles: [String]
    var manualFilesEntry: String

    init(project: Project? = nil) {
        if let project {
            name = project.name
            colorHex = project.colorHex
            iconName = project.iconName
            selectedAppIDs = Set(project.assignedApps)
            manualApps = ""
            domainEntry = ""
            assignedDomains = project.assignedDomains
            assignedFiles = project.assignedFiles
            manualFilesEntry = ""
        } else {
            name = ""
            colorHex = ProjectPalette.defaultColor.hex
            iconName = ProjectIcon.spark.systemName
            selectedAppIDs = []
            manualApps = ""
            domainEntry = ""
            assignedDomains = []
            assignedFiles = []
            manualFilesEntry = ""
        }
    }

    var assignedApps: [String] {
        let manual = manualApps
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(selectedAppIDs.union(manual))
            .sorted()
    }

    var isDomainEntryEmpty: Bool {
        let trimmed = domainEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutCommas = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ","))
        return withoutCommas.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    mutating func addDomainEntry() -> DomainEntryResult {
        let domains = DomainNormalizer.domains(from: domainEntry)
        let rejected = DomainNormalizer.rejectedTokens(from: domainEntry)
        addDomains(domains)
        if !domains.isEmpty {
            domainEntry = ""
        }
        return DomainEntryResult(added: domains, rejected: rejected)
    }

    mutating func addDomains(_ domains: [String]) {
        guard !domains.isEmpty else { return }
        var seen = Set(assignedDomains.map { $0.lowercased() })
        for domain in domains {
            let key = domain.lowercased()
            guard seen.insert(key).inserted else { continue }
            assignedDomains.append(domain)
        }
    }

    mutating func removeDomain(_ domain: String) {
        assignedDomains.removeAll { $0.caseInsensitiveCompare(domain) == .orderedSame }
    }

    mutating func addFiles(_ paths: [String]) {
        let normalized = paths.map(\.normalizedFilePath).filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }
        var seen: Set<String> = []
        let merged = (assignedFiles + normalized).filter { path in
            let key = path.lowercased()
            return seen.insert(key).inserted
        }
        assignedFiles = merged.sorted()
    }

    mutating func removeFile(_ path: String) {
        assignedFiles.removeAll { $0.caseInsensitiveCompare(path) == .orderedSame }
    }

    mutating func addManualFilesEntry() {
        let entries = manualFilesEntry
            .split(separator: ",")
            .map { String($0).normalizedFilePath }
            .filter { !$0.isEmpty }
        addFiles(entries)
        manualFilesEntry = ""
    }
}
