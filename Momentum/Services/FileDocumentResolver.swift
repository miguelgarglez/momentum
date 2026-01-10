#if os(macOS)
    import AppKit
    import ApplicationServices
    import OSLog

    final class FileDocumentResolver {
        private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momentum", category: "FileDocumentResolver")

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

            _ = await MainActor.run {
                FileDocumentResolver.requestAutomationPermission(for: identifier)
            }

            return await Task.detached(priority: .utility) { [logger] in
                let script = app.script
                guard let appleScript = NSAppleScript(source: script) else {
                    logger.error("Failed to compile AppleScript for file lookup")
                    return nil
                }
                var error: NSDictionary?
                let descriptor = appleScript.executeAndReturnError(&error)
                if let error,
                   let errorNumber = error[NSAppleScript.errorNumber] as? Int,
                   errorNumber == -600
                {
                    logger.debug("Document app \(identifier, privacy: .public) not ready for AppleScript (not running)")
                    return nil
                } else if let error {
                    logger.error("AppleScript error: \(error, privacy: .public)")
                }
                guard let path = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !path.isEmpty
                else {
                    return nil
                }
                return path.normalizedFilePath
            }.value
        }

        private static func requestAutomationPermission(for bundleIdentifier: String) -> Bool {
            let target = NSAppleEventDescriptor(bundleIdentifier: bundleIdentifier)
            let status = AEDeterminePermissionToAutomateTarget(
                target.aeDesc,
                AEEventClass(kAECoreSuite),
                AEEventID(kAEGetData),
                true
            )
            return status == noErr
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
                    return bundleIdentifier
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
                    return Self.previewScript(bundleIdentifier: bundleIdentifier)
                case let .word(bundleIdentifier):
                    return Self.wordScript(bundleIdentifier: bundleIdentifier)
                case let .powerpoint(bundleIdentifier):
                    return Self.powerpointScript(bundleIdentifier: bundleIdentifier)
                case let .pages(bundleIdentifier):
                    return Self.iWorkScript(bundleIdentifier: bundleIdentifier)
                case let .keynote(bundleIdentifier):
                    return Self.iWorkScript(bundleIdentifier: bundleIdentifier)
                case let .numbers(bundleIdentifier):
                    return Self.iWorkScript(bundleIdentifier: bundleIdentifier)
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
#else
    final class FileDocumentResolver {
        func supports(bundleIdentifier _: String?) -> Bool { false }
        func resolveFilePath(for _: Any) async -> String? { nil }
    }
#endif
