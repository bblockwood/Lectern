# Decisions

Record of spec ambiguities and how they were resolved. Newest at the bottom.

| Date | Topic | Decision | Status |
|---|---|---|---|
| 2026-10-25 | Deployment targets | macOS 26.0, iOS/iPadOS 26.0, watchOS 26.0: the installed Simulator runtimes are 26.5 and the spec allows raising freely. | Fable, provisional |
| 2026-10-25 | Bundle identifier prefix | `dev.lectern` (spikes use `dev.lectern.spike.*`). Ben can change it once signing is set up; nothing depends on it. | Fable, provisional |
| 2026-10-25 | Spike projects | Each spike is a self-contained XcodeGen project or SwiftPM package under `Spikes/`, not a target of the main project, so M0 code can be deleted without touching `project.yml`. | Fable |
| 2026-10-25 | Frame grouping in second-screen-notes decks | Beamer's page labels equal frame numbers in ordinary decks (verified on `overlays.pdf`) but **not** when `show notes on second screen` is used (`notes-right.pdf`: 5 frames, labels 1,1,2,2,3,3). M3 needs a different grouping signal for notes-split decks. Options to evaluate then: the frame number printed on the slide, beamer's `Navigation<n>` named destinations, or treating each page as its own frame. | Open, for M3 |
| 2026-10-25 | Render engine | `CGContext.drawPDFPage` is fast enough (≤ 18 ms at 4K on the heaviest fixture, ~3 ms typical) and skips annotations by construction. No PDFium evaluation unless real decks show fidelity bugs. See `docs/spikes/C-render.md`. | Fable |
| 2026-10-25 | Concurrent rendering | `RenderCache` serialises renders on one `CGPDFDocument`. The spike showed 4× scaling from sharing the document across threads without crashing, but Apple does not document that as safe, and serial rendering is fast enough. Revisit only if M1 profiling shows queueing. | Fable |
