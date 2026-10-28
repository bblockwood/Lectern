import AppKit
import Observation
import PresenterCore

/// A connected display, identified by name plus pixel resolution so choices can be remembered (SPEC §6.1).
struct DisplayInfo: Identifiable, Hashable, Sendable {
    let id: String
    let displayID: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let pixelSize: PixelSize
    let isBuiltin: Bool
    let isMirrored: Bool
    let isMain: Bool

    var pixelArea: Int { pixelSize.width * pixelSize.height }

    static func key(name: String, pixelSize: PixelSize) -> String {
        "\(name)@\(pixelSize.width)x\(pixelSize.height)"
    }

    @MainActor
    init(screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        let displayID = CGDirectDisplayID(number?.uint32Value ?? 0)
        let pixels = PixelSize(width: CGDisplayPixelsWide(displayID), height: CGDisplayPixelsHigh(displayID))
        self.displayID = displayID
        self.name = screen.localizedName
        self.frame = screen.frame
        self.pixelSize = pixels
        self.isBuiltin = CGDisplayIsBuiltin(displayID) != 0
        self.isMirrored = CGDisplayIsInMirrorSet(displayID) != 0
        self.isMain = CGDisplayIsMain(displayID) != 0
        self.id = DisplayInfo.key(name: screen.localizedName, pixelSize: pixels)
    }

    /// For tests and previews.
    init(id: String, name: String, pixelSize: PixelSize, isBuiltin: Bool, isMirrored: Bool = false, isMain: Bool = false) {
        self.id = id
        self.displayID = 0
        self.name = name
        self.frame = CGRect(origin: .zero, size: pixelSize.cgSize)
        self.pixelSize = pixelSize
        self.isBuiltin = isBuiltin
        self.isMirrored = isMirrored
        self.isMain = isMain
    }
}

enum DisplayRole: String, Codable, Sendable {
    case presenter
    case audience
}

struct DisplayAssignment: Equatable, Sendable {
    var presenter: DisplayInfo? = nil
    var audience: DisplayInfo? = nil
    /// Single display: the audience view is a resizable window or hidden (SPEC §6.1).
    var isRehearsal: Bool { audience == nil }
}

/// Pure assignment logic: remembered roles win, otherwise built-in = presenter and the largest other display = audience.
enum DisplayAssigner {
    static func assign(displays: [DisplayInfo], remembered: [String: DisplayRole]) -> DisplayAssignment {
        guard let first = displays.first else { return DisplayAssignment() }
        guard displays.count > 1 else { return DisplayAssignment(presenter: first, audience: nil) }

        let rememberedPresenter = displays.first { remembered[$0.id] == .presenter }
        let rememberedAudience = displays.first { remembered[$0.id] == .audience }
        if let p = rememberedPresenter, let a = rememberedAudience, p != a {
            return DisplayAssignment(presenter: p, audience: a)
        }
        let presenter = rememberedPresenter
            ?? displays.first(where: { $0 != rememberedAudience && $0.isBuiltin })
            ?? displays.first(where: { $0 != rememberedAudience && $0.isMain })
            ?? displays.first(where: { $0 != rememberedAudience })
            ?? first
        let others = displays.filter { $0 != presenter }
        let audience = (rememberedAudience != presenter ? rememberedAudience : nil)
            ?? others.max { $0.pixelArea < $1.pixelArea }
        return DisplayAssignment(presenter: presenter, audience: audience)
    }
}

/// Tracks connected screens, remembers roles per display, and reports hot-plug changes (SPEC §6.1).
@MainActor
@Observable
final class DisplayManager {
    private static let defaultsKey = "displayRoles"

    private(set) var displays: [DisplayInfo] = []
    private(set) var assignment = DisplayAssignment()
    private(set) var remembered: [String: DisplayRole] = [:]
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var observer: NSObjectProtocol?

    var hasMirroring: Bool { displays.contains { $0.isMirrored } }

    init() {
        if let stored = UserDefaults.standard.dictionary(forKey: DisplayManager.defaultsKey) as? [String: String] {
            remembered = stored.compactMapValues(DisplayRole.init(rawValue:))
        }
        refresh()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let before = self.assignment
                self.refresh()
                if self.assignment != before { self.onChange?() }
            }
        }
    }

    func refresh() {
        displays = NSScreen.screens.map(DisplayInfo.init(screen:))
        assignment = DisplayAssigner.assign(displays: displays, remembered: remembered)
    }

    /// Swap presenter and audience (⌘D) and remember the choice for these displays.
    func swap() {
        guard let presenter = assignment.presenter, let audience = assignment.audience else { return }
        remembered[presenter.id] = .audience
        remembered[audience.id] = .presenter
        UserDefaults.standard.set(remembered.mapValues(\.rawValue), forKey: DisplayManager.defaultsKey)
        refresh()
        onChange?()
    }

    func screen(for display: DisplayInfo?) -> NSScreen? {
        guard let display else { return nil }
        return NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == display.displayID
        }
    }

    static func openDisplaySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
