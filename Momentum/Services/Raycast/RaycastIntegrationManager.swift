import Combine
import Foundation
import OSLog
import SwiftData

@MainActor
final class RaycastIntegrationManager: ObservableObject {
    private static let supportedCommandActions: [String] = [
        "projects.list",
        "project.open",
        "conflicts.open",
        "manual.start",
        "manual.stop",
        "manual.open",
    ]

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
    private weak var tracker: ActivityTracker?
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

    func configure(modelContainer: ModelContainer?, tracker: ActivityTracker?, isUITest: Bool, isSeedRun: Bool) {
        self.modelContainer = modelContainer
        self.tracker = tracker
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
                data: RaycastHealthPayload(
                    apiVersion: 1,
                    capabilities: RaycastCapabilitiesPayload(
                        supportedCommandActions: Self.supportedCommandActions,
                        requiresPairing: true,
                    )
                ),
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
        case "project.open":
            return handleProjectOpen(command)
        case "conflicts.open":
            return handleConflictsOpen(command)
        case "manual.start":
            return handleManualStart(command)
        case "manual.stop":
            return handleManualStop()
        case "manual.open":
            return handleManualOpen(command)
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

    private func handleProjectOpen(_ command: RaycastCommandRequest) -> RaycastHTTPResponse {
        guard let modelContainer else {
            return RaycastHTTPError.response(code: 503, error: "StoreNotReady", message: "La base de datos no está lista.")
        }
        guard let payload = command.payload else {
            return RaycastHTTPError.response(code: 422, error: "InvalidPayload", message: "Proyecto requerido.")
        }

        let project = findProject(by: payload.projectID, name: payload.projectName, in: modelContainer.mainContext)
        guard let project else {
            return RaycastHTTPError.response(code: 404, error: "ProjectNotFound", message: "No encontramos el proyecto indicado.")
        }

        NotificationCenter.default.post(name: .statusItemShowApp, object: nil)
        NotificationCenter.default.post(name: .statusItemOpenProject, object: nil, userInfo: [
            StatusItemUserInfoKey.projectID: project.persistentModelID,
        ])

        let response = RaycastEnvelope(
            ok: true,
            data: RaycastProjectOpenResponse(
                opened: true,
                project: RaycastProjectSummary(
                    id: String(describing: project.persistentModelID),
                    name: project.name,
                    colorHex: project.colorHex,
                    iconName: project.iconName,
                )
            ),
            error: nil,
            message: nil,
        )
        return RaycastHTTPResponse.json(statusCode: 200, payload: response)
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

    private func handleManualStart(_ command: RaycastCommandRequest) -> RaycastHTTPResponse {
        guard let modelContainer else {
            return RaycastHTTPError.response(code: 503, error: "StoreNotReady", message: "La base de datos no está lista.")
        }
        guard let tracker else {
            return RaycastHTTPError.response(code: 503, error: "TrackerNotReady", message: "El rastreador no está listo.")
        }

        let payload = command.payload
        let selectedProject: Project

        if let projectID = payload?.projectID {
            guard let existingProject = findProject(by: projectID, name: payload?.projectName, in: modelContainer.mainContext) else {
                return RaycastHTTPError.response(code: 422, error: "ProjectNotFound", message: "No encontramos el proyecto indicado.")
            }
            selectedProject = existingProject
        } else {
            let baseName = payload?.newProjectName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let projectName = manualProjectName(from: baseName, in: modelContainer.mainContext)
            let iconName = validatedProjectIconName(payload?.newProjectIconName)
            let createdProject = Project(
                name: projectName,
                colorHex: ProjectPalette.defaultColor.hex,
                iconName: iconName,
            )
            modelContainer.mainContext.insert(createdProject)
            do {
                try modelContainer.mainContext.save()
            } catch {
                logger.error("Failed to create manual project from Raycast: \(error.localizedDescription, privacy: .public)")
                return RaycastHTTPError.response(code: 500, error: "ProjectCreateFailed", message: "No pudimos crear el proyecto.")
            }
            selectedProject = createdProject
        }

        tracker.startManualTracking(project: selectedProject)

        let result = RaycastManualStartResponse(
            project: RaycastProjectSummary(
                id: String(describing: selectedProject.persistentModelID),
                name: selectedProject.name,
                colorHex: selectedProject.colorHex,
                iconName: selectedProject.iconName,
            )
        )
        let response = RaycastEnvelope(
            ok: true,
            data: result,
            error: nil,
            message: nil,
        )
        return RaycastHTTPResponse.json(statusCode: 200, payload: response)
    }

    private func handleManualOpen(_ command: RaycastCommandRequest) -> RaycastHTTPResponse {
        let mode = command.payload?.mode == "existing" ? "existing" : "new"
        NotificationCenter.default.post(
            name: .raycastStartManualTracking,
            object: nil,
            userInfo: ["mode": mode],
        )
        let payload = RaycastEnvelope(
            ok: true,
            data: RaycastEmptyPayload(),
            error: nil,
            message: nil,
        )
        return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
    }

    private func handleManualStop() -> RaycastHTTPResponse {
        guard let tracker else {
            return RaycastHTTPError.response(code: 503, error: "TrackerNotReady", message: "El rastreador no está listo.")
        }

        let wasActive = tracker.isManualTrackingActive
        if wasActive {
            tracker.stopManualTracking(reason: .manual)
        }

        let payload = RaycastEnvelope(
            ok: true,
            data: RaycastManualStopResponse(wasActive: wasActive),
            error: nil,
            message: nil,
        )
        return RaycastHTTPResponse.json(statusCode: 200, payload: payload)
    }

    private func parseBearerToken(_ request: RaycastHTTPRequest) -> String? {
        guard let header = request.headerValue(for: "authorization") else { return nil }
        let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return nil }
        return String(parts[1])
    }

    private func findProject(by id: String?, name: String?, in context: ModelContext) -> Project? {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name, order: .forward)])
        guard let projects = try? context.fetch(descriptor) else { return nil }
        if let id, !id.isEmpty {
            if let byID = projects.first(where: { String(describing: $0.persistentModelID) == id }) {
                return byID
            }
        }
        if let name, !name.isEmpty {
            return projects.first(where: { $0.name == name })
        }
        return nil
    }

    private func manualProjectName(from baseName: String, in context: ModelContext) -> String {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name, order: .forward)])
        let existingProjects = (try? context.fetch(descriptor)) ?? []
        let existingNames = Set(existingProjects.map { $0.name.lowercased() })
        let seed = baseName.isEmpty ? "New cool project" : baseName
        let needsSuffix = baseName.isEmpty || existingNames.contains(seed.lowercased())
        guard needsSuffix else { return seed }

        var index = 1
        while true {
            let candidate = "\(seed) (\(index))"
            if !existingNames.contains(candidate.lowercased()) {
                return candidate
            }
            index += 1
        }
    }

    private func validatedProjectIconName(_ rawValue: String?) -> String {
        if let rawValue, ProjectIcon.allCases.contains(where: { $0.systemName == rawValue }) {
            return rawValue
        }
        return ProjectIcon.allCases.randomElement()?.systemName ?? ProjectIcon.spark.systemName
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
    let capabilities: RaycastCapabilitiesPayload
}

private struct RaycastCapabilitiesPayload: Encodable {
    let supportedCommandActions: [String]
    let requiresPairing: Bool
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
    let payload: RaycastCommandPayload?
    let apiVersion: Int?
}

private struct RaycastCommandPayload: Decodable {
    let projectID: String?
    let projectName: String?
    let newProjectName: String?
    let newProjectIconName: String?
    let mode: String?

    private enum CodingKeys: String, CodingKey {
        case projectID = "projectId"
        case projectName
        case newProjectName
        case newProjectIconName
        case mode
    }
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

private struct RaycastManualStartResponse: Encodable {
    let project: RaycastProjectSummary
}

private struct RaycastManualStopResponse: Encodable {
    let wasActive: Bool
}

private struct RaycastProjectOpenResponse: Encodable {
    let opened: Bool
    let project: RaycastProjectSummary
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
