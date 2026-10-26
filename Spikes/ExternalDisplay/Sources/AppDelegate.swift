import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SpikeModel.shared.record("app didFinishLaunching supportsMultipleScenes=\(application.supportsMultipleScenes)")
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        let activityTypes = options.userActivities.map(\.activityType)
        let restored = connectingSceneSession.stateRestorationActivity?.activityType
        SpikeModel.shared.record("app configurationForConnecting role=\(role.shortName) activities=\(activityTypes) restored=\(restored ?? "nil")")

        // The Info.plist manifest already lists these; naming one here picks which entry to use.
        switch role {
        case .windowExternalDisplayNonInteractive:
            return UISceneConfiguration(name: "Audience", sessionRole: role)
        default:
            let wantsAudience = activityTypes.contains(SpikeActivity.audienceWindow)
                || restored == SpikeActivity.audienceWindow
            return UISceneConfiguration(name: wantsAudience ? "AudienceWindow" : "Presenter", sessionRole: role)
        }
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        SpikeModel.shared.record("app didDiscardSceneSessions \(sceneSessions.map { $0.role.shortName })")
    }
}
