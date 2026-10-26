import Foundation

/// Keeps the displays awake while presenting (SPEC §6.1). Released on deinit.
final class PowerAssertion {
    private let activity: NSObjectProtocol

    init(reason: String) {
        activity = ProcessInfo.processInfo.beginActivity(options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated], reason: reason)
    }

    deinit {
        ProcessInfo.processInfo.endActivity(activity)
    }
}
