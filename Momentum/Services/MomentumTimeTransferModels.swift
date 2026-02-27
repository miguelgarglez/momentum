import Foundation

struct MomentumTimeExportV1: Codable {
    let schemaVersion: Int
    let exportedAt: Date
    let app: String
    let project: MomentumTimeExportMetadataV1
    let records: [MomentumTimeRecordV1]
}

struct MomentumTimeExportMetadataV1: Codable {
    let name: String
    let colorHex: String
    let iconName: String
}

struct MomentumTimeRecordV1: Codable {
    let startDate: Date
    let endDate: Date
    let appName: String
    let bundleIdentifier: String?
    let domain: String?
    let filePath: String?
    let source: String
}
