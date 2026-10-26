import CoreGraphics
import Foundation
import Testing
@testable import PresenterCore

private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8) {
    let data = image.dataProvider!.data!
    let p = CFDataGetBytePtr(data)!
    let i = y * image.bytesPerRow + x * 4   // BGRX little-endian: B G R X
    return (p[i + 2], p[i + 1], p[i])
}

@Suite struct Fitting {
    @Test func fitKeepsAspectAndFillsOneAxis() {
        #expect(PixelSize.fit(aspectRatio: 16.0 / 9.0, in: PixelSize(width: 1000, height: 1000)) == PixelSize(width: 1000, height: 563))
        #expect(PixelSize.fit(aspectRatio: 4.0 / 3.0, in: PixelSize(width: 1920, height: 1080)) == PixelSize(width: 1440, height: 1080))
        #expect(PixelSize.fit(aspectRatio: 16.0 / 9.0, in: PixelSize(width: 1920, height: 1080)) == PixelSize(width: 1920, height: 1080))
    }

    @Test func surfaceRequestUsesCroppedAspect() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("notes-right.pdf"))
        let surface = SurfaceSpec(role: .audience, bounds: PixelSize(width: 1920, height: 1080), crop: .leftHalf)
        let request = surface.request(for: doc.pages[0])
        #expect(request.pixelSize == PixelSize(width: 1920, height: 1080))   // 907x255 page, left half is 16:9
    }
}

@Suite struct Rendering {
    @Test func rendersAtTheRequestedSizeWithWhiteBackground() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("basic-169.pdf"))
        let request = RenderRequest(pageIndex: 0, pixelSize: PixelSize(width: 480, height: 270))
        let image = try #require(PageRenderer.render(page: doc.source.page(at: 0)!, pageSize: doc.pages[0].size, request: request))
        #expect(image.width == 480 && image.height == 270)
        let corner = pixel(image, x: 2, y: 2)
        #expect(corner == (255, 255, 255))
        // The title is dark blue text near the middle: at least one non-white pixel in the central band.
        var nonWhite = 0
        for y in 100..<170 { for x in 150..<330 where pixel(image, x: x, y: y) != (255, 255, 255) { nonWhite += 1 } }
        #expect(nonWhite > 50)
    }

    @Test func cropRendersTheSlideHalfOnly() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("notes-right.pdf"))
        let page = doc.source.page(at: 2)!   // slide left, grey notes panel right
        let full = try #require(PageRenderer.render(page: page, pageSize: doc.pages[2].size,
                                                    request: RenderRequest(pageIndex: 2, pixelSize: PixelSize(width: 800, height: 225))))
        let left = try #require(PageRenderer.render(page: page, pageSize: doc.pages[2].size,
                                                    request: RenderRequest(pageIndex: 2, pixelSize: PixelSize(width: 400, height: 225), crop: .leftHalf)))
        let right = try #require(PageRenderer.render(page: page, pageSize: doc.pages[2].size,
                                                     request: RenderRequest(pageIndex: 2, pixelSize: PixelSize(width: 400, height: 225), crop: .rightHalf)))
        // The notes panel is grey; the slide is white at the same spot.
        let fullRightSample = pixel(full, x: 600, y: 200)
        let rightSample = pixel(right, x: 200, y: 200)
        let leftSample = pixel(left, x: 200, y: 200)
        #expect(fullRightSample == rightSample)
        #expect(rightSample.r < 250, "notes panel should be grey, got \(rightSample)")
        #expect(leftSample == (255, 255, 255))
    }

    @Test func displayP3RequestsRenderToo() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("tikz-heavy.pdf"))
        let request = RenderRequest(pageIndex: 3, pixelSize: PixelSize(width: 320, height: 180), colorSpace: .displayP3)
        let image = PageRenderer.render(page: doc.source.page(at: 3)!, pageSize: doc.pages[3].size, request: request)
        #expect(image?.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func colorSpaceIDRoundTripsNamedSpaces() {
        let id = ColorSpaceID(CGColorSpace(name: CGColorSpace.displayP3)!)
        #expect(id == .displayP3)
        #expect(id.cgColorSpace.name == CGColorSpace.displayP3)
    }
}

@Suite struct Caching {
    @Test func missRendersThenHitIsSynchronous() async throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("overlays.pdf"))
        let cache = RenderCache(document: doc)
        let request = RenderRequest(pageIndex: 4, pixelSize: PixelSize(width: 400, height: 300))
        #expect(cache.cachedImage(for: request) == nil)
        let first = try #require(await cache.image(for: request))
        let hit = try #require(cache.cachedImage(for: request))
        #expect(first === hit)
        let again = try #require(await cache.image(for: request))
        #expect(again === first)
    }

    @Test func outOfRangePageReturnsNil() async throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("overlays.pdf"))
        let cache = RenderCache(document: doc)
        let image = await cache.image(for: RenderRequest(pageIndex: 99, pixelSize: PixelSize(width: 10, height: 10)))
        #expect(image == nil)
    }

    @Test func prefetchFillsTheStore() async throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("basic-169.pdf"))
        let cache = RenderCache(document: doc)
        let requests = (0..<5).map { RenderRequest(pageIndex: $0, pixelSize: PixelSize(width: 320, height: 180)) }
        await cache.prefetch(requests)
        await cache.waitUntilIdle()
        for r in requests { #expect(cache.cachedImage(for: r) != nil) }
        #expect(cache.store.count == 5)
    }

    @Test func interactiveRequestsJumpTheQueue() async throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("huge.pdf"))
        let cache = RenderCache(document: doc)
        let size = PixelSize(width: 1920, height: 1080)
        await cache.prefetch((0..<60).map { RenderRequest(pageIndex: $0, pixelSize: size) })
        let urgent = RenderRequest(pageIndex: 300, pixelSize: size)
        _ = await cache.image(for: urgent)
        // The urgent render finished while most of the prefetch queue was still pending.
        let pendingAfter = await cache.pendingCount
        #expect(pendingAfter > 30, "urgent request should not wait for \(60 - pendingAfter) prefetches")
        await cache.cancelPrefetches()
        #expect(await cache.pendingCount <= 1, "only the render in flight may remain")
        await cache.waitUntilIdle()
        #expect(await cache.pendingCount == 0)
    }

    @Test func cancelDropsOnlyPrefetches() async throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("huge.pdf"))
        let cache = RenderCache(document: doc)
        let size = PixelSize(width: 1920, height: 1080)
        let keep = RenderRequest(pageIndex: 50, pixelSize: size)
        await cache.prefetch((10..<50).map { RenderRequest(pageIndex: $0, pixelSize: size) } + [keep])
        await cache.cancelPrefetches(keeping: [keep])
        await cache.waitUntilIdle()
        #expect(cache.cachedImage(for: keep) != nil)
        #expect(cache.store.count <= 3)   // the one in flight when cancel arrived, plus `keep`
    }

    @Test func storeEvictsLeastRecentlyUsedButNotPinned() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("basic-169.pdf"))
        let one = PixelSize(width: 100, height: 100)
        func render(_ page: Int) -> (RenderRequest, CGImage) {
            let r = RenderRequest(pageIndex: page, pixelSize: one)
            return (r, PageRenderer.render(page: doc.source.page(at: page)!, pageSize: doc.pages[page].size, request: r)!)
        }
        let (r0, i0) = render(0), (r1, i1) = render(1), (r2, i2) = render(2)
        let store = ImageStore(budgetBytes: i0.bytesPerRow * i0.height * 2 + 100)   // room for exactly two images
        store.insert(i0, for: r0)
        store.insert(i1, for: r1)
        store.pin([r0])
        store.insert(i2, for: r2)
        #expect(store.contains(r0), "pinned survives")
        #expect(!store.contains(r1), "least recently used unpinned entry is evicted")
        #expect(store.contains(r2))
        _ = store.image(for: r0)
        #expect(store.bytesUsed <= store.budgetBytes)
    }

    @Test func storeEvictsFarthestFromFocusBeforeLeastRecentlyUsed() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("basic-169.pdf"))
        let one = PixelSize(width: 100, height: 100)
        func render(_ page: Int) -> (RenderRequest, CGImage) {
            let r = RenderRequest(pageIndex: page, pixelSize: one)
            return (r, PageRenderer.render(page: doc.source.page(at: page)!, pageSize: doc.pages[page].size, request: r)!)
        }
        let (r0, i0) = render(0), (r1, i1) = render(1), (r9, i9) = render(9), (r2, i2) = render(2)
        let store = ImageStore(budgetBytes: i0.bytesPerRow * i0.height * 3 + 100)   // room for three
        store.setFocusPages([1])
        store.insert(i9, for: r9)       // far from focus, but most recently inserted below gets touched
        store.insert(i0, for: r0)
        store.insert(i1, for: r1)
        _ = store.image(for: r9)        // page 9 is now the most recently used
        store.insert(i2, for: r2)       // over budget: evict the farthest (page 9), not the LRU (page 0)
        #expect(!store.contains(r9))
        #expect(store.contains(r0) && store.contains(r1) && store.contains(r2))
        #expect(store.evictions == 1)
        #expect(store.recentEvents.last?.kind == .evict)
    }

    @Test func clearForgetsPendingWork() async throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("huge.pdf"))
        let cache = RenderCache(document: doc)
        await cache.prefetch((0..<30).map { RenderRequest(pageIndex: $0, pixelSize: PixelSize(width: 1920, height: 1080)) })
        await cache.clear()
        #expect(await cache.pendingCount == 0)
        await cache.waitUntilIdle()
        #expect(cache.store.count == 0)
    }
}

@Suite struct Planning {
    @Test func planOrdersNearPagesOfEverySurfaceFirst() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("overlays.pdf"))   // frames 0 | 1-3 | 4-7 | 8-10 ...
        var state = SessionState()
        state.committedPage = 5
        state.history = [1]
        let audience = SurfaceSpec(role: .audience, bounds: PixelSize(width: 1920, height: 1080))
        let current = SurfaceSpec(role: .presenterCurrent, bounds: PixelSize(width: 960, height: 540))
        let preview = SurfaceSpec(role: .preview, bounds: PixelSize(width: 480, height: 270))
        let plan = PrefetchPlanner.plan(state: state, document: doc, surfaces: [audience, current, preview])
        let pages = plan.map { ($0.pageIndex, $0.pixelSize.width) }
        #expect(pages[0] == (5, 1440))   // audience focus
        #expect(pages[1] == (5, 720))    // presenter current focus
        #expect(pages[2] == (6, 360))    // preview focus (next page)
        #expect(pages[3] == (6, 1440))   // audience +1
        #expect(plan.contains { $0.pageIndex == 8 && $0.pixelSize.width == 1440 }, "first page of the next frame")
        #expect(plan.contains { $0.pageIndex == 1 && $0.pixelSize.width == 1440 }, "back target")
        #expect(plan.contains { $0.pageIndex == 3 && $0.pixelSize.width == 1440 }, "committed - 2")
        #expect(Set(plan).count == plan.count, "no duplicate requests")
    }

    @Test func planAtTheEndOmitsOutOfRangeAndPreview() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("basic-169.pdf"))
        var state = SessionState()
        state.committedPage = 19
        let plan = PrefetchPlanner.plan(state: state, document: doc, surfaces: [
            SurfaceSpec(role: .audience, bounds: PixelSize(width: 1920, height: 1080)),
            SurfaceSpec(role: .preview, bounds: PixelSize(width: 480, height: 270)),
        ])
        #expect(plan.allSatisfy { $0.pageIndex <= 19 })
        #expect(!plan.contains { $0.pixelSize.width == 480 }, "no preview requests past the last page")
    }

    @Test func blackAudienceStillPrefetchesPresenterPages() throws {
        let doc = try PresentationDocument.load(url: Fixtures.url("basic-169.pdf"))
        var state = SessionState()
        state.committedPage = 3
        state.audienceMode = .black
        let plan = PrefetchPlanner.plan(state: state, document: doc, surfaces: [
            SurfaceSpec(role: .audience, bounds: PixelSize(width: 1920, height: 1080)),
            SurfaceSpec(role: .presenterCurrent, bounds: PixelSize(width: 960, height: 540)),
        ])
        #expect(!plan.contains { $0.pixelSize.width == 1920 })
        #expect(plan.contains { $0.pixelSize.width == 960 && $0.pageIndex == 3 })
    }
}
