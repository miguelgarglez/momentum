import Foundation
import SwiftData

@MainActor
struct MomentumTimeTransferService {
    let modelContext: ModelContext

    private let schemaVersion = 1
    private let appName = "Momentum"

    func export(project: Project) throws -> Data {
        let records = project.sessions
            .sorted { $0.startDate < $1.startDate }
            .map { session in
                MomentumTimeRecordV1(
                    startDate: session.startDate,
                    endDate: session.endDate,
                    appName: session.appName,
                    bundleIdentifier: session.bundleIdentifier,
                    domain: session.domain,
                    filePath: session.filePath,
                    source: session.source.rawValue
                )
            }

        let payload = MomentumTimeExportV1(
            schemaVersion: schemaVersion,
            exportedAt: Date(),
            app: appName,
            project: MomentumTimeExportMetadataV1(
                name: project.name,
                colorHex: project.colorHex,
                iconName: project.iconName
            ),
            records: records
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }
}
