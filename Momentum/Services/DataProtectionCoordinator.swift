import Combine
import Foundation
import OSLog
import SwiftData

@MainActor
final class DataProtectionCoordinator: ObservableObject {
    private let container: ModelContainer
    private let settings: TrackerSettings
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "DataProtection")
    private var cancellables: Set<AnyCancellable> = []

    init(container: ModelContainer, settings: TrackerSettings) {
        self.container = container
        self.settings = settings
        applyProtection(isEnabled: settings.isDatabaseEncryptionEnabled)
        settings.$isDatabaseEncryptionEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.applyProtection(isEnabled: enabled)
            }
            .store(in: &cancellables)
    }

    private func applyProtection(isEnabled: Bool) {
        let protection: FileProtectionType = isEnabled ? .complete : .none
        logger.debug("Updating store file protection. Enabled: \(isEnabled, privacy: .public)")
        for configuration in container.configurations {
            guard configuration.url.isFileURL else { continue }
            prepareDirectory(for: configuration.url)
            secureFile(at: configuration.url, protection: protection)
            secureCompanionFiles(for: configuration.url, protection: protection)
        }
    }

    private func secureCompanionFiles(for url: URL, protection: FileProtectionType) {
        let basePath = url.path
        secureFile(atPath: basePath + "-wal", protection: protection)
        secureFile(atPath: basePath + "-shm", protection: protection)
    }

    private func secureFile(atPath path: String, protection: FileProtectionType) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        do {
            try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: path)
        } catch {
            logger.error("Failed to set protection for \(path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    private func secureFile(at url: URL, protection: FileProtectionType) {
        secureFile(atPath: url.path, protection: protection)
    }

    private func prepareDirectory(for url: URL) {
        let directory = url.deletingLastPathComponent()
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create store directory: \(error.localizedDescription, privacy: .public)")
        }
    }
}
