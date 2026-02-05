import Foundation
import OSLog

@MainActor
final class RaycastTokenStore {
    private let keychain = KeychainStore(service: "Momentum.Raycast")
    private let account = "RaycastTokens"
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "Raycast")
    private var cachedTokens: Set<String>?

    func isValid(_ token: String) -> Bool {
        do {
            return try loadTokens().contains(token)
        } catch {
            logger.error("Failed to read Raycast tokens: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func issueToken() throws -> String {
        let token = UUID().uuidString
        var tokens = try loadTokens()
        tokens.insert(token)
        try storeTokens(tokens)
        return token
    }

    func hasTokens() throws -> Bool {
        try !loadTokens().isEmpty
    }

    func revokeAll() throws {
        try storeTokens([])
    }

    private func loadTokens() throws -> Set<String> {
        if let cachedTokens {
            return cachedTokens
        }
        guard let data = try keychain.read(account: account) else {
            cachedTokens = []
            return []
        }
        let decoded = try JSONDecoder().decode([String].self, from: data)
        let tokens = Set(decoded)
        cachedTokens = tokens
        return tokens
    }

    private func storeTokens(_ tokens: Set<String>) throws {
        let data = try JSONEncoder().encode(Array(tokens))
        try keychain.write(data, account: account)
        cachedTokens = tokens
    }
}
