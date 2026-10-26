import CoreGraphics
import Foundation

/// Beamer `show notes on second screen` detection (SPEC §5.1.4): the page is about twice as wide or twice
/// as tall as a slide. Confirmed once per deck by the user; the answer lives in the sidecar.
public enum SecondScreenDetector {
    /// A guess at the layout, nil when the page looks like an ordinary slide. `hint` is pdfpc's NotesPosition
    /// (`left`, `right`, `top`, `bottom`, `none`) when the deck carries it.
    public static func detect(pageSize: CGSize, hint: String? = nil) -> NotesSplit? {
        guard pageSize.width > 0, pageSize.height > 0 else { return nil }
        let aspect = pageSize.width / pageSize.height
        if let hint, let split = NotesSplit(rawValue: hint), split != .none {
            switch split {
            case .left, .right: return aspect > 2.3 ? split : nil
            case .top, .bottom: return aspect < 0.95 ? split : nil
            case .none: return nil
            }
        }
        if aspect > 2.3 { return .right }     // 4:3 → 2.67, 16:9 → 3.56
        if aspect < 0.95 { return .bottom }   // 4:3 → 0.67, 16:9 → 0.89
        return nil
    }
}
