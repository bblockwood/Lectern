import Foundation
import PresenterCore

/// App-wide preferences (Settings window, ⌘,), stored in UserDefaults. Per-deck settings live in the sidecar.
enum AppSettings {
    static let previousLandsOnFrameStartKey = "nav.previousLandsOnFrameStart"
    static let notesFontSizeKey = "notesFontSize"
    /// Presenting puts the presenter window into full screen; ending presenting leaves it (not when the audience view
    /// is a window on this display, which full screen would hide).
    static let fullScreenWhilePresentingKey = "presenting.fullScreen"
    /// Overview: every build as its own thumbnail (expanded) rather than one per frame (collapsed).
    static let overviewShowsBuildsKey = "overview.showsBuilds"
    /// SPEC §4.3: URI links are ignored unless this is on.
    static let opensURILinksKey = "LecternOpenURILinks"

    static var fullScreenWhilePresenting: Bool {
        UserDefaults.standard.object(forKey: fullScreenWhilePresentingKey) as? Bool ?? true
    }

    static var navigationOptions: NavigationOptions {
        NavigationOptions(previousLandsOnFrameStart: UserDefaults.standard.bool(forKey: previousLandsOnFrameStartKey))
    }
}
