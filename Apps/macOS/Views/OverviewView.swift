import PresenterCore
import SwiftUI

/// Overview (SPEC §6.3): the current slide stays exactly where the presenter layout puts it; the next-slide and
/// notes column is replaced by search and a two-column grid of frames (feedback rounds 4 to 6). Every key keeps
/// its presenting meaning, so the talk goes on with the overview open and the grid follows; a click on a frame
/// or a search hit jumps there at once; Tab or Esc closes.
struct OverviewLayout: View {
    let model: AppModel
    let presentation: Presentation
    @AppStorage("layout.horizontalFraction") private var horizontalFraction = 0.68

    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .top, spacing: 0) {
                CurrentSlidePane(model: model, presentation: presentation)
                    .frame(width: max(200, geo.size.width * horizontalFraction))
                SplitHandle(axis: .horizontal) { delta in
                    horizontalFraction = min(0.85, max(0.3, horizontalFraction + delta / geo.size.width))
                }
                OverviewPanel(model: model, presentation: presentation)
            }
        }
        .padding(8)
        .font(.system(size: Theme.body))
    }
}

struct OverviewPanel: View {
    let model: AppModel
    let presentation: Presentation
    @State private var query = ""
    @State private var hits: [SearchHit] = []
    @State private var selectedHit: Int? = nil
    @FocusState private var searchFocused: Bool
    /// Frames (collapsed, one thumbnail per frame) or Builds (expanded, one per page); feedback round 7.
    @AppStorage(AppSettings.overviewShowsBuildsKey) private var showsBuilds = false

    private var currentPage: Int { presentation.state.presenterPage }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paneSpacing) {
            HStack(spacing: 12) {
                PaneTitle("Overview")
                Spacer()
                Picker("Overview shows", selection: $showsBuilds) {
                    Text("Frames").tag(false)
                    Text("Builds").tag(true)
                }
                .pickerStyle(.segmented).labelsHidden().controlSize(.small).frame(width: 150)
                .help("Frames: one thumbnail per frame (collapsed); the current frame shows the build on screen and lists its builds. Builds: every build as its own thumbnail (expanded).")
                OverviewToggle(model: model)
            }
            .frame(height: Theme.paneHeader)
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search text (⌘F)", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { commitFromSearch() }
                    .onKeyPress(.downArrow) { moveHit(1); return .handled }
                    .onKeyPress(.upArrow) { moveHit(-1); return .handled }
                    .onKeyPress(.escape) { searchFocused = false; return .handled }
                if !query.isEmpty {
                    Text(hits.isEmpty ? "no matches" : "\(hits.count) matches").foregroundStyle(.secondary).font(.system(size: Theme.small))
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(8)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            if !query.isEmpty {
                SearchResults(hits: hits, selected: selectedHit, frames: presentation.document.frames) { index in
                    selectedHit = index
                    model.jump(to: hits[index].pageIndex)
                }
                .frame(maxHeight: 220)
            }
            FrameGrid(model: model, presentation: presentation, showsBuilds: showsBuilds)
        }
        .task(id: query) {
            let text = query
            guard !text.isEmpty else { hits = []; selectedHit = nil; return }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            let results = await presentation.searcher.search(text)
            guard !Task.isCancelled else { return }
            hits = results
            selectedHit = results.isEmpty ? nil : 0
        }
        .onChange(of: model.searchFocusRequest, initial: true) { _, _ in
            if model.searchFocusRequest > 0 { searchFocused = true }
        }
        .onAppear { presentation.thumbnails.setFocus(page: currentPage) }
        .onChange(of: currentPage) { _, page in presentation.thumbnails.setFocus(page: page) }
    }

    private func moveHit(_ delta: Int) {
        guard !hits.isEmpty else { return }
        selectedHit = min(max((selectedHit ?? -1) + delta, 0), hits.count - 1)
    }

    private func commitFromSearch() {
        if let selectedHit, hits.indices.contains(selectedHit) {
            model.jump(to: hits[selectedHit].pageIndex)
        }
    }
}

/// The outline as a list with the current part highlighted and kept in view (notes pane, feedback round 2).
struct OutlineSidebar: View {
    let outline: Outline
    let frames: FrameIndex
    let currentPage: Int
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PaneTitle("Outline")
            OutlineList(outline: outline, frames: frames, currentPage: currentPage, fontSize: Theme.body, select: select)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SearchResults: View {
    let hits: [SearchHit]
    let selected: Int?
    let frames: FrameIndex
    let select: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(hits.enumerated()), id: \.element.id) { index, hit in
                        let frame = frames.frames[hit.frameIndex]
                        HStack(alignment: .top, spacing: 8) {
                            Text("Frame \(frame.label)").font(.system(size: Theme.small, weight: .semibold)).foregroundStyle(.secondary).frame(width: 70, alignment: .leading)
                            Text(hit.snippet).lineLimit(2)
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .background(selected == index ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 4))
                        .contentShape(Rectangle())
                        .onTapGesture { select(index) }
                        .id(index)
                    }
                }
                .padding(4)
            }
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: selected) { _, index in if let index { proxy.scrollTo(index) } }
        }
    }
}

/// One cell of the overview grid: a frame in Frames mode (collapsed) or a page in Builds mode (expanded).
struct OverviewItem: Identifiable, Hashable {
    /// Frame index in Frames mode, page index in Builds mode; also the scroll anchor.
    let id: Int
    let frame: Frame
    /// The page the thumbnail shows.
    let page: Int
}

/// Two columns, labelled. The current item is ringed blue; when the audience sees a different one (frozen), that
/// one is ringed orange, the FROZEN colour. A click jumps there. Frames mode (collapsed) shows the last page of each
/// frame, fully built (SPEC §4.1), except the current frame, whose thumbnail follows the build on screen and whose
/// label lists its builds with the current one lit (feedback round 7). Builds mode (expanded) shows every page.
/// Under each: the build count or position, an appendix mark, and a notes icon at the right when the frame has notes.
struct FrameGrid: View {
    let model: AppModel
    let presentation: Presentation
    let showsBuilds: Bool

    private static let columns = 2

    private var items: [OverviewItem] {
        let frames = presentation.document.frames
        if showsBuilds {
            return (0..<frames.pageCount).map { OverviewItem(id: $0, frame: frames.frame(containing: $0), page: $0) }
        }
        let current = presentation.currentFrame.index
        return frames.frames.map {
            OverviewItem(id: $0.index, frame: $0, page: $0.index == current ? presentation.state.presenterPage : $0.lastPage)
        }
    }

    private var selectedID: Int { showsBuilds ? presentation.state.presenterPage : presentation.currentFrame.index }

    private var audienceID: Int? {
        presentation.state.audiencePage.map { showsBuilds ? $0 : presentation.document.frames.frame(containing: $0).index }
    }

    var body: some View {
        let frames = presentation.document.frames
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: FrameGrid.columns), spacing: 12) {
                    ForEach(items) { item in
                        FrameCell(item: item, aspect: presentation.document.pages[item.page].aspectRatio,
                                  image: presentation.thumbnails.image(forPage: item.page),
                                  isSelected: item.id == selectedID,
                                  isAudience: item.id == audienceID && item.id != selectedID,
                                  isAppendix: presentation.document.isAppendix(page: item.frame.firstPage),
                                  hasNotes: item.frame.pages.contains { presentation.notes.table.note(for: $0, frames: frames) != nil },
                                  buildShown: showsBuilds ? frames.buildIndex(of: item.page)
                                      : (item.id == selectedID ? presentation.currentBuild : nil),
                                  listsBuilds: !showsBuilds && item.id == selectedID,
                                  jump: { page in model.jump(to: page) })
                            .onTapGesture { model.jump(to: showsBuilds ? item.page : item.frame.firstPage) }
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 4).padding(.vertical, 8)
            }
            .onAppear { proxy.scrollTo(selectedID, anchor: .center) }
            .onChange(of: selectedID) { _, id in withAnimation(.easeInOut(duration: 0.1)) { proxy.scrollTo(id) } }
            .onChange(of: showsBuilds) { _, _ in
                // The grid's items were just replaced; anchor once they are laid out.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(50))
                    proxy.scrollTo(selectedID, anchor: .center)
                }
            }
        }
    }
}

struct FrameCell: View {
    let item: OverviewItem
    let aspect: CGFloat
    let image: CGImage?
    let isSelected: Bool
    let isAudience: Bool
    let isAppendix: Bool
    let hasNotes: Bool
    /// The build this cell stands for, when the label should say so (Builds mode, or the current frame in Frames mode).
    let buildShown: Int?
    /// Frames mode, the current frame: list every build with `buildShown` lit, each clickable.
    let listsBuilds: Bool
    let jump: (Int) -> Void

    /// Beyond this, the current frame's builds are shown as "k/n" rather than one number each.
    private static let maxListedBuilds = 8
    /// The label row is this tall whether it holds a count or the build list, so nothing below it moves (feedback round 8).
    private static let labelRowHeight: CGFloat = 24

    var body: some View {
        let frame = item.frame
        VStack(spacing: 4) {
            ZStack {
                Rectangle().fill(Color.white.opacity(0.08))
                if let image {
                    Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
                }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected ? Color.accentColor : (isAudience ? .orange : .clear), lineWidth: isSelected ? 6 : 4))
            // Everything on the text baseline, so the build count sits level with the frame number (feedback round 7),
            // in a row of fixed height, so a frame listing its builds does not push the rows below it down (round 8).
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(frame.label).font(.system(size: Theme.small, weight: .semibold))
                if frame.buildCount > 1 {
                    if listsBuilds, let buildShown, frame.buildCount <= FrameCell.maxListedBuilds {
                        Text(Image(systemName: "rectangle.stack")).font(.system(size: Theme.small)).foregroundStyle(.secondary)
                        buildList(frame: frame, current: buildShown)
                    } else {
                        Label(buildShown.map { "\($0 + 1)/\(frame.buildCount)" } ?? "\(frame.buildCount)", systemImage: "rectangle.stack")
                            .font(.system(size: Theme.small)).monospacedDigit().foregroundStyle(.secondary)
                            .help(buildShown.map { "Build \($0 + 1) of \(frame.buildCount)" } ?? "\(frame.buildCount) builds")
                            .accessibilityLabel(buildShown.map { "Build \($0 + 1) of \(frame.buildCount)" } ?? "\(frame.buildCount) builds")
                    }
                }
                if isAppendix { Text("A").font(.system(size: Theme.small, weight: .heavy)).foregroundStyle(.purple) }
                Spacer(minLength: 0)
                if hasNotes {
                    Text(Image(systemName: "note.text"))
                        .font(.system(size: Theme.small)).foregroundStyle(.secondary)
                        .help("Has notes")
                        .accessibilityLabel("Has notes")
                }
            }
            .frame(height: FrameCell.labelRowHeight)
        }
        .contentShape(Rectangle())
    }

    /// "1 2 3" with the build on screen lit: the talk is inside this frame's build progression. Each number jumps.
    private func buildList(frame: Frame, current: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            ForEach(0..<frame.buildCount, id: \.self) { build in
                let lit = build == current
                Text("\(build + 1)")
                    .font(.system(size: Theme.small, weight: lit ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(lit ? Color.white : Color.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(lit ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 3))
                    .contentShape(Rectangle())
                    .onTapGesture { jump(frame.firstPage + build) }
                    .accessibilityLabel("Build \(build + 1)\(lit ? ", on screen" : "")")
            }
        }
        .padding(2)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))   // one group beside the frame number
        .help("Builds of frame \(frame.label); build \(current + 1) is on screen. Click one to show it.")
    }
}
