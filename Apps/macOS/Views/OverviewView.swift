import PresenterCore
import SwiftUI

/// Overview (SPEC §6.3): the current slide stays exactly where the presenter layout puts it; the next-slide and
/// notes column is replaced by search and a two-column grid of frames, with the outline as titled dividers
/// between the frames of each section (feedback round 4). A click on a frame or a search hit jumps there at
/// once; arrows move a cursor without changing the slide and Return jumps to it; Tab or Esc closes.
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

    private var selectedFrame: Int { model.overviewSelectedFrame ?? presentation.currentFrame.index }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.paneSpacing) {
            PaneTitle("Overview")
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
            FrameGrid(model: model, presentation: presentation, selectedFrame: selectedFrame)
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
        .onAppear { presentation.thumbnails.setFocus(frame: selectedFrame) }
        .onChange(of: selectedFrame) { _, frame in presentation.thumbnails.setFocus(frame: frame) }
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

/// Consecutive frames that fall under the same outline entry; `title` is nil before the first entry.
struct FrameSection {
    var entryID: Int?
    var title: String?
    var depth: Int
    var frames: [Frame]

    /// Groups the deck's frames by the outline entry each starts under (SPEC §4.4's current-part rule).
    static func sections(frames: FrameIndex, outline: Outline) -> [FrameSection] {
        let depths = Dictionary(uniqueKeysWithValues: outline.flattened.map { ($0.node.id, $0.depth) })
        var sections: [FrameSection] = []
        for frame in frames.frames {
            let entry = outline.currentEntry(forPage: frame.firstPage)
            if !sections.isEmpty, sections[sections.count - 1].entryID == entry?.id {
                sections[sections.count - 1].frames.append(frame)
            } else {
                sections.append(FrameSection(entryID: entry?.id, title: entry?.title, depth: entry.map { depths[$0.id] ?? 0 } ?? 0, frames: [frame]))
            }
        }
        return sections
    }
}

/// Two columns of frames showing the last page of each (SPEC §4.1), labelled, under titled dividers for the
/// outline's sections. The cursor is blue; what the audience sees is ringed orange (the FROZEN colour, since
/// that is when the two differ). A click jumps to the frame. Under each: the build count beside the label when
/// there is more than one, an appendix mark, and a notes icon at the right when the frame has notes.
struct FrameGrid: View {
    let model: AppModel
    let presentation: Presentation
    let selectedFrame: Int

    private static let columns = 2

    var body: some View {
        let sections = FrameSection.sections(frames: presentation.document.frames, outline: presentation.document.outline)
        let audienceFrame = presentation.state.audiencePage.map { presentation.document.frames.frame(containing: $0).index }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: FrameGrid.columns),
                          spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        Section {
                            ForEach(section.frames, id: \.index) { frame in
                                FrameCell(frame: frame, aspect: presentation.document.pages[frame.lastPage].aspectRatio,
                                          image: presentation.thumbnails.image(forFrame: frame.index),
                                          isSelected: frame.index == selectedFrame,
                                          isAudience: frame.index == audienceFrame,
                                          isAppendix: presentation.document.isAppendix(page: frame.firstPage),
                                          hasNotes: frame.pages.contains { presentation.notes.table.note(for: $0, frames: presentation.document.frames) != nil })
                                    .onTapGesture { model.jump(to: frame.firstPage) }
                                    .id(frame.index)
                            }
                        } header: {
                            if let title = section.title { SectionDivider(title: title, depth: section.depth) }
                        }
                    }
                }
                .padding(.horizontal, 4).padding(.bottom, 8)
            }
            .onAppear { model.overviewColumns = FrameGrid.columns; proxy.scrollTo(selectedFrame, anchor: .center) }
            .onChange(of: selectedFrame) { _, frame in withAnimation(.easeInOut(duration: 0.1)) { proxy.scrollTo(frame) } }
        }
    }
}

/// A titled horizontal rule between the frames of one outline section; subsections are indented.
struct SectionDivider: View {
    let title: String
    let depth: Int

    var body: some View {
        HStack(spacing: 10) {
            Text(title.isEmpty ? "(untitled)" : title)
                .font(.system(size: Theme.small, weight: .semibold))
                .foregroundStyle(depth == 0 ? Color.primary : Color.secondary)
                .lineLimit(1)
                .padding(.leading, CGFloat(depth) * 12)
            Rectangle().fill(Color.white.opacity(0.18)).frame(height: 1)
        }
        .padding(.vertical, 6)
        .background(Color.black)   // pinned headers scroll over the thumbnails
    }
}

struct FrameCell: View {
    let frame: Frame
    let aspect: CGFloat
    let image: CGImage?
    let isSelected: Bool
    let isAudience: Bool
    let isAppendix: Bool
    let hasNotes: Bool

    var body: some View {
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
            HStack(spacing: 6) {
                Text(frame.label).font(.system(size: Theme.small, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                if frame.buildCount > 1 {
                    Label("\(frame.buildCount)", systemImage: "rectangle.stack")
                        .font(.system(size: Theme.small - 2)).foregroundStyle(.secondary)
                        .help("\(frame.buildCount) builds")
                        .accessibilityLabel("\(frame.buildCount) builds")
                }
                if isAppendix { Text("A").font(.system(size: Theme.small - 2, weight: .heavy)).foregroundStyle(.purple) }
                Spacer(minLength: 0)
                if hasNotes {
                    Image(systemName: "note.text")
                        .font(.system(size: Theme.small - 2)).foregroundStyle(.secondary)
                        .help("Has notes")
                        .accessibilityLabel("Has notes")
                }
            }
        }
        .contentShape(Rectangle())
    }
}
