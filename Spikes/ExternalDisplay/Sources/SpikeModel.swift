import Observation
import UIKit

/// Shared state for every scene: the counter, plus a running log of lifecycle events
/// and a tick that bumps whenever the set of scenes may have changed.
@MainActor @Observable
final class SpikeModel {
    static let shared = SpikeModel()

    var counter = 0
    private(set) var events: [String] = []
    /// Incremented on every scene lifecycle event so views that list scenes re-read them.
    private(set) var sceneTick = 0

    private let clock = Date()
    private static let timeFormat: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    func record(_ message: String) {
        spikeLog.notice("\(message, privacy: .public)")
        events.append("\(Self.timeFormat.string(from: Date())) \(message)")
        if events.count > 60 { events.removeFirst(events.count - 60) }
        sceneTick += 1
    }

    /// Every window scene the app currently has, newest last.
    var windowScenes: [UIWindowScene] {
        _ = sceneTick
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { $0.session.persistentIdentifier < $1.session.persistentIdentifier }
    }

    // MARK: Second path: ask for scenes explicitly.

    /// Ask the system to create (or activate) a scene with the non-interactive external display role.
    /// Expected to fail unless a display is connected; the point is to log what iOS says.
    func requestExternalRoleScene() {
        let request = UISceneSessionActivationRequest(role: .windowExternalDisplayNonInteractive)
        record("request: activateSceneSession(role: externalDisplayNonInteractive)")
        UIApplication.shared.activateSceneSession(for: request) { error in
            Task { @MainActor in
                SpikeModel.shared.record("request FAILED: \(error.localizedDescription) (\((error as NSError).domain) \((error as NSError).code))")
            }
        }
    }

    /// Open an ordinary application window that shows the audience view. With Stage Manager and an
    /// external display in extended-desktop mode, the user can drag this window onto the external display.
    func requestAudienceWindow() {
        let activity = NSUserActivity(activityType: SpikeActivity.audienceWindow)
        activity.title = "Audience window"
        var request = UISceneSessionActivationRequest(role: .windowApplication)
        request.userActivity = activity
        record("request: activateSceneSession(role: application, activity: audience-window)")
        UIApplication.shared.activateSceneSession(for: request) { error in
            Task { @MainActor in
                SpikeModel.shared.record("request FAILED: \(error.localizedDescription) (\((error as NSError).domain) \((error as NSError).code))")
            }
        }
    }
}

enum SpikeActivity {
    static let audienceWindow = "dev.lectern.spike.audience-window"
}

extension UISceneSession.Role {
    var shortName: String {
        switch self {
        case .windowApplication: "application"
        case .windowExternalDisplayNonInteractive: "externalDisplayNonInteractive"
        default: rawValue
        }
    }
}

extension UIScene.ActivationState {
    var shortName: String {
        switch self {
        case .unattached: "unattached"
        case .foregroundActive: "foregroundActive"
        case .foregroundInactive: "foregroundInactive"
        case .background: "background"
        @unknown default: "unknown(\(rawValue))"
        }
    }
}

extension UIWindowScene {
    /// One-line description used in logs and on screen.
    var spikeDescription: String {
        let s = screen
        let b = s.bounds
        let n = s.nativeBounds
        let mirror = s.mirrored == nil ? "" : " mirrorsAnother"
        return "\(session.configuration.name ?? "?") role=\(session.role.shortName) state=\(activationState.shortName) "
            + "screen=\(Int(b.width))x\(Int(b.height))@\(s.scale)x native=\(Int(n.width))x\(Int(n.height))\(mirror) "
            + "mode=\(s.currentMode.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "nil") "
            + "modes=[\(s.availableModes.map { "\(Int($0.size.width))x\(Int($0.size.height))" }.joined(separator: ","))] "
            + "id=\(session.persistentIdentifier.suffix(6))"
    }
}

extension SpikeModel {
    /// Handles `lectern-spike://add?n=<int>`, `lectern-spike://set?n=<int>`, `lectern-spike://window`.
    func handle(urls: [URL]) {
        for url in urls {
            let n = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "n" }?.value.flatMap(Int.init) ?? 1
            switch url.host() {
            case "add": counter += n
            case "set": counter = n
            case "window": requestAudienceWindow()
            default: break
            }
            record("url \(url.absoluteString) → counter=\(counter)")
        }
    }
}
