import Foundation
import PresenterCore

/// App-wide preferences (Settings window, ⌘,), stored in UserDefaults. Per-deck settings live in the sidecar.
enum AppSettings {
    static let previousLandsOnFrameStartKey = "nav.previousLandsOnFrameStart"
    static let notesFontSizeKey = "notesFontSize"
    /// Presenting on a second display puts the presenter window into full screen; ending presenting leaves it.
    static let fullScreenWhilePresentingKey = "presenting.fullScreen"
    /// SPEC §4.3: URI links are ignored unless this is on.
    static let opensURILinksKey = "LecternOpenURILinks"

    static var fullScreenWhilePresenting: Bool {
        UserDefaults.standard.object(forKey: fullScreenWhilePresentingKey) as? Bool ?? true
    }

    static var navigationOptions: NavigationOptions {
        NavigationOptions(previousLandsOnFrameStart: UserDefaults.standard.bool(forKey: previousLandsOnFrameStartKey))
    }
}
