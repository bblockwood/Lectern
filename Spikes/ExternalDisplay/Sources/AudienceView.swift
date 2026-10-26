import SwiftUI
import UIKit

/// What the external display (or the draggable audience window) shows.
struct AudienceView: View {
    let kind: AudienceKind
    @State private var model = SpikeModel.shared

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                background.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text("\(model.counter)")
                        .font(.system(size: min(proxy.size.width, proxy.size.height) * 0.6, weight: .black, design: .rounded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.2)
                    Text("view \(Int(proxy.size.width))×\(Int(proxy.size.height)) pt")
                        .font(.title3.monospaced())
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        // The external scene has a safe-area inset even though nothing is there; an audience surface must fill the screen.
        .ignoresSafeArea()
    }

    private var title: String {
        switch kind {
        case .externalDisplayScene: "AUDIENCE: external display scene (non-interactive)"
        case .applicationWindow: "AUDIENCE: application window (drag to external display)"
        }
    }

    private var background: Color {
        switch kind {
        case .externalDisplayScene: Color(red: 0.85, green: 0.35, blue: 0.05)
        case .applicationWindow: Color(red: 0.35, green: 0.1, blue: 0.7)
        }
    }
}
