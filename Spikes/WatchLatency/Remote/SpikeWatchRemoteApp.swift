import SwiftUI

@main
struct SpikeWatchRemoteApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = LatencyModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .task { model.start() }
        }
        .onChange(of: scenePhase) { _, phase in
            model.logPhase(phase)
        }
    }
}
