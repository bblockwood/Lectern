import SwiftUI
import UIKit

/// Logs every lifecycle callback with a tag so the two scene kinds can be told apart in the log.
@MainActor
protocol SpikeSceneLogging: AnyObject {
    var tag: String { get }
}

extension SpikeSceneLogging {
    func log(_ event: String, _ scene: UIScene) {
        let detail = (scene as? UIWindowScene)?.spikeDescription ?? "(not a window scene)"
        SpikeModel.shared.record("\(tag) \(event): \(detail)")
    }
}

/// The interactive scene on the iPad itself.
final class PresenterSceneDelegate: UIResponder, UIWindowSceneDelegate, SpikeSceneLogging {
    var window: UIWindow?
    let tag = "PRESENTER"

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        log("willConnect", scene)
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: PresenterView())
        self.window = window
        window.makeKeyAndVisible()
        SpikeModel.shared.handle(urls: connectionOptions.urlContexts.map(\.url))
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        SpikeModel.shared.handle(urls: URLContexts.map(\.url))
    }

    func sceneDidDisconnect(_ scene: UIScene) { log("didDisconnect", scene) }
    func sceneDidBecomeActive(_ scene: UIScene) { log("didBecomeActive", scene) }
    func sceneWillResignActive(_ scene: UIScene) { log("willResignActive", scene) }
    func sceneWillEnterForeground(_ scene: UIScene) { log("willEnterForeground", scene) }
    func sceneDidEnterBackground(_ scene: UIScene) { log("didEnterBackground", scene) }

    func windowScene(_ windowScene: UIWindowScene, didUpdateEffectiveGeometry previousEffectiveGeometry: UIWindowScene.Geometry) {
        log("didUpdateEffectiveGeometry", windowScene)
    }
}

/// Used for two configurations:
///  - "Audience": the system-created non-interactive external display scene.
///  - "AudienceWindow": an ordinary application scene we request ourselves, for the Stage Manager path.
final class AudienceSceneDelegate: UIResponder, UIWindowSceneDelegate, SpikeSceneLogging {
    var window: UIWindow?
    var tag: String { kind.tag }
    private var kind: AudienceKind = .externalDisplayScene

    /// Some callbacks (didUpdateEffectiveGeometry) arrive before willConnect, so derive the kind from the session every time.
    func log(_ event: String, _ scene: UIScene) {
        kind = scene.session.role == .windowExternalDisplayNonInteractive ? .externalDisplayScene : .applicationWindow
        let detail = (scene as? UIWindowScene)?.spikeDescription ?? "(not a window scene)"
        SpikeModel.shared.record("\(tag) \(event): \(detail)")
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        log("willConnect", scene)
        guard let windowScene = scene as? UIWindowScene else { return }
        if kind == .applicationWindow {
            // Keep the activity so the system restores this window as an audience window.
            session.stateRestorationActivity = connectionOptions.userActivities.first
                ?? NSUserActivity(activityType: SpikeActivity.audienceWindow)
        }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UIHostingController(rootView: AudienceView(kind: kind))
        self.window = window
        // Not makeKeyAndVisible: a non-interactive display scene should never take key status.
        window.isHidden = false
    }

    func stateRestorationActivity(for scene: UIScene) -> NSUserActivity? {
        kind == .applicationWindow ? NSUserActivity(activityType: SpikeActivity.audienceWindow) : nil
    }

    func sceneDidDisconnect(_ scene: UIScene) { log("didDisconnect", scene) }
    func sceneDidBecomeActive(_ scene: UIScene) { log("didBecomeActive", scene) }
    func sceneWillResignActive(_ scene: UIScene) { log("willResignActive", scene) }
    func sceneWillEnterForeground(_ scene: UIScene) { log("willEnterForeground", scene) }
    func sceneDidEnterBackground(_ scene: UIScene) { log("didEnterBackground", scene) }

    func windowScene(_ windowScene: UIWindowScene, didUpdateEffectiveGeometry previousEffectiveGeometry: UIWindowScene.Geometry) {
        log("didUpdateEffectiveGeometry", windowScene)
    }
}

enum AudienceKind: Sendable {
    case externalDisplayScene
    case applicationWindow

    var tag: String {
        switch self {
        case .externalDisplayScene: "AUDIENCE-EXT"
        case .applicationWindow: "AUDIENCE-WIN"
        }
    }
}
