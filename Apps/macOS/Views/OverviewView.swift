import PresenterCore
import SwiftUI

/// Overview (SPEC §6.3): current slide on the left; outline, search and the frame grid on the right.
/// A click on a frame, an outline entry or a search hit jumps there at once; arrows move a cursor without
/// changing the slide and Return jumps to it. The overview stays open until Tab or Esc.
struct OverviewLayout: View {
    let model: AppModel
    let presentation: Presentation

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 8) {
                CurrentSlidePane(model: model, presentation: presentation)
                    .frame(width: max(240, geo.size.width * 0.36))
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
        HStack(spacing: 8) {
            if !presentation.document.outline.isEmpty {
                OutlineSidebar(outline: presentation.document.outline, frames: presentation.document.frames,
                               currentPage: presentation.state.presenterPage) { page in
                    model.jump(to: page)
                }
                .frame(width: 220)
            }
            VStack(spacing: 8) {
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

/// Grid of frames showing the last page of each (SPEC §4.1), labelled; the cursor is blue, the current frame green.
/// A click jumps to the frame. Under each: the build count beside the label when there is more than one, an
/// appendix mark, and a notes icon at the right when the frame has notes.
struct FrameGrid: View {
    let model: AppModel
    let presentation: Presentation
    let selectedFrame: Int

    private let cellWidth: CGFloat = 200

    var body: some View {
        GeometryReader { geo in
            let columns = max(1, Int(geo.size.width / (cellWidth + 12)))
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: 12), count: columns), spacing: 12) {
                        ForEach(presentation.document.frames.frames, id: \.index) { frame in
                            FrameCell(frame: frame, aspect: presentation.document.pages[frame.lastPage].aspectRatio,
                                      image: presentation.thumbnails.image(forFrame: frame.index),
                                      isSelected: frame.index == selectedFrame,
                                      isCommitted: frame.index == presentation.committedFrame.index,
                                      isAppendix: presentation.document.isAppendix(page: frame.firstPage),
                                      hasNotes: frame.pages.contains { presentation.notes.table.note(for: $0, frames: presentation.document.frames) != nil })
                                .frame(width: cellWidth)
                                .onTapGesture { model.jump(to: frame.firstPage) }
                                .id(frame.index)
                        }
                    }
                    .padding(8)
                }
                .onAppear { model.overviewColumns = columns; proxy.scrollTo(selectedFrame, anchor: .center) }
                .onChange(of: columns) { _, c in model.overviewColumns = c }
                .onChange(of: selectedFrame) { _, frame in withAnimation(.easeInOut(duration: 0.1)) { proxy.scrollTo(frame) } }
            }
        }
    }
}

struct FrameCell: View {
    let frame: Frame
    let aspect: CGFloat
    let image: CGImage?
    let isSelected: Bool
    let isCommitted: Bool
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
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(isSelected ? Color.accentColor : (isCommitted ? .green : .clear), lineWidth: isSelected ? 6 : 3))
            .shadow(color: isSelected ? Color.accentColor.opacity(0.9) : .clear, radius: 12)
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
    }
}
