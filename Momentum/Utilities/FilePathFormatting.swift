import Foundation

extension String {
    var filePathDisplayName: String {
        let url = URL(fileURLWithPath: self)
        let name = url.lastPathComponent
        return name.isEmpty ? self : name
    }

    var normalizedFilePath: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }
}
