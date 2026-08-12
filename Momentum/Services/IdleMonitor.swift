import Foundation
import IOKit

/// Polls HID idle time. No Accessibility permission required.
@MainActor
final class IdleMonitor {
    var idleThreshold: TimeInterval
    var onIdleStateChange: ((Bool) -> Void)?

    private var timer: Timer?
    private var isIdle = false

    init(idleThreshold: TimeInterval = 5 * 60) {
        self.idleThreshold = idleThreshold
    }

    func start() {
        stop()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if isIdle {
            isIdle = false
            onIdleStateChange?(false)
        }
    }

    private func tick() {
        let idleSeconds = Self.systemIdleSeconds()
        let nowIdle = idleSeconds >= idleThreshold
        guard nowIdle != isIdle else { return }
        isIdle = nowIdle
        onIdleStateChange?(nowIdle)
    }

    static func systemIdleSeconds() -> TimeInterval {
        var iterator: io_iterator_t = 0
        defer {
            if iterator != 0 {
                IOObjectRelease(iterator)
            }
        }

        let result = IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        )
        guard result == KERN_SUCCESS else { return 0 }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return 0 }
        defer { IOObjectRelease(entry) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = properties?.takeRetainedValue() as? [String: Any],
              let number = dict["HIDIdleTime"] as? UInt64
        else {
            return 0
        }

        // HIDIdleTime is in nanoseconds.
        return TimeInterval(number) / 1_000_000_000
    }
}
