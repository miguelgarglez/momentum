import Foundation

extension String {
    nonisolated var filePathDisplayName: String {
        let url = URL(fileURLWithPath: self)
        let name = url.lastPathComponent
        return name.isEmpty ? self : name
    }

    nonisolated var normalizedFilePath: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }
}
