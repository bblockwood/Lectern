import SwiftUI
import UIKit

/// What the iPad screen shows: the counter, controls, the live scene list and the event log.
struct PresenterView: View {
    @State private var model = SpikeModel.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Shared counter") {
                    HStack(spacing: 24) {
                        Button { model.counter -= 1 } label: { Label("−1", systemImage: "minus.circle.fill") }
                        Text("\(model.counter)")
                            .font(.system(size: 64, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                        Button { model.counter += 1 } label: { Label("+1", systemImage: "plus.circle.fill") }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .labelStyle(.titleOnly)
                    .padding(.vertical, 8)
                }

                Section("Connected window scenes") {
                    ForEach(model.windowScenes, id: \.session.persistentIdentifier) { scene in
                        SceneRow(scene: scene)
                    }
                    Button("Refresh") { model.record("manual refresh") }
                }

                Section("Second path (for Stage Manager / extended desktop)") {
                    Button("Open audience window (application scene)") { model.requestAudienceWindow() }
                    Button("Request external-display-role scene explicitly") { model.requestExternalRoleScene() }
                    Text("With Stage Manager on and an external display in extended-desktop mode, drag the audience window onto the external display. The explicit request is expected to fail; it logs what iOS says.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Events (newest last)") {
                    ForEach(Array(model.events.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Spike A: external display")
        }
    }
}

private struct SceneRow: View {
    let scene: UIWindowScene

    var body: some View {
        let isExternal = scene.session.role == .windowExternalDisplayNonInteractive
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(scene.session.configuration.name ?? "?").bold()
                if isExternal {
                    Text("EXTERNAL")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                }
                Spacer()
                Text(scene.activationState.shortName).foregroundStyle(.secondary)
            }
            Text("role: \(scene.session.role.shortName)")
            Text("screen bounds: \(Int(scene.screen.bounds.width))×\(Int(scene.screen.bounds.height)) pt @\(scene.screen.scale, specifier: "%.1f")x, native \(Int(scene.screen.nativeBounds.width))×\(Int(scene.screen.nativeBounds.height)) px")
            Text("scene bounds: \(Int(scene.effectiveGeometry.coordinateSpace.bounds.width))×\(Int(scene.effectiveGeometry.coordinateSpace.bounds.height)) pt, mirrors another screen: \(scene.screen.mirrored == nil ? "no" : "yes")")
            Text("screen modes: \(scene.screen.availableModes.map { "\(Int($0.size.width))×\(Int($0.size.height))" }.joined(separator: ", "))")
        }
        .font(.system(.footnote, design: .monospaced))
    }
}
