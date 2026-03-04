#if os(macOS)
    @preconcurrency import AppKit
    import ApplicationServices
    import OSLog

    @MainActor
    final class FileDocumentResolver {
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "FileDocumentResolver")
        private let deniedPermissionRetryInterval: TimeInterval = 60
        private var nextPermissionRetryAt: [String: Date] = [:]
        private var grantedPermissionTargets: Set<String> = []

        func supports(bundleIdentifier: String?) -> Bool {
            guard let bundleIdentifier else { return false }
            return DocumentApp(bundleIdentifier: bundleIdentifier) != nil
        }

        func resolveFilePath(for application: NSRunningApplication) async -> String? {
            guard let identifier = application.bundleIdentifier,
                  let app = DocumentApp(bundleIdentifier: identifier)
            else {
                return nil
            }

            guard canAttemptAutomation(for: identifier),
                  hasAutomationPermission(for: identifier)
            else {
                return nil
            }
            let script = app.script

            return await DocumentAppleScriptRunner.run(script: script, identifier: identifier, logger: logger)
        }

        private func canAttemptAutomation(for bundleIdentifier: String) -> Bool {
            guard let retryAt = nextPermissionRetryAt[bundleIdentifier] else { return true }
            return retryAt <= Date()
        }

        private func hasAutomationPermission(for bundleIdentifier: String) -> Bool {
            if grantedPermissionTargets.contains(bundleIdentifier) {
                return true
            }
            let status = Self.automationPermissionStatus(for: bundleIdentifier, prompt: false)
            guard status == noErr else {
                nextPermissionRetryAt[bundleIdentifier] = Date().addingTimeInterval(deniedPermissionRetryInterval)
                logger.debug(
                    "Automation unavailable for \(bundleIdentifier, privacy: .public). Retrying after cooldown. status=\(Int(status), privacy: .public)"
                )
                return false
            }
            grantedPermissionTargets.insert(bundleIdentifier)
            nextPermissionRetryAt.removeValue(forKey: bundleIdentifier)
            return true
        }

        private static func automationPermissionStatus(for bundleIdentifier: String, prompt: Bool) -> OSStatus {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            return AEDeterminePermissionToAutomateTarget(
                target.aeDesc,
                AEEventClass(kAECoreSuite),
                AEEventID(kAEGetData),
                prompt,
            )
        }

        private enum DocumentApp {
            case preview(bundleIdentifier: String)
            case word(bundleIdentifier: String)
            case powerpoint(bundleIdentifier: String)
            case pages(bundleIdentifier: String)
            case keynote(bundleIdentifier: String)
            case numbers(bundleIdentifier: String)

            var identifier: String {
                switch self {
                case let .preview(bundleIdentifier),
                     let .word(bundleIdentifier),
                     let .powerpoint(bundleIdentifier),
                     let .pages(bundleIdentifier),
                     let .keynote(bundleIdentifier),
                     let .numbers(bundleIdentifier):
                    bundleIdentifier
                }
            }

            init?(bundleIdentifier: String) {
                switch bundleIdentifier {
                case "com.apple.Preview":
                    self = .preview(bundleIdentifier: bundleIdentifier)
                case "com.microsoft.Word":
                    self = .word(bundleIdentifier: bundleIdentifier)
                case "com.microsoft.Powerpoint":
                    self = .powerpoint(bundleIdentifier: bundleIdentifier)
                case "com.apple.iWork.Pages":
                    self = .pages(bundleIdentifier: bundleIdentifier)
                case "com.apple.iWork.Keynote":
                    self = .keynote(bundleIdentifier: bundleIdentifier)
                case "com.apple.iWork.Numbers":
                    self = .numbers(bundleIdentifier: bundleIdentifier)
                default:
                    return nil
                }
            }

            var script: String {
                switch self {
                case let .preview(bundleIdentifier):
                    Self.previewScript(bundleIdentifier: bundleIdentifier)
                case let .word(bundleIdentifier):
                    Self.wordScript(bundleIdentifier: bundleIdentifier)
                case let .powerpoint(bundleIdentifier):
                    Self.powerpointScript(bundleIdentifier: bundleIdentifier)
                case let .pages(bundleIdentifier):
                    Self.iWorkScript(bundleIdentifier: bundleIdentifier)
                case let .keynote(bundleIdentifier):
                    Self.iWorkScript(bundleIdentifier: bundleIdentifier)
                case let .numbers(bundleIdentifier):
                    Self.iWorkScript(bundleIdentifier: bundleIdentifier)
                }
            }

            private static func previewScript(bundleIdentifier: String) -> String {
                """
                tell application id "\(bundleIdentifier)"
                    if (count of documents) = 0 then return ""
                    set docPath to path of front document
                    if docPath is missing value then return ""
                    return POSIX path of docPath
                end tell
                return ""
                """
            }

            private static func wordScript(bundleIdentifier: String) -> String {
                """
                tell application id "\(bundleIdentifier)"
                    if (count of documents) = 0 then return ""
                    set docPath to full name of active document
                    if docPath is missing value then return ""
                    return docPath
                end tell
                return ""
                """
            }

            private static func powerpointScript(bundleIdentifier: String) -> String {
                """
                tell application id "\(bundleIdentifier)"
                    if (count of presentations) = 0 then return ""
                    set docPath to full name of active presentation
                    if docPath is missing value then return ""
                    return docPath
                end tell
                return ""
                """
            }

            private static func iWorkScript(bundleIdentifier: String) -> String {
                """
                tell application id "\(bundleIdentifier)"
                    if (count of documents) = 0 then return ""
                    set docPath to path of front document
                    if docPath is missing value then return ""
                    return POSIX path of docPath
                end tell
                return ""
                """
            }
        }
    }

    private nonisolated enum DocumentAppleScriptRunner {
        @concurrent
        static func run(script: String, identifier: String, logger: Logger) async -> String? {
            guard let path = await AppleScriptRunner.run(script: script, identifier: identifier, logger: logger) else {
                return nil
            }
            return path.normalizedFilePath
        }
    }
#else
    final class FileDocumentResolver {
        func supports(bundleIdentifier _: String?) -> Bool { false }
        func resolveFilePath(for _: Any) async -> String? { nil }
    }
#endif
