import CoreGraphics
import Foundation

/// A slide surface's rendering parameters: the box it fits pages into, its colour space and crop.
public struct SurfaceSpec: Hashable, Sendable {
    public enum Role: Hashable, Sendable {
        case audience
        case presenterCurrent
        case preview
    }

    public var role: Role
    public var bounds: PixelSize
    public var colorSpace: ColorSpaceID
    public var crop: CropRect

    public init(role: Role, bounds: PixelSize, colorSpace: ColorSpaceID = .sRGB, crop: CropRect = .full) {
        self.role = role
        self.bounds = bounds
        self.colorSpace = colorSpace
        self.crop = crop
    }

    /// The exact request this surface makes for `page`: the page (after crop) fitted into the bounds.
    public func request(for page: PageInfo) -> RenderRequest {
        let croppedAspect = page.aspectRatio * CGFloat(crop.width / crop.height)
        return RenderRequest(pageIndex: page.index,
                             pixelSize: PixelSize.fit(aspectRatio: croppedAspect, in: bounds),
                             crop: crop,
                             colorSpace: colorSpace)
    }
}

/// Decides what to render ahead of time (SPEC §3.3): per surface, its focus page ±2, the first page of the
/// next frame, and the page `back` would return to. Nearer pages of every surface come before farther ones.
public enum PrefetchPlanner {
    public static func plan(state: SessionState, document: PresentationDocument, surfaces: [SurfaceSpec]) -> [RenderRequest] {
        let frames = document.frames
        let last = document.pageCount - 1
        guard last >= 0 else { return [] }

        func focus(for role: SurfaceSpec.Role) -> Int? {
            switch role {
            case .audience: return state.audiencePage
            case .presenterCurrent: return state.presenterPage
            case .preview:
                let next = state.presenterPage + 1
                return next <= last ? next : nil
            }
        }

        // Rings of candidates per surface, nearest first.
        var rings: [[(SurfaceSpec, Int)]] = []
        for surface in surfaces {
            guard let f = focus(for: surface.role) else { continue }
            var ring: [Int?] = [f, f + 1, f - 1, frames.nextFrameFirstPage(after: f), f + 2, f - 2, state.history.last]
            if surface.role == .preview { ring = [f, f + 1, f + 2, frames.nextFrameFirstPage(after: f)] }
            for (depth, candidate) in ring.enumerated() {
                guard let page = candidate, page >= 0, page <= last else { continue }
                while rings.count <= depth { rings.append([]) }
                rings[depth].append((surface, page))
            }
        }

        var seen: Set<RenderRequest> = []
        var result: [RenderRequest] = []
        for ring in rings {
            for (surface, page) in ring {
                let request = surface.request(for: document.pages[page])
                if seen.insert(request).inserted { result.append(request) }
            }
        }
        return result
    }
}
