import Foundation
import PresenterCore

/// App-wide preferences (Settings window, ⌘,), stored in UserDefaults. Per-deck settings live in the sidecar.
enum AppSettings {
    static let previousLandsOnFrameStartKey = "nav.previousLandsOnFrameStart"
    static let notesFontSizeKey = "notesFontSize"
    /// Presenting or rehearsing puts the presenter window into full screen; ending leaves it. With one display the
    /// audience window floats above the full-screen presenter (feedback round 8).
    static let fullScreenWhilePresentingKey = "presenting.fullScreen"
    /// The last countdown set in the timer's popover, in seconds: what "Count down from" offers next time.
    static let lastCountdownKey = "timer.lastCountdown"
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
