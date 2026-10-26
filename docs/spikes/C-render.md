# Spike C: render benchmark

*2026-10-25. Code: `Spikes/RenderBench` (SwiftPM executable, `swift run -c release RenderBench ../../Fixtures`). Machine: Ben's MacBook Pro, 14 cores, 36 GiB, macOS 26.6.2, Xcode 27.1.*

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
| basic-169 | 20 | 1.1 / 2.4 / 5.6 | 1.5 / 1.8 / 2.0 | 2.7 / 3.4 / 3.5 |
| overlays | 23 | 1.1 / 1.4 / 1.6 | 1.8 / 2.2 / 2.2 | 3.6 / 4.3 / 4.4 |
| notes-right | 6 | 1.2 / 1.8 / 1.8 | 1.4 / 1.5 / 1.5 | 2.8 / 3.3 / 3.3 |
| notes-bottom | 6 | 1.3 / 1.9 / 1.9 | 1.6 / 1.7 / 1.7 | 3.5 / 3.8 / 3.8 |
| pdfpc-notes | 10 | 1.0 / 1.4 / 1.4 | 1.6 / 2.0 / 2.0 | 3.6 / 4.0 / 4.0 |
| pdfcomment-notes | 7 | 1.3 / 1.5 / 1.5 | 1.3 / 1.7 / 1.7 | 3.6 / 3.9 / 3.9 |
| links-appendix | 11 | 1.1 / 2.0 / 2.0 | 1.4 / 1.4 / 1.4 | 3.0 / 3.3 / 3.3 |
| tikz-heavy | 7 | 4.5 / 15.6 / 15.6 | 2.9 / 15.8 / 15.8 | 6.3 / 17.9 / 17.9 |
| transitions | 13 | 1.0 / 1.0 / 1.4 | 1.3 / 1.4 / 1.6 | 2.6 / 2.7 / 2.8 |
| huge | 401 | 0.9 / 1.1 / 1.9 | 1.3 / 1.5 / 1.8 | 2.7 / 3.1 / 3.7 |
| malformed | – | `CGPDFDocument` returns nil in 1.6 ms; `PDFDocument` also nil. No crash. | | |

Warm renders are within noise of cold ones (CoreGraphics caches fonts, not rasters), so "warm" for us has to mean "image already in our cache". The 5.6 ms outlier on basic-169 page 1 is the very first render in the process (font loading). The slowest page in the corpus is tikz-heavy page 5 (2400 translucent discs): 15.6 ms at 1080p, 17.9 ms at 4K. Opening a document costs 0.3–6.5 ms (`transitions.pdf` was the slowest, 401-page `huge.pdf` took 3.4 ms).

Of the per-render cost, allocating and clearing the fresh context is 0.5 ms at 1080p, 1.0 ms at 1440p and 2.3 ms at 4K, i.e. most of the time for simple pages at 4K. Reusing contexts is an easy optimisation if ever needed; it is not needed now.

### Warm-cache advance

Dictionary lookup + `layer.contents = cachedImage` + `CATransaction.commit()` with 4K images, 200 iterations: **median 1.0 µs, p95 1.3 µs, max 10.9 µs**. One frame is 16 667 µs at 60 Hz and 8 333 µs at 120 Hz. The CPU side of a warm advance is therefore three to four orders of magnitude inside one frame; whatever latency remains is the Core Animation commit → render server → display pipeline, which this headless spike cannot measure. **M1 verifies the end-to-end number with `os_signpost` (input → command → frame presented), as the M1 acceptance criterion requires.**

A *cold* advance (page not cached) at 4K costs up to 18 ms on this corpus, which would miss a 60 Hz frame. Prefetching the committed page ±2, the next frame's first page and the back target (SPEC §3.3) covers every single-keypress destination, so a miss only happens on jumps, and SPEC §3.3 already says to keep the old image up until the new one is ready and log the miss.

### Annotations never reach the bitmap

Differing pixels at 1080p between the PDFKit render and the CoreGraphics render:

| Fixture | Pages | Annotation | PDFKit with annotations vs CG | PDFKit without annotations vs CG |
|---|---|---|---|---|
| pdfpc-notes | 1–9 | `/Text`, `/F 6` (Hidden) | 233 | 233 |
| pdfpc-notes | 10 | none | 233 | 233 |
| pdfcomment-notes | 1–5 | `/Text`, `/F 4` | 551–711 | 202 |
| pdfcomment-notes | 6 | `/FreeText`, `/F 4` | 4349 | 202 |
| pdfcomment-notes | 7 | none | 202 | 202 |

The 202–233 pixel floor is anti-aliasing noise between the two engines (present on the annotation-free pages too). PDFKit adds ~500 pixels of comment icon on fixture 5 and ~4100 pixels of FreeText on page 6; the CG render has none of them, and the CG render of a page with annotations is identical to PDFKit-without-annotations up to that floor. PDFKit skips pdfpc's notes anyway because of the Hidden flag; pdfcomment's are not hidden and would show as icons through PDFKit. I also looked at the dumped PNGs: no icon on `pdfcomment-notes` page 1, and `notes-right` page 3 shows the slide on the left and the notes panel on the right.

**Consequence:** `CGContext.drawPDFPage` draws page content only, so SPEC §3.3's "note annotations must never appear" holds by construction. The flip side is that *any* annotation appearance stream is skipped, including the visible FreeText on fixture 5 page 6, so a deck that relies on annotations for visible content (rare in Beamer) will look different from Preview. Acceptable; noted as a known limitation.

### Thumbnails

All 401 pages of `huge.pdf` at 256 px tall: median 0.21 ms per page, 86 ms total, 178 MB if all kept as BGRX. tikz-heavy's heavy page costs 13.8 ms even as a thumbnail (it is path-bound, not pixel-bound). Thumbnails need a separate memory-bounded cache (SPEC §3.3), ideally JPEG/HEIF-compressed or at most ~100 MB of raw bitmaps; rendering them lazily is cheap enough that eviction is harmless.

### Concurrency (all pages, 1080p, wall-clock ms)

| Fixture | Sequential | 4 threads sharing one `CGPDFDocument` | 4 threads, one document each | 8 threads, one document each |
|---|---|---|---|---|
| basic-169 (20) | 15 | 4 | 9 | 7 |
| tikz-heavy (7) | 42 | 20 | 20 | 20 |
| overlays (23) | 20 | 5 | 10 | 7 |

Rendering different pages of one `CGPDFDocument` from four threads did not crash and scaled ~4×. Separate documents per thread scale worse because each document re-parses and re-loads fonts. Apple does not document `CGPDFDocument` as thread-safe for concurrent drawing, so the production design stays conservative: `RenderCache` is an actor that owns the document and serialises renders, which at 1–4 ms per page keeps a 6-page prefetch set under 25 ms even at 4K. Concurrency can be added behind a flag if M1 profiling shows the queue backing up (e.g. on tikz-heavy decks).

### Colour space

tikz-heavy, 7 pages at 1080p: sRGB 41 ms, Display P3 48 ms, generic linear RGB 47 ms, device RGB 41 ms. Rendering in the display's colour space (P3 on modern Apple displays) costs ~15 % on the heaviest fixture and nothing visible elsewhere. Keep SPEC §3.3's "render in the target display's colour space".

### Memory

| Size | MB per image | 6-image prefetch set | Two surfaces (audience + presenter) |
|---|---|---|---|
| 1080p | 7.9 | 47 | 95 |
| 1440p | 14.1 | 84 | 169 |
| 4K | 31.6 | 190 | 380 |

Fine on the Mac. On iPad the presenter-side surfaces are smaller than the external display, so the real number is one 4K set plus smaller ones, roughly 250 MB, which is within iPadOS foreground limits but argues for evicting beyond the prefetch window and responding to memory warnings by dropping everything except the committed image.

## Recommendations for M1

1. **Renderer:** `CGContext.drawPDFPage` into a BGRX 8-bit context in the display's colour space, fresh context per render, exactly as in the spike. No fallback engine is needed: fidelity on the corpus was fine and the slowest page is under 20 ms at 4K. Re-evaluate PDFium only if Ben's real decks show fidelity bugs.
2. **`RenderCache`** as an actor keyed by (page, pixel size, crop, colour space), serial rendering, prefetch per SPEC §3.3, cancel stale requests, `os_log` on misses. Budget: ~200 MB of full-size images on Mac, less on iPad, plus a separate thumbnail cache of ~100 MB.
3. **Audience surface:** a CALayer whose `contents` is swapped under `CATransaction` with actions disabled; never draw into the layer. Instrument keyDown → command applied → `CATransaction.commit` → next display refresh with `os_signpost` to close the measurement this spike cannot make.
4. **Malformed PDFs:** both `CGPDFDocument` and `PDFDocument` return nil for the truncated file, so "fail to open" is the path to design, not "crash". Live reload must keep the old document when the new one returns nil (SPEC §6.6 already says so).
5. **Annotations** are off the audience path for free; the notes parser (M3) reads them from the page dictionary instead. The `.pdfpc` JSON format and the exact annotation shapes are documented in `Fixtures/README.md`.

## Open questions

- Nothing blocks M1. The notes-split page-label problem found while building the fixtures is an M3 question (see `docs/decisions.md`).
