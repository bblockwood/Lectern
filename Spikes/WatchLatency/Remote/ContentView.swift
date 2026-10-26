import SwiftUI

struct ContentView: View {
    @Bindable var model: LatencyModel

    var body: some View {
        TabView {
            mainPage
            logPage
        }
        .tabViewStyle(.verticalPage)
    }

    private var mainPage: some View {
        ScrollView {
            VStack(spacing: 8) {
                Button {
                    model.press()
                } label: {
                    Text("Next")
                        .font(.system(size: 34, weight: .bold))
                        .frame(maxWidth: .infinity, minHeight: 72)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .handGestureShortcut(.primaryAction)

                Picker("Transport", selection: $model.transport) {
                    ForEach(LatencyModel.Transport.allCases) { transport in
                        Text(transport.title).tag(transport)
                    }
                }
                .pickerStyle(.navigationLink)

                statsBlock

                Text(model.connectionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack {
                    Button(model.autorunRemaining > 0 ? "Stop (\(model.autorunRemaining))" : "Auto \(model.autorunTotal)") {
                        if model.autorunRemaining > 0 { model.stopAutorun() } else { model.startAutorun() }
                    }
                    Button("Reset", role: .destructive) { model.resetCurrent() }
                }
                .font(.caption)
            }
        }
    }

    private var statsBlock: some View {
        let stats = model.currentStats
        return VStack(alignment: .leading, spacing: 2) {
            Text("n \(stats.count)  fail \(model.currentFailures)  in-flight \(model.inFlight)")
            Text("last \(ms(stats.last))  RTT")
            Text("med \(ms(stats.median))  p95 \(ms(stats.p95))")
            Text("one-way ≈ \(ms(stats.median.map { $0 / 2 })) / \(ms(stats.p95.map { $0 / 2 }))")
            if let reconnect = model.lastReconnectMs {
                Text("reconnect \(ms(reconnect))")
            }
        }
        .font(.system(.caption2, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ms(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.0f ms", value)
    }

    private var logPage: some View {
        List(Array(model.log.reversed().enumerated()), id: \.offset) { _, line in
            Text(line).font(.system(size: 11, design: .monospaced))
        }
    }
}
