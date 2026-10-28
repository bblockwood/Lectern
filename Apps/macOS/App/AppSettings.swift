import Foundation
import PresenterCore

/// App-wide preferences (Settings window, ⌘,), stored in UserDefaults. Per-deck settings live in the sidecar.
enum AppSettings {
    static let previousLandsOnFrameStartKey = "nav.previousLandsOnFrameStart"
    static let notesFontSizeKey = "notesFontSize"
    /// SPEC §4.3: URI links are ignored unless this is on.
    static let opensURILinksKey = "LecternOpenURILinks"

    static var navigationOptions: NavigationOptions {
        NavigationOptions(previousLandsOnFrameStart: UserDefaults.standard.bool(forKey: previousLandsOnFrameStartKey))
    }
}
