import Foundation

struct ProjectFormDraft {
    var name: String
    var colorHex: String
    var iconName: String
    var selectedAppIDs: Set<String>
    var manualApps: String
    var domains: String
    var assignedFiles: [String]
    var manualFilesEntry: String

    init(project: Project? = nil) {
        if let project {
            name = project.name
            colorHex = project.colorHex
            iconName = project.iconName
            selectedAppIDs = Set(project.assignedApps)
            manualApps = ""
            domains = project.assignedDomains.joined(separator: ", ")
            assignedFiles = project.assignedFiles
            manualFilesEntry = ""
        } else {
            name = ""
            colorHex = ProjectPalette.defaultColor.hex
            iconName = ProjectIcon.spark.systemName
            selectedAppIDs = []
            manualApps = ""
            domains = ""
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

    var assignedDomains: [String] {
        domains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
    }

    mutating func addFiles(_ paths: [String]) {
        let normalized = paths.map { $0.normalizedFilePath }.filter { !$0.isEmpty }
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
