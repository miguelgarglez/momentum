#if os(macOS)
    @preconcurrency import AppKit
    import Foundation
    import OSLog

    @MainActor
    enum AppleScriptRunner {
        private static let queue = DispatchQueue(label: "Momentum.AppleScriptRunner")

        static func run(script: String, identifier: String, logger: Logger) async -> String? {
            await withCheckedContinuation { continuation in
                queue.async {
                    guard let appleScript = NSAppleScript(source: script) else {
                        logger.error("Failed to compile AppleScript for \(identifier, privacy: .public)")
                        continuation.resume(returning: nil)
                        return
                    }
                    var error: NSDictionary?
                    let descriptor = appleScript.executeAndReturnError(&error)
                    if let error,
                       let errorNumber = error[NSAppleScript.errorNumber] as? Int,
                       errorNumber == -600
                    {
                        logger.debug("App \(identifier, privacy: .public) not ready for AppleScript (not running)")
                        continuation.resume(returning: nil)
                        return
                    } else if let error {
                        logger.error("AppleScript error: \(error, privacy: .public)")
                    }
                    guard let value = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !value.isEmpty
                    else {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(returning: value)
                }
            }
        }
    }
#endif
