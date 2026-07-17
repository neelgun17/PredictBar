import Foundation
import UserNotifications

/// Watchdog for long-uptime memory growth.
///
/// Samples the app's physical memory footprint (the same number Activity Monitor's
/// "Memory" column shows) every 30 minutes and writes it to the unified log, so a
/// slow leak surfaces in `log show --predicate 'subsystem == "com.predictbar.app"'`
/// instead of going unnoticed for weeks. Posts a one-time notification if the
/// footprint crosses the warning threshold.
final class MemoryMonitor {
    static let shared = MemoryMonitor()

    /// A menu bar app anywhere near this footprint is misbehaving.
    private let warningThresholdBytes: UInt64 = 500 * 1024 * 1024
    private let sampleInterval: TimeInterval = 30 * 60

    private var timer: Timer?
    private var didWarn = false

    private init() {}

    /// Call from the main thread — the sampling timer needs its run loop.
    func start() {
        guard timer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: sampleInterval, repeats: true) { [weak self] _ in
            self?.sample()
        }
        timer.tolerance = 120
        self.timer = timer
        sample()
    }

    private func sample() {
        guard let footprint = Self.physicalFootprint() else { return }
        let mb = Int(footprint / 1_048_576)
        Log.app.info("Memory footprint: \(mb, privacy: .public) MB")

        guard footprint > warningThresholdBytes, !didWarn else { return }
        didWarn = true
        let thresholdMB = Int(warningThresholdBytes / 1_048_576)
        Log.app.fault("Memory footprint \(mb, privacy: .public) MB exceeds \(thresholdMB, privacy: .public) MB — possible leak. Capture `footprint PredictBar` output and investigate.")

        // Notifications only work from a signed .app bundle (same guard as alerts).
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let content = UNMutableNotificationContent()
        content.title = "PredictBar Memory Warning"
        content.body = "PredictBar is using \(mb) MB of memory. Restarting the app is recommended."
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    /// phys_footprint from task_vm_info — matches Activity Monitor's "Memory" column,
    /// including compressed and swapped pages that RSS misses.
    static func physicalFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }
}
