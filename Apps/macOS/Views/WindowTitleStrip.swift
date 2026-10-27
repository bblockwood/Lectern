import AppKit
import SwiftUI

/// A centred window title (with the document's icon when there is one) drawn in the title bar area of a window
/// set up by `NSWindow.useCentredTitleStrip()`. Wrap a window's root view in `.centredTitleStrip(...)`: the
/// strip takes exactly the title bar's height (the top safe area) and vanishes in full screen, where the
/// title bar is gone.
struct WindowTitleStrip: View {
    let title: String
    let fileURL: URL?
    let height: CGFloat

    var body: some View {
        HStack(spacing: 6) {
            if let fileURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: fileURL.path))
                    .resizable().interpolation(.high)
                    .frame(width: 16, height: 16)
            }
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.85))
                .lineLimit(1)
        }
        .padding(.horizontal, 80)   // never under the traffic lights
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(Color.black)    // hides content that scrolls under the title bar
        .allowsHitTesting(false)    // the title bar underneath keeps window dragging
    }
}

extension View {
    /// Only the strip extends into the title bar; the content keeps to the safe area below it. (A ScrollView
    /// reaching under the title bar would get the system's scroll-edge backdrop, which cannot be rendered
    /// offscreen and so breaks the self-test's screenshots.)
    func centredTitleStrip(title: String, fileURL: URL?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                self
                WindowTitleStrip(title: title, fileURL: fileURL, height: geo.safeAreaInsets.top)
                    .ignoresSafeArea(edges: .top)
            }
        }
    }
}
