import SwiftUI
import UniformTypeIdentifiers

/// The deck chooser in its own window (feedback round 3, like iWork's chooser): open a PDF, drop one, or pick a
/// recent. Scrolls when the window is short, so the title never crops.
struct WelcomeView: View {
    let model: AppModel

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 24) {
                    Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSApp.applicationIconImage)
                        .resizable().interpolation(.high)
                        .frame(width: 128, height: 128)
                    Text("Lectern").font(.system(size: 44, weight: .semibold))
                    Text("Drop a PDF here, or open one.").font(.system(size: Theme.body)).foregroundStyle(.secondary)
                    Button("Open PDF…") { model.openPanel() }
                        .keyboardShortcut("o", modifiers: .command)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    if !model.recents.urls.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Recent").font(.system(size: Theme.body, weight: .semibold)).foregroundStyle(.secondary)
                            ForEach(model.recents.urls, id: \.self) { url in
                                Button {
                                    model.open(url: url)
                                } label: {
                                    HStack {
                                        Image(systemName: "doc.richtext")
                                        VStack(alignment: .leading) {
                                            Text(url.lastPathComponent).font(.system(size: Theme.body))
                                            Text(url.deletingLastPathComponent().path).font(.system(size: Theme.small)).foregroundStyle(.tertiary).lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu { Button("Remove from Recents") { model.recents.remove(url) } }
                            }
                        }
                        .frame(maxWidth: 520)
                        .padding()
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                    }
                    Text("→ / Space / click next build · ← previous · ⇧→ next frame · ⌥⌘P present · ? for every shortcut")
                        .font(.system(size: Theme.small)).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24).padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height)   // centred when it fits, scrollable when it does not
            }
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { $0.pathExtension.lowercased() == "pdf" }) else { return false }
            model.open(url: url)
            return true
        }
    }
}
