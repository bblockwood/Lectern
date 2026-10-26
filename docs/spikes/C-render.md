# Spike C: render benchmark

*2026-10-25. Code: `Spikes/RenderBench` (SwiftPM executable, `swift run -c release RenderBench ../../Fixtures`). Machine: Ben's MacBook Pro, 14 cores, 36 GiB, macOS 26.6.2, Xcode 27.1.*

*Re-measured 2026-10-26 after fixing a bug in the spike's drawing transform: `CGPDFPageGetDrawingTransform` only ever scales a page *down* into the rect it is given, so the first run drew every page at its native point size centred in the bitmap and understated every pixel-bound cost. The same bug shipped in M1's `PageRenderer` and was found by Ben on first launch. All numbers below are from the corrected run; the only material change is the heaviest TikZ page.*

## Questions

1. How long does `CGContext.drawPDFPage` take per page at 1080p, 1440p and 4K across the corpus?
2. Is a warm-cache advance under one display frame?
3. Does the CoreGraphics path ever draw note annotations (SPEC §3.3)?
4. Side questions that shape `RenderCache`: context allocation cost, thumbnail throughput, whether rendering scales across threads and whether one `CGPDFDocument` can be shared, colour-space cost, memory per prefetch set, and what a truncated PDF does.

## Method

- Open with `CGPDFDocument`, letterbox the crop box into a fresh BGRX (no alpha, 8-bit, sRGB) bitmap context per render: fill black, fill the fitted rect white, `getDrawingTransform(.cropBox …)`, `drawPDFPage`, `makeImage()`. That is the exact shape `RenderCache` will use.
- Every page of every fixture, cold (first render) then warm (immediate second render), three sizes. Fixture 9 (`ppt-export`) is not present yet.
- Annotation check: pixel-diff the CG render against `PDFPage.draw(with:to:)` with and without `displaysAnnotations`.
- Headless `CALayer.contents` assignment for the warm-cache handoff. There is no window in a command-line tool, so this is CPU cost only.

## Results

### Per-page render time (ms; cold = first render of that page)

| Fixture | Pages | 1080p median / p95 / max | 1440p median / p95 / max | 4K median / p95 / max |
|---|---|---|---|---|
| basic-169 | 20 | 1.5 / 2.9 / 4.5 | 1.5 / 2.5 / 2.6 | 2.9 / 3.3 / 3.5 |
| overlays | 23 | 0.8 / 1.0 / 1.3 | 1.5 / 1.6 / 1.6 | 3.2 / 3.5 / 3.6 |
| notes-right | 6 | 1.0 / 1.6 / 1.6 | 1.4 / 1.6 / 1.6 | 2.9 / 3.1 / 3.1 |
| notes-bottom | 6 | 1.0 / 1.6 / 1.6 | 1.6 / 1.7 / 1.7 | 3.2 / 3.5 / 3.5 |
| pdfpc-notes | 10 | 0.8 / 1.3 / 1.3 | 1.3 / 1.5 / 1.5 | 2.7 / 2.8 / 2.8 |
| pdfcomment-notes | 7 | 0.8 / 1.2 / 1.2 | 1.3 / 1.4 / 1.4 | 2.8 / 2.9 / 2.9 |
| links-appendix | 11 | 0.8 / 1.5 / 1.5 | 1.4 / 1.8 / 1.8 | 2.9 / 4.0 / 4.0 |
| tikz-heavy | 7 | 7.5 / 73.1 / 73.1 | 12.7 / 128.2 / 128.2 | 23.9 / 283.5 / 283.5 |
| transitions | 13 | 0.7 / 0.8 / 1.2 | 1.2 / 1.3 / 1.3 | 2.6 / 2.7 / 2.7 |
| huge | 401 | 0.8 / 0.8 / 1.2 | 1.3 / 1.4 / 1.6 | 2.8 / 3.0 / 3.3 |
| malformed | – | `CGPDFDocument` returns nil in 0.7 ms; `PDFDocument` also nil. No crash. | | |

Warm renders are within noise of cold ones (CoreGraphics caches fonts, not rasters), so "warm" for us has to mean "image already in our cache". The 4.5 ms outlier on basic-169 page 1 is the very first render in the process (font loading). The slowest page in the corpus is tikz-heavy page 5 (2400 translucent discs): 73 ms at 1080p, 128 ms at 1440p and 284 ms at 4K, i.e. it scales with pixel count because every disc goes through a transparency group. Every other page in the corpus is under 5 ms at 4K. Opening a document costs 0.2–2 ms (401-page `huge.pdf` took 2.0 ms).

Of the per-render cost, allocating and clearing the fresh context is 0.45 ms at 1080p, 0.8 ms at 1440p and 1.9 ms at 4K, i.e. most of the time for simple pages at 4K. Reusing contexts is an easy optimisation if ever needed; it is not needed now.

### Warm-cache advance

Dictionary lookup + `layer.contents = cachedImage` + `CATransaction.commit()` with 4K images, 200 iterations: **median 1.0 µs, p95 1.3 µs, max 10.9 µs**. One frame is 16 667 µs at 60 Hz and 8 333 µs at 120 Hz. The CPU side of a warm advance is therefore three to four orders of magnitude inside one frame; whatever latency remains is the Core Animation commit → render server → display pipeline, which this headless spike cannot measure. **M1 verifies the end-to-end number with `os_signpost` (input → command → frame presented), as the M1 acceptance criterion requires.**

A *cold* advance (page not cached) costs 1–4 ms for an ordinary page but up to 73 ms at 1080p and 284 ms at 4K for tikz-heavy page 5, many frames. Prefetching the committed page ±2, the next frame's first page and the back target (SPEC §3.3) covers every single-keypress destination, so a miss only happens on jumps, and SPEC §3.3 already says to keep the old image up until the new one is ready and log the miss. Because `RenderCache` renders one page at a time, a heavy page also holds up whatever is queued behind it, so a jump into a run of heavy pages can delay the interactive request by one heavy render. The M1 self-test on `tikz-heavy.pdf` at laptop resolution still shows no misses; a 4K projector and a deck full of such pages is the case to watch, and the concurrency section below shows the remedy if it is ever needed.

### Annotations never reach the bitmap

Differing pixels at 1080p between the PDFKit render and the CoreGraphics render:

| Fixture | Pages | Annotation | PDFKit with annotations vs CG | PDFKit without annotations vs CG |
|---|---|---|---|---|
| pdfpc-notes | 1–9 | `/Text`, `/F 6` (Hidden) | 0 | 0 |
| pdfpc-notes | 10 | none | 0 | 0 |
| pdfcomment-notes | 1–5 | `/Text`, `/F 4` | 5 554–8 597 | 0 |
| pdfcomment-notes | 6 | `/FreeText`, `/F 4` | 72 721 | 0 |
| pdfcomment-notes | 7 | none | 0 | 0 |

With the corrected transform the two engines are pixel-identical on every annotation-free page (the first run's 202–233 pixel floor was anti-aliasing at the wrong scale). PDFKit adds 5.5–8.6 k pixels of comment icon on fixture 5 pages 1–5 and 73 k pixels of FreeText on page 6; the CG render has none of them and is identical to PDFKit-without-annotations. PDFKit skips pdfpc's notes anyway because of the Hidden flag; pdfcomment's are not hidden and would show as icons through PDFKit. I also looked at the dumped PNGs: no icon on `pdfcomment-notes` page 1, and `notes-right` page 3 shows the slide on the left and the notes panel on the right.

**Consequence:** `CGContext.drawPDFPage` draws page content only, so SPEC §3.3's "note annotations must never appear" holds by construction. The flip side is that *any* annotation appearance stream is skipped, including the visible FreeText on fixture 5 page 6, so a deck that relies on annotations for visible content (rare in Beamer) will look different from Preview. Acceptable; noted as a known limitation.

### Thumbnails

All 401 pages of `huge.pdf` at 256 px tall: median 0.19 ms per page, 75 ms total, 178 MB if all kept as BGRX (thumbnails are smaller than the page, so the transform bug never affected them). tikz-heavy's heavy page costs 14 ms even as a thumbnail (it is path-bound, not pixel-bound). Thumbnails need a separate memory-bounded cache (SPEC §3.3), ideally JPEG/HEIF-compressed or at most ~100 MB of raw bitmaps; rendering them lazily is cheap enough that eviction is harmless.

### Concurrency (all pages, 1080p, wall-clock ms)

| Fixture | Sequential | 4 threads sharing one `CGPDFDocument` | 4 threads, one document each | 8 threads, one document each |
|---|---|---|---|---|
| basic-169 (20) | 15 | 5 | 8 | 8 |
| tikz-heavy (7) | 131 | 76 | 78 | 77 |
| overlays (23) | 22 | 7 | 10 | 8 |

Rendering different pages of one `CGPDFDocument` from four threads did not crash and scaled ~3× on ordinary decks; tikz-heavy only gains 1.7× because its single 73 ms page dominates the wall clock. Separate documents per thread scale worse because each document re-parses and re-loads fonts. Apple does not document `CGPDFDocument` as thread-safe for concurrent drawing, so the production design stays conservative: `RenderCache` is an actor that owns the document and serialises renders, which at 1–4 ms per page keeps a 6-page prefetch set under 25 ms even at 4K for ordinary decks. Heavy TikZ pages (284 ms each at 4K) are the case that would justify rendering off the serial path, behind a flag, if Ben's real decks have them.

### Colour space

tikz-heavy, 7 pages at 1080p: sRGB 131 ms, Display P3 138 ms, generic linear RGB 139 ms, device RGB 135 ms. Rendering in the display's colour space (P3 on modern Apple displays) costs ~5 % on the heaviest fixture and nothing visible elsewhere. Keep SPEC §3.3's "render in the target display's colour space".

### Memory

| Size | MB per image | 6-image prefetch set | Two surfaces (audience + presenter) |
|---|---|---|---|
| 1080p | 7.9 | 47 | 95 |
| 1440p | 14.1 | 84 | 169 |
| 4K | 31.6 | 190 | 380 |

Fine on the Mac. On iPad the presenter-side surfaces are smaller than the external display, so the real number is one 4K set plus smaller ones, roughly 250 MB, which is within iPadOS foreground limits but argues for evicting beyond the prefetch window and responding to memory warnings by dropping everything except the committed image.

## Recommendations for M1

1. **Renderer:** `CGContext.drawPDFPage` into a BGRX 8-bit context in the display's colour space, fresh context per render, exactly as in the spike. No fallback engine is needed: fidelity on the corpus was fine and every ordinary page is under 5 ms at 4K. The one slow page (2400 translucent discs, 284 ms at 4K) is pixel-bound compositing that any renderer pays; it is handled by prefetch plus keep-the-old-image, not by changing engines. Re-evaluate PDFium only if Ben's real decks show fidelity bugs.
2. **`RenderCache`** as an actor keyed by (page, pixel size, crop, colour space), serial rendering, prefetch per SPEC §3.3, cancel stale requests, `os_log` on misses. Budget: ~200 MB of full-size images on Mac, less on iPad, plus a separate thumbnail cache of ~100 MB.
3. **Audience surface:** a CALayer whose `contents` is swapped under `CATransaction` with actions disabled; never draw into the layer. Instrument keyDown → command applied → `CATransaction.commit` → next display refresh with `os_signpost` to close the measurement this spike cannot make.
4. **Malformed PDFs:** both `CGPDFDocument` and `PDFDocument` return nil for the truncated file, so "fail to open" is the path to design, not "crash". Live reload must keep the old document when the new one returns nil (SPEC §6.6 already says so).
5. **Annotations** are off the audience path for free; the notes parser (M3) reads them from the page dictionary instead. The `.pdfpc` JSON format and the exact annotation shapes are documented in `Fixtures/README.md`.

## Open questions

- Nothing blocks M1. The notes-split page-label problem found while building the fixtures is an M3 question (see `docs/decisions.md`).
- Heavy TikZ pages on a 4K projector (284 ms each): if Ben's real decks have them, measure the prefetch backlog on the projector and, if it shows, render heavy pages concurrently (sharing one `CGPDFDocument` across threads worked above).
