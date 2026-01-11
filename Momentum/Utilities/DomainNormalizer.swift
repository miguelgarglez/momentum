import Foundation

enum DomainNormalizer {
    static func tokens(from input: String) -> [String] {
        input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normalize(_ rawValue: String) -> String? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var candidate = trimmed
        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              var host = url.host?.lowercased()
        else {
            return nil
        }
        if host.hasPrefix("www.") {
            host.removeFirst(4)
        }
        while host.hasSuffix(".") {
            host.removeLast()
        }
        guard !host.isEmpty, isValidHost(host) else { return nil }
        return host
    }

    static func domains(from input: String) -> [String] {
        tokens(from: input)
            .compactMap { normalize($0) }
    }

    static func rejectedTokens(from input: String) -> [String] {
        tokens(from: input)
            .filter { normalize($0) == nil }
    }

    private static func isValidHost(_ host: String) -> Bool {
        if host.count > 253 {
            return false
        }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return false }
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        for label in labels {
            guard !label.isEmpty, label.count <= 63 else { return false }
            if label.hasPrefix("-") || label.hasSuffix("-") {
                return false
            }
            if label.rangeOfCharacter(from: allowedCharacters.inverted) != nil {
                return false
            }
        }
        return true
    }
}
