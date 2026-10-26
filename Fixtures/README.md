# Test corpus (SPEC §12)

Built from `src/*.tex` with `make` (latexmk + pdfTeX, TeX Live 2021). The built PDFs are committed so tests do not depend on a TeX installation. `tools/inspect.swift` dumps labels, annotations, `/Trans`, `/Dur`, outline and links: `swift Fixtures/tools/inspect.swift Fixtures/overlays.pdf`.

| # | File | Pages | What it exercises |
|---|---|---|---|
| 1 | `basic-169.pdf` | 20 | 16:9, 20 single-page frames, 4 outline sections. Labels 1–20. |
| 2 | `overlays.pdf` | 23 | 4:3, `\pause`, `\only`, `\uncover`, `\alt`, `\visible`. 9 frames; builds per frame: 1,3,4,3,2,1,3,5,1. |
| 3 | `notes-right.pdf`, `notes-bottom.pdf` | 6 each | Beamer second-screen notes via pgfpages. Pages are 907×255 pt (right, 16:9 slide) and 362×544 pt (bottom, 4:3 slide). 5 frames, frame 3 has 2 builds. |
| 4 | `pdfpc-notes.pdf` + `pdfpc-notes.pdfpc` | 10 | `\pdfpcnote` from pdfpc.sty v0.6.0, plus a JSON `.pdfpc` sidecar. 7 frames (frame 3: 3 builds, frame 4: 2), `\appendix` before frame 6. Package options `duration=30,enduserslide=5`. |
| 5 | `pdfcomment-notes.pdf` | 7 | `\pdfcomment` (Comment icon, Note icon, `open=true` with author), `\pdfmargincomment`, and a visible `\pdffreetextcomment` on page 6. Page 7 has no annotations. |
| 6 | `links-appendix.pdf` | 11 | `\hyperlink` to labelled appendix frames, `\hyperlinkframestart/-next`, `\hyperlinkappendixstart`, `\hyperlinkpresentationend`, `\hyperlinkdocumentstart`, explicit `\Acrobatmenu` named actions, one URI link, outline with an "Appendix" entry at page 8. |
| 7 | `tikz-heavy.pdf` | 7 | pgfplots fill-between, `surf` with `shader=interp`, ball/radial/axis shadings, fadings, patterns, 2400 translucent discs (page 5), blend modes and transparency groups, scatter + flat mesh. |
| 8 | `transitions.pdf` | 13 | `/Trans` Dissolve (with and without `/D`), Fade, Wipe `/Di 90`, Push, per-build `\transdissolve<2->`, `/Dur 1.0` and `/Dur 3.0`, explicit `/Replace`. |
| 9 | `ppt-export.pdf` + `.pptx` | – | **Supplied by Ben** (PowerPoint export with notes and one hidden slide). Not built here. |
| 10 | `huge.pdf` | 401 | 320 frames (every fourth has 2 builds), 15 sections + appendix. |
| 11 | `malformed.pdf` | – | First 20 000 bytes of `basic-169.pdf`. `CGPDFDocument` and `PDFDocument` both return nil; must never crash. |

## What the PDFs actually contain (verified with `tools/inspect.swift`, 2026-10-25)

- **Page labels are frame numbers.** Every overlay page of a frame carries the same label: in `overlays.pdf`, pages 2–4 are all labelled "2", pages 5–8 "3". `\appendix` does not restart numbering (fixture 6 labels run 1–8 across the appendix). Grouping by label is the right frame definition for ordinary Beamer decks.
- **Exception: second-screen-notes decks.** With `show notes on second screen`, labels are *not* frame numbers. `notes-right.pdf` has 5 frames on 6 pages but labels 1,1,2,2,3,3 (so frames 4 and 5 would merge, and frame 3's two builds would be split). Frame grouping for notes-split decks needs another signal (M3 problem; candidates: the slide's own frame counter, or beamer's `Navigation<n>` destinations). Recorded in `docs/decisions.md`.
- **pdfpc notes** are `/Subtype /Text` annotations with a zero-size `/Rect`, `/F 6` (Hidden + Print) and the text in `/Contents` with literal newlines for `\\`. A `\pdfpcnote` not wrapped in an overlay spec is repeated on every build page of the frame (pages 3–5). Metadata (`pdfpc:Duration`, `pdfpc:EndUserSlide`, `pdfpc:NotesPosition`, …) lives in the XMP packet, not in the Info dictionary; PDFKit's `documentAttributes` does not expose it.
- **pdfcomment notes** are `/Subtype /Text` with a 13.5 pt `/Rect`, `/F 4` (Print), `/Name /Comment` or `/Note`, `/Open`, `/T` (author), `/Subj`, `/C`. The FreeText on page 6 is `/Subtype /FreeText` and must be treated as visible content, not notes. (`\pdfmarkupcomment` emitted nothing with this TeX Live, so there is no markup annotation in the corpus.)
- **Named actions:** beamer's default navigation bar puts ~20 link annotations on every page: `/GoTo` to `Navigation<n>` destinations plus `/Named` `GoToPage`, `GoBack`, `Find`, `GoForward`. Fixture 6 additionally has `NextPage`, `PrevPage`, `FirstPage`, `LastPage`, `/GoTo /D (backup-proof)` named destinations and a `/URI` action.
- **Transitions:** beamer writes `/Trans <</S /R>>` on every page by default; the inspector hides that. Fixture 8 shows `/S /Dissolve`, `/D 1.5`, `/S /Fade`, `/S /Wipe /Di 90`, `/S /Push /D 0.5 /Di 270`, `/S /Replace`, and `/Dur` on the page dictionary.
- **`.pdfpc` format:** pdfpc (current master) writes JSON with `pdfpcFormat: 2`; the legacy `[notes]` text format is only a fallback. Per-page entries are keyed by 0-based `idx`, `label` and `overlay` (0-based position within the label run), with `note` text. The sidecar here overrides page 2's embedded note, adds one to build 3 of frame 3, and adds one to page 10 which has no embedded note. `endSlide` is a 0-based user-slide index in the JSON (pdfpc keeps all slide numbering 0-based internally and subtracts 1 only on the XMP path), so `4` here means frame 5, matching the XMP `EndUserSlide` of 5. `duration` is minutes.

## Rebuilding

    make -C Fixtures            # all
    make -C Fixtures overlays.pdf
    make -C Fixtures clean

LaTeX intermediates and `src/*.pdf` are gitignored; only the copies in this directory are committed.
