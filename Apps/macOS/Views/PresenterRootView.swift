import PresenterCore
import PresenterProtocol
import SwiftUI
import UniformTypeIdentifiers

/// Type sizes for the presenter chrome. Everything here is read at a glance from behind a lectern, so it is
/// larger than ordinary Mac UI (feedback round 1).
enum Theme {
    static let status: CGFloat = 30
    static let statusSecondary: CGFloat = 24
    static let paneTitle: CGFloat = 16
    static let body: CGFloat = 18
    static let small: CGFloat = 14
    static let notesDefault: Double = 22
    static let paneSpacing: CGFloat = 6

    /// Largest size with `aspect` (width / height) that fits in `bounds`.
    static func fit(aspect: CGFloat, in bounds: CGSize) -> CGSize {
        guard aspect > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let width = min(bounds.width, bounds.height * aspect)
        return CGSize(width: width.rounded(.down), height: (width / aspect).rounded(.down))
    }
}

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
                        .font(.system(size: 28))
                        .padding(12)
                        .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 8))
                        .padding(16)
                    }
                }
                if model.shortcutOverlayVisible {
                    ShortcutOverlay().transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.12), value: model.shortcutOverlayVisible)
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
            Spacer()
            Text("→ / Space next build · ← previous · ⇧→ next frame · ⌥⌘P present · hold ⌘ for every shortcut")
                .font(.system(size: Theme.small)).foregroundStyle(.tertiary)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Current slide left; next preview and notes stacked on the right; both splits draggable and persisted.
/// Both slide panes start with a title of the same height and pin their slide to the top, so the top edges of
/// the current and next slides line up (feedback round 1).
struct PresenterLayout: View {
    let model: AppModel
    let presentation: Presentation
    @AppStorage("layout.horizontalFraction") private var horizontalFraction = 0.68
    @AppStorage("layout.verticalFraction") private var verticalFraction = 0.42

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 0) {
                CurrentSlidePane(model: model, presentation: presentation)
                    .frame(width: max(200, geo.size.width * horizontalFraction))
                SplitHandle(axis: .horizontal) { delta in
                    horizontalFraction = min(0.85, max(0.3, horizontalFraction + delta / geo.size.width))
                }
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: Theme.paneSpacing) {
                        PaneTitle(presentation.nextPage == nil ? "Next: end of deck" : "Next")
                        FittedSurface(view: presentation.previewSurface.view, aspect: presentation.nextSlideAspectRatio)
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

/// A surface at the largest size with `aspect` that fits its area, pinned to the top and centred horizontally.
struct FittedSurface: View {
    let view: SlideSurfaceView
    let aspect: CGFloat

    var body: some View {
        GeometryReader { geo in
            let fitted = Theme.fit(aspect: aspect, in: geo.size)
            SurfaceHost(view: view)
                .frame(width: fitted.width, height: fitted.height)
                .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// The presenter's current slide with the PREVIEW banner while browsing and the APPENDIX badge (SPEC §4.2, §6.3),
/// and the Laser / Pen / Clear buttons directly under it (feedback round 1).
struct CurrentSlidePane: View {
    let model: AppModel
    let presentation: Presentation
    private let barHeight: CGFloat = 44

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paneSpacing) {
            PaneTitle("Current")
            GeometryReader { geo in
                let available = CGSize(width: geo.size.width, height: max(1, geo.size.height - barHeight - Theme.paneSpacing))
                let fitted = Theme.fit(aspect: presentation.currentSlideAspectRatio, in: available)
                VStack(spacing: Theme.paneSpacing) {
                    ZStack(alignment: .top) {
                        SurfaceHost(view: presentation.currentSurface.view)
                        HStack(alignment: .top) {
                            if presentation.state.isBrowsing {
                                Text("PREVIEW: audience sees Frame \(presentation.committedFrame.label)")
                                    .font(.system(size: Theme.body, weight: .semibold)).padding(8)
                                    .background(.orange, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.black)
                            }
                            Spacer()
                            if presentation.isInAppendix {
                                Text("APPENDIX")
                                    .font(.system(size: Theme.small, weight: .heavy)).padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(.purple, in: RoundedRectangle(cornerRadius: 6)).foregroundStyle(.white)
                            }
                        }
                        .padding(8)
                    }
                    .frame(width: fitted.width, height: fitted.height)
                    ModeBar(model: model, presentation: presentation)
                        .frame(width: fitted.width, height: barHeight)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }
}

/// Laser / Pen / Clear, lit when active; the same actions as L, D and E.
struct ModeBar: View {
    let model: AppModel
    let presentation: Presentation

    var body: some View {
        HStack(spacing: 10) {
            ModeButton(title: "Laser", key: "L", symbol: "cursorarrow.rays", color: .red, isOn: presentation.pointerMode) {
                _ = model.perform(.togglePointer)
            }
            ModeButton(title: "Pen", key: "D", symbol: "pencil.tip", color: .orange, isOn: presentation.drawMode) {
                _ = model.perform(.toggleDraw)
            }
            ModeButton(title: "Clear", key: "E", symbol: "eraser", color: .gray, isOn: false) {
                _ = model.perform(.command(.clearInk))
            }
            Spacer()
            if presentation.pointerMode {
                Text("Move the mouse over the slide").font(.system(size: Theme.small)).foregroundStyle(.secondary)
            } else if presentation.drawMode {
                Text("Draw on the slide; strokes fade after 3 s").font(.system(size: Theme.small)).foregroundStyle(.secondary)
            }
        }
    }
}

struct ModeButton: View {
    let title: String
    let key: String
    let symbol: String
    let color: Color
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                Text(title)
                Text(key)
                    .font(.system(size: Theme.small, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((isOn ? Color.black : Color.white).opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            }
            .font(.system(size: Theme.body, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(isOn ? color.opacity(0.9) : Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(isOn ? .black : .white)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) mode")
        .accessibilityValue(isOn ? "on" : "off")
    }
}

struct PaneTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: Theme.paneTitle, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 2)
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
        VStack(alignment: .leading, spacing: Theme.paneSpacing) {
            HStack {
                PaneTitle(note.map { "Notes · \($0.source.displayName)" } ?? "Notes")
                Spacer()
                if model.notesEditing {
                    Button("Done") { finishEditing(page: page) }.keyboardShortcut(.defaultAction).controlSize(.regular)
                } else {
                    Button("Edit (⌘E)") { model.setNotesEditing(true) }
                        .buttonStyle(.plain).font(.system(size: Theme.small)).foregroundStyle(.secondary)
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
                        .font(.system(size: Theme.body))
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
        .font(.system(size: Theme.body))
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
/// Three fixed regions: frame info on the left, the timer always centred, the audience state on the right, so
/// nothing shifts as the text on the left changes width (feedback round 1).
struct StatusBar: View {
    let model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            ZStack {
                HStack(spacing: 20) {
                    if let presentation = model.presentation {
                        let frame = presentation.currentFrame
                        Text("Frame \(frame.label) / \(presentation.frameCount)")
                            .font(.system(size: Theme.status, weight: .semibold, design: .rounded))
                        if frame.buildCount > 1 {
                            Text("Build \(presentation.currentBuild + 1)/\(frame.buildCount)").foregroundStyle(.secondary)
                        }
                        if presentation.isInAppendix {
                            Text("APPENDIX").font(.system(size: Theme.body, weight: .heavy)).foregroundStyle(.purple)
                        } else if let left = presentation.mainTalkFramesLeft {
                            Text("\(left) left").foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No deck open").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if let presentation = model.presentation {
                    timerSection(presentation: presentation, now: context.date)
                } else {
                    Text(context.date, format: .dateTime.hour().minute()).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if let presentation = model.presentation { audienceIndicator(presentation: presentation) }
                }
            }
            .font(.system(size: Theme.statusSecondary, design: .rounded))
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.06))
        }
    }

    @ViewBuilder
    private func timerSection(presentation: Presentation, now: Date) -> some View {
        let timer = presentation.state.timer
        let elapsed = timer.elapsed(at: now)
        HStack(spacing: 20) {
            Label(format(elapsed), systemImage: timer.isRunning ? "timer" : "pause.circle")
                .font(.system(size: Theme.status, weight: .semibold, design: .rounded))
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
        return HStack(spacing: 12) {
            if model.isPresenting && model.displays.assignment.audience == nil {
                Text("REHEARSAL").font(.system(size: Theme.small, weight: .bold)).foregroundStyle(.secondary)
            }
            Text(text)
                .font(.system(size: Theme.body, weight: .bold, design: .rounded))
                .padding(.horizontal, 12).padding(.vertical, 6)
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
