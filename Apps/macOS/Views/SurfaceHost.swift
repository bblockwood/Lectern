import AppKit
import SwiftUI

/// Embeds an existing `SlideSurfaceView` in SwiftUI. The view is owned by its `SurfaceController`.
struct SurfaceHost: NSViewRepresentable {
    let view: SlideSurfaceView

    func makeNSView(context: Context) -> SlideSurfaceView { view }
    func updateNSView(_ nsView: SlideSurfaceView, context: Context) {}
}
