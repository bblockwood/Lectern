import PresenterCore
import SwiftUI
import UniformTypeIdentifiers

/// The presenter window's content: the deck layout or the welcome screen, banners, and the status bar (SPEC §6.2).
struct PresenterRootView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                if let presentation = model.presentation {
                    if model.overviewVisible {
                        OverviewLayout(model: model, presentation: presentation)
                            .id(ObjectIdentifier(presentation))
                    } else {
                        PresenterLayout(model: model, presentation: presentation)
                            .id(ObjectIdentifier(presentation))
                    }
                } else {
                    WelcomeView(model: model)
                }
                BannerStack(model: model)
                if !model.jumpBuffer.isEmpty {
                    VStack {
                        Spacer()
                        HStack {
                            Text("Go to frame \(Text(model.jumpBuffer).bold()) ⏎")
                            Spacer()
                        }
                        .font(.title2)
                        .padding(10)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                        .padding(16)
                    }
                }
            }
            StatusBar(model: model)
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

struct WelcomeView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Lectern").font(.system(size: 40, weight: .semibold))
            Text("Drop a PDF here, or open one.").foregroundStyle(.secondary)
            Button("Open PDF…") { model.openPanel() }
                .keyboardShortcut("o", modifiers: .command)
                .buttonStyle(.borderedProminent)
            if !model.recents.urls.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent").font(.headline).foregroundStyle(.secondary)
                    ForEach(model.recents.urls, id: \.self) { url in
                        Button {
                            model.open(url: url)
                        } label: {
                            HStack {
                                Image(systemName: "doc.richtext")
                                VStack(alignment: .leading) {
                                    Text(url.lastPathComponent)
                                    Text(url.deletingLastPathComponent().path).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { Button("Remove from Recents") { model.recents.remove(url) } }
                    }
                }
                .frame(maxWidth: 480)
                .padding()
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
            Spacer()
            Text("→ / Space next build · ← previous · ⇧→ next frame · ⌥⌘P present · B black · T timer")
                .font(.caption).foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Current slide left; next preview and notes stacked on the right; both splits draggable and persisted.
struct PresenterLayout: View {
    let model: AppModel
    let presentation: Presentation
    @AppStorage("layout.horizontalFraction") private var horizontalFraction = 0.68
    @AppStorage("layout.verticalFraction") private var verticalFraction = 0.42

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                CurrentSlidePane(presentation: presentation)
                    .frame(width: max(200, geo.size.width * horizontalFraction))
                SplitHandle(axis: .horizontal) { delta in
                    horizontalFraction = min(0.85, max(0.3, horizontalFraction + delta / geo.size.width))
                }
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 4) {
                        PaneTitle(presentation.nextPage == nil ? "Next: end of deck" : "Next")
                        SurfaceHost(view: presentation.previewSurface.view)
                    }
                    .frame(height: max(120, geo.size.height * verticalFraction))
                    SplitHandle(axis: .vertical) { delta in
                        verticalFraction = min(0.8, max(0.15, verticalFraction + delta / geo.size.height))
                    }
                    NotesPane(model: model, presentation: presentation)
                }
            }
        }
        .padding(8)
    }
}

/// The presenter's current slide with the PREVIEW banner while browsing and the APPENDIX badge (SPEC §4.2, §6.3).
struct CurrentSlidePane: View {
    let presentation: Presentation

    var body: some View {
        ZStack(alignment: .top) {
            SurfaceHost(view: presentation.currentSurface.view)
            HStack(alignment: .top) {
                if presentation.state.isBrowsing {
                    Text("PREVIEW: audience sees Frame \(presentation.committedFrame.label)")
                        .font(.headline).padding(8).background(.orange, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.black)
                }
                Spacer()
                if presentation.isInAppendix {
                    Text("APPENDIX")
                        .font(.caption.weight(.heavy)).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.purple, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.white)
                }
            }
            .padding(8)
        }
    }
}

struct PaneTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 2)
    }
}

/// Notes for the presenter's page (SPEC §5.2): Markdown text from the merged sources, the rendered notes
/// half of a second-screen deck, or an inline editor that writes to the sidecar.
struct NotesPane: View {
    let model: AppModel
    let presentation: Presentation
    @State private var draft = ""
    @State private var editingPage: Int? = nil

    var body: some View {
        let page = presentation.state.presenterPage
        let note = presentation.currentNote
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                PaneTitle(note.map { "Notes · \($0.source.displayName)" } ?? "Notes")
                Spacer()
                if model.notesEditing {
                    Button("Done") { finishEditing(page: page) }.keyboardShortcut(.defaultAction).controlSize(.small)
                } else {
                    Button("Edit (⌘E)") { model.setNotesEditing(true) }.controlSize(.small).buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05))
                if model.notesEditing {
                    TextEditor(text: $draft)
                        .font(.system(size: model.notesFontSize))
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .onAppear { draft = presentation.userNoteText(forPage: page); editingPage = page }
                        .onChange(of: page) { _, newPage in
                            if let editingPage { presentation.setUserNote(draft, forPage: editingPage) }
                            draft = presentation.userNoteText(forPage: newPage)
                            editingPage = newPage
                        }
                        .onDisappear { if let editingPage { presentation.setUserNote(draft, forPage: editingPage) } }
                } else if let note {
                    ScrollView {
                        MarkdownNoteView(text: note.text, fontSize: model.notesFontSize)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                } else if presentation.notesSplit != .none {
                    SurfaceHost(view: presentation.notesSurface.view).padding(4)
                } else {
                    Text("No notes for this frame. ⌘E to write some.")
                        .foregroundStyle(.tertiary).multilineTextAlignment(.center).padding()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .id(model.notesFontTick)
    }

    private func finishEditing(page: Int) {
        presentation.setUserNote(draft, forPage: editingPage ?? page)
        model.setNotesEditing(false)
    }
}

/// Paragraphs, bullets and numbered items; inline emphasis and code via Foundation's Markdown parser.
struct MarkdownNoteView: View {
    let text: String
    let fontSize: Double

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.5) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let body):
                    inline(body)
                case .bullet(let body, let level):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").padding(.leading, CGFloat(level) * fontSize)
                        inline(body)
                    }
                case .numbered(let body, let number):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(number).").monospacedDigit()
                        inline(body)
                    }
                }
            }
        }
        .font(.system(size: fontSize))
        .textSelection(.enabled)
    }

    private func inline(_ body: String) -> Text {
        if let attributed = try? AttributedString(markdown: body, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(body)
    }
}

struct SplitHandle: View {
    enum Axis { case horizontal, vertical }
    let axis: Axis
    let onDrag: (CGFloat) -> Void
    @State private var lastTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: axis == .horizontal ? 6 : nil, height: axis == .vertical ? 6 : nil)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { (axis == .horizontal ? NSCursor.resizeLeftRight : NSCursor.resizeUpDown).push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let current = axis == .horizontal ? value.translation.width : value.translation.height
                    onDrag(current - lastTranslation)
                    lastTranslation = current
                }
                .onEnded { _ in lastTranslation = 0 })
    }
}

struct BannerStack: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 6) {
            if let presentation = model.presentation, let split = presentation.pendingSplitQuestion {
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.split.2x1")
                    Text("This deck looks like Beamer second-screen notes (notes \(split.rawValue)). Show the audience only the slide half?")
                    Button("Yes, split it") { presentation.answerSplitQuestion(useSplit: true) }
                    Button("No, full page") { presentation.answerSplitQuestion(useSplit: false) }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color.cyan.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
            }
            ForEach(model.banners) { banner in
                HStack(spacing: 12) {
                    Image(systemName: icon(for: banner.kind))
                    Text(banner.text).lineLimit(3)
                    if let action = banner.action, let title = banner.actionTitle {
                        Button(title) { model.run(action) }
                    }
                    Spacer(minLength: 0)
                    Button { model.dismiss(banner) } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(10)
                .background(color(for: banner.kind).opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 12)
        .animation(.easeInOut(duration: 0.15), value: model.banners)
    }

    private func icon(for kind: Banner.Kind) -> String {
        switch kind {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.octagon"
        }
    }

    private func color(for kind: Banner.Kind) -> Color {
        switch kind {
        case .info: .cyan
        case .warning: .orange
        case .error: .red
        }
    }
}

/// Frame label and total, build x/y, elapsed, wall clock, remaining vs target, audience indicator (SPEC §6.2).
struct StatusBar: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 20) {
                if let presentation = model.presentation {
                    let frame = presentation.currentFrame
                    Text("Frame \(frame.label) / \(presentation.frameCount)").font(.system(.title3, design: .rounded).weight(.semibold))
                    if frame.buildCount > 1 {
                        Text("Build \(presentation.currentBuild + 1)/\(frame.buildCount)").foregroundStyle(.secondary)
                    }
                    if presentation.isInAppendix {
                        Text("APPENDIX").font(.caption.weight(.heavy)).foregroundStyle(.purple)
                    } else if let left = presentation.mainTalkFramesLeft {
                        Text("\(left) left").foregroundStyle(.secondary)
                    }
                    Spacer()
                    timerSection(presentation: presentation, now: context.date)
                    Spacer()
                    audienceIndicator(presentation: presentation)
                } else {
                    Text("No deck open").foregroundStyle(.secondary)
                    Spacer()
                    Text(context.date, format: .dateTime.hour().minute()).monospacedDigit()
                }
            }
            .font(.system(.title3, design: .rounded))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.06))
        }
    }

    @ViewBuilder
    private func timerSection(presentation: Presentation, now: Date) -> some View {
        let timer = presentation.state.timer
        let elapsed = timer.elapsed(at: now)
        HStack(spacing: 16) {
            Label(format(elapsed), systemImage: timer.isRunning ? "timer" : "pause.circle")
                .monospacedDigit()
                .foregroundStyle(timer.isRunning ? .primary : .secondary)
            Text(now, format: .dateTime.hour().minute()).monospacedDigit().foregroundStyle(.secondary)
            if let target = timer.target, let remaining = timer.remaining(at: now) {
                let pace = PaceIndicator.pace(framesDone: presentation.committedFrame.index, framesTotal: presentation.document.mainTalkFrameCount,
                                              elapsed: elapsed, target: target)
                Text((remaining < 0 ? "−" : "") + format(abs(remaining)) + " left")
                    .monospacedDigit()
                    .foregroundStyle(paceColor(pace, remaining: remaining))
            }
        }
    }

    private func audienceIndicator(presentation: Presentation) -> some View {
        let (text, color): (String, Color) = {
            switch presentation.state.audienceMode {
            case .live: return model.isPresenting ? ("LIVE", .green) : ("NOT PRESENTING", .gray)
            case .frozen: return ("FROZEN", .orange)
            case .black: return ("BLACK", .red)
            case .white: return ("WHITE", .red)
            }
        }()
        return HStack(spacing: 8) {
            if presentation.pointerMode { Text("POINTER").font(.caption.weight(.bold)).foregroundStyle(.red) }
            if presentation.drawMode { Text("DRAW").font(.caption.weight(.bold)).foregroundStyle(.orange) }
            if model.isPresenting && model.displays.assignment.audience == nil {
                Text("REHEARSAL").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(.body, design: .rounded).weight(.bold))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(color.opacity(0.25), in: Capsule())
                .foregroundStyle(color)
        }
    }

    private func paceColor(_ pace: Pace, remaining: TimeInterval) -> Color {
        if remaining < 0 { return .red }
        switch pace {
        case .ahead: return .green
        case .slightlyBehind: return .orange
        case .behind: return .red
        }
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}
