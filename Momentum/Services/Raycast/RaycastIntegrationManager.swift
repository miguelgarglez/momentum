import Combine
import Foundation
import OSLog
import SwiftData

@MainActor
final class RaycastIntegrationManager: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var pairingCode: String?
    @Published private(set) var pairingExpiresAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var hasActiveToken: Bool = false
    @Published private(set) var statusMessage: RaycastStatusMessage?

    let port: UInt16

    private let settings: TrackerSettings
    private let tokenStore: RaycastTokenStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "Raycast")
    private var cancellables: Set<AnyCancellable> = []
    private var modelContainer: ModelContainer?
    private var isAvailable = false
    private var isStarting = false
    private var statusTask: Task<Void, Never>?
    private var lastSettingsOpenAt: Date?
    private var lastMainWindowOpenAt: Date?

    private lazy var server = RaycastServer(port: port) { [weak self] request in
        if let response = await self?.handle(request) {
            return response
        }
        return await MainActor.run {
            RaycastHTTPError.response(
                code: 500,
                error: "ServerUnavailable",
                message: "No pudimos procesar la solicitud.",
            )
        }
    }

    init(settings: TrackerSettings, port: UInt16 = 51637, tokenStore: RaycastTokenStore = RaycastTokenStore()) {
        self.settings = settings
        self.port = port
        self.tokenStore = tokenStore
        isEnabled = settings.isRaycastIntegrationEnabled

        settings.$isRaycastIntegrationEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                Task { @MainActor in
                    self?.setEnabled(enabled)
                }
            }
            .store(in: &cancellables)
    }

    func configure(modelContainer: ModelContainer?, isUITest: Bool, isSeedRun: Bool) {
        self.modelContainer = modelContainer
        isAvailable = !(isUITest || isSeedRun)
        refreshTokenStatus()
        evaluateState()
    }

    func refreshPairingCode() {
        pairingCode = RaycastIntegrationManager.makePairingCode()
        pairingExpiresAt = Date().addingTimeInterval(10 * 60)
    }

    func revokeTokens() {
        do {
            try tokenStore.revokeAll()
            hasActiveToken = false
            showStatusMessage(
                RaycastStatusMessage(
                    text: "Tokens revocados",
                    systemImage: "xmark.seal.fill",
                    style: .warning
                )
            )
        } catch {
            lastError = "No pudimos revocar los tokens."
            logger.error("Failed to revoke Raycast tokens: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        evaluateState()
    }

    private func evaluateState() {
        guard isAvailable else {
            stopServer()
            return
        }
        if isEnabled {
            startServer()
        } else {
            stopServer()
        }
    }

    private func startServer() {
        guard !isRunning, !isStarting else { return }
        isStarting = true
        Task {
            do {
                try await server.start()
                isRunning = true
                lastError = nil
                if pairingCode == nil || isPairingExpired {
                    refreshPairingCode()
                }
            } catch {
                isRunning = false
                lastError = "No pudimos iniciar el servidor local. Revisa que el puerto \(port) esté libre."
                logger.error("Raycast server failed to start: \(error.localizedDescription, privacy: .public)")
            }
            isStarting = false
        }
    }

    private func stopServer() {
        server.stop()
        isRunning = false
        isStarting = false
        lastError = nil
        pairingCode = nil
        pairingExpiresAt = nil
    }

    private var isPairingExpired: Bool {
        if let expiresAt = pairingExpiresAt {
            return Date() > expiresAt
        }
        return true
    }

    private func validatePairingCode(_ code: String) -> Bool {
        guard let current = pairingCode, let expiresAt = pairingExpiresAt else {
            return false
        }
        guard Date() <= expiresAt else {
            pairingCode = nil
            pairingExpiresAt = nil
            return false
        }
        return current == code
    }

    private func handle(_ request: RaycastHTTPRequest) async -> RaycastHTTPResponse {
        switch (request.method.uppercased(), request.path) {
        case ("GET", "/health"):
            let payload = RaycastEnvelope(
                ok: true,
                data: RaycastHealthPayload(apiVersion: 1),
                error: nil,
                message: nil,
            )
            return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
        case ("POST", "/v1/settings/open"):
            return handleSettingsOpen(request)
        case ("POST", "/v1/app/open"):
            return handleAppOpen(request)
        case ("POST", "/v1/pairing/confirm"):
            return handlePairingConfirm(request)
        case ("POST", "/v1/commands"):
            return await handleCommands(request)
        default:
            return RaycastHTTPError.response(code: 404, error: "NotFound", message: "Ruta no encontrada.")
        }
    }

    private func handlePairingConfirm(_ request: RaycastHTTPRequest) -> RaycastHTTPResponse {
        guard let pairing = try? JSONDecoder().decode(RaycastPairingRequest.self, from: request.body) else {
            return RaycastHTTPError.response(code: 422, error: "InvalidPayload", message: "Payload inválido.")
        }
        if let apiVersion = pairing.apiVersion, apiVersion != 1 {
            return RaycastHTTPError.response(code: 426, error: "UpgradeRequired", message: "Versión no soportada.")
        }
        guard validatePairingCode(pairing.code) else {
            return RaycastHTTPError.response(code: 401, error: "InvalidPairingCode", message: "Código inválido o expirado.")
        }
        do {
            let token = try tokenStore.issueToken()
            hasActiveToken = true
            showStatusMessage(
                RaycastStatusMessage(
                    text: "Emparejamiento completado",
                    systemImage: "checkmark.seal.fill",
                    style: .success
                )
            )
            let payload = RaycastEnvelope(
                ok: true,
                data: RaycastPairingResponse(token: token, expiresAt: nil),
                error: nil,
                message: nil,
            )
            return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
        } catch {
            logger.error("Failed to issue Raycast token: \(error.localizedDescription, privacy: .public)")
            return RaycastHTTPError.response(code: 500, error: "TokenStoreFailure", message: "No pudimos generar el token.")
        }
    }

    private func handleSettingsOpen(_ request: RaycastHTTPRequest) -> RaycastHTTPResponse {
        let section = (try? JSONDecoder().decode(RaycastSettingsOpenRequest.self, from: request.body))?.section
        if let lastSettingsOpenAt, Date().timeIntervalSince(lastSettingsOpenAt) < 4.0 {
            let payload = RaycastEnvelope(
                ok: true,
                data: RaycastEmptyPayload(),
                error: nil,
                message: nil,
            )
            return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
        }
        lastSettingsOpenAt = Date()
        MomentumDeepLink.openSettings(section: section ?? "raycast")
        let payload = RaycastEnvelope(
            ok: true,
            data: RaycastEmptyPayload(),
            error: nil,
            message: nil,
        )
        return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
    }

    private func handleAppOpen(_ request: RaycastHTTPRequest) -> RaycastHTTPResponse {
        _ = try? JSONDecoder().decode(RaycastAppOpenRequest.self, from: request.body)
        if let lastMainWindowOpenAt, Date().timeIntervalSince(lastMainWindowOpenAt) < 2.0 {
            let payload = RaycastEnvelope(
                ok: true,
                data: RaycastEmptyPayload(),
                error: nil,
                message: nil,
            )
            return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
        }
        lastMainWindowOpenAt = Date()
        NotificationCenter.default.post(name: .statusItemShowApp, object: nil)
        let payload = RaycastEnvelope(
            ok: true,
            data: RaycastEmptyPayload(),
            error: nil,
            message: nil,
        )
        return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
    }

    private func handleCommands(_ request: RaycastHTTPRequest) async -> RaycastHTTPResponse {
        guard let token = parseBearerToken(request) else {
            return RaycastHTTPError.response(code: 401, error: "Unauthorized", message: "Token requerido.")
        }
        guard tokenStore.isValid(token) else {
            return RaycastHTTPError.response(code: 401, error: "Unauthorized", message: "Token inválido.")
        }
        guard let command = try? JSONDecoder().decode(RaycastCommandRequest.self, from: request.body) else {
            return RaycastHTTPError.response(code: 422, error: "InvalidPayload", message: "Payload inválido.")
        }
        if let apiVersion = command.apiVersion, apiVersion != 1 {
            return RaycastHTTPError.response(code: 426, error: "UpgradeRequired", message: "Versión no soportada.")
        }

        switch command.action {
        case "projects.list":
            return handleProjectsList()
        case "conflicts.open":
            return handleConflictsOpen(command)
        default:
            return RaycastHTTPError.response(code: 422, error: "UnsupportedAction", message: "Acción no soportada.")
        }
    }

    private func handleProjectsList() -> RaycastHTTPResponse {
        guard let modelContainer else {
            return RaycastHTTPError.response(code: 503, error: "StoreNotReady", message: "La base de datos no está lista.")
        }
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name, order: .forward)])
        do {
            let projects = try modelContainer.mainContext.fetch(descriptor)
            let summaries = projects.map { project in
                RaycastProjectSummary(
                    id: String(describing: project.persistentModelID),
                    name: project.name,
                    colorHex: project.colorHex,
                    iconName: project.iconName,
                )
            }
            let payload = RaycastEnvelope<[RaycastProjectSummary]>(
                ok: true,
                data: summaries,
                error: nil,
                message: nil,
            )
            return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
        } catch {
            logger.error("Failed to fetch projects for Raycast: \(error.localizedDescription, privacy: .public)")
            return RaycastHTTPError.response(code: 500, error: "FetchFailed", message: "No pudimos leer los proyectos.")
        }
    }

    private func handleConflictsOpen(_ command: RaycastCommandRequest) -> RaycastHTTPResponse {
        guard let modelContainer else {
            return RaycastHTTPError.response(code: 503, error: "StoreNotReady", message: "La base de datos no está lista.")
        }

        do {
            let descriptor = FetchDescriptor<PendingTrackingSession>(sortBy: [SortDescriptor(\.endDate, order: .reverse)])
            let pendingSessions = try modelContainer.mainContext.fetch(descriptor)
            let conflictsCount = pendingSessions.count
            let shouldPresent = command.present ?? true
            let opened = conflictsCount > 0 && shouldPresent

            if opened {
                NotificationCenter.default.post(name: .raycastShowConflicts, object: nil)
            }

            let payload = RaycastEnvelope(
                ok: true,
                data: RaycastConflictsOpenResponse(conflictsCount: conflictsCount, opened: opened),
                error: nil,
                message: nil,
            )
            return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
        } catch {
            logger.error("Failed to fetch pending conflicts for Raycast: \(error.localizedDescription, privacy: .public)")
            return RaycastHTTPError.response(code: 500, error: "FetchFailed", message: "No pudimos leer los conflictos pendientes.")
        }
    }

    private func parseBearerToken(_ request: RaycastHTTPRequest) -> String? {
        guard let header = request.headerValue(for: "authorization") else { return nil }
        let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        return String(parts[1])
    }

    private func refreshTokenStatus() {
        do {
            hasActiveToken = try tokenStore.hasTokens()
        } catch {
            hasActiveToken = false
            logger.error("Failed to read Raycast tokens: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func showStatusMessage(_ message: RaycastStatusMessage, duration: TimeInterval = 4) {
        statusTask?.cancel()
        statusMessage = message
        statusTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.statusMessage = nil
            }
        }
    }

    private static func makePairingCode() -> String {
        let value = Int.random(in: 0 ... 9999)
        return String(format: "%04d", value)
    }
}

private struct RaycastHealthPayload: Encodable {
    let apiVersion: Int
}

private struct RaycastPairingRequest: Decodable {
    let code: String
    let clientName: String?
    let apiVersion: Int?
}

private struct RaycastPairingResponse: Encodable {
    let token: String
    let expiresAt: String?
}

private struct RaycastSettingsOpenRequest: Decodable {
    let section: String?
    let apiVersion: Int?
}

private struct RaycastAppOpenRequest: Decodable {
    let apiVersion: Int?
}

private struct RaycastCommandRequest: Decodable {
    let action: String
    let requestId: String?
    let present: Bool?
    let apiVersion: Int?
}

private struct RaycastProjectSummary: Encodable {
    let id: String
    let name: String
    let colorHex: String
    let iconName: String
}

private struct RaycastConflictsOpenResponse: Encodable {
    let conflictsCount: Int
    let opened: Bool
}

struct RaycastStatusMessage: Equatable {
    enum Style {
        case success
        case warning
        case info
    }

    let text: String
    let systemImage: String
    let style: Style
}
