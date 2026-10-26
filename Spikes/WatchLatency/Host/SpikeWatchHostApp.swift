import SwiftUI

@main
struct SpikeWatchHostApp: App {
    @State private var model = HostModel()

    init() {
        // Line-buffer stdout so a terminal launch (or a redirect to a file) shows rows as they happen.
        setvbuf(stdout, nil, _IOLBF, 0)
    }

    var body: some Scene {
        WindowGroup("Lectern Spike Host") {
            HostView(model: model)
                .task { model.start() }
        }
        .defaultSize(width: 720, height: 520)
    }
}

struct HostView: View {
    let model: HostModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Transport A: TCP via iPhone relay") {
                VStack(alignment: .leading) {
                    Text(model.tcpState)
                    Text("\(model.tcpClients) relay(s) connected, \(model.tcpPings) pings echoed")
                    if let summary = model.lastSummary[.aViaMac] { Text("A: " + summary).bold() }
                    if let summary = model.lastSummary[.aPhoneOnly] { Text("A′: " + summary).bold() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Transport B: Bluetooth LE peripheral") {
                VStack(alignment: .leading) {
                    Text(model.bleState)
                    Text("\(model.bleSubscribers) central(s) subscribed, \(model.blePings) pings echoed")
                    if let summary = model.lastSummary[.bBluetooth] { Text("B: " + summary).bold() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("CSV: \(model.csvDirectory)").font(.caption).textSelection(.enabled)
            List(model.log) { line in
                Text(line.text).font(.system(.caption, design: .monospaced))
            }
        }
        .padding()
    }
}
