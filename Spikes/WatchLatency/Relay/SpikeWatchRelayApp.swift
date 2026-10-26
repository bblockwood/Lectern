import SwiftUI

@main
struct SpikeWatchRelayApp: App {
    @State private var model = RelayModel()

    var body: some Scene {
        WindowGroup {
            RelayView(model: model)
                .task { model.start() }
        }
    }
}

struct RelayView: View {
    let model: RelayModel

    var body: some View {
        NavigationStack {
            List {
                Section("Mac host (Transport A)") {
                    LabeledContent("Link", value: model.hostConnected ? "connected" : "not connected")
                    Text(model.hostState).font(.caption)
                    LabeledContent("Forwarded to Mac", value: "\(model.forwarded)")
                }
                Section("Watch (WatchConnectivity)") {
                    LabeledContent("Reachable", value: model.wcReachable ? "yes" : "no")
                    Text(model.wcState).font(.caption)
                    LabeledContent("Echoed on phone (A′)", value: "\(model.phoneEchoed)")
                }
                Section("Log") {
                    ForEach(model.log) { line in
                        Text(line.text).font(.system(.caption2, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Lectern Spike Relay")
        }
    }
}
