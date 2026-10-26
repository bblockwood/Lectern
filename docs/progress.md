# Progress

## M0: Spikes (branch `m0-spikes`)

Started 2026-10-25. Toolchain: Xcode 27.1 (SDKs macOS 27.0, iOS 27.1, watchOS 27.0; simulator runtimes iOS 26.5, watchOS 26.5), Swift 6.4, XcodeGen 2.45.4, xcbeautify, TeX Live 2021 with beamer, pdfpc, pdfcomment, pgfplots.

### Plan

1. **Fixtures first.** Write LaTeX sources for fixtures 1–8 and 10 in `Fixtures/src/`, a `Makefile` that runs latexmk, and derive `malformed.pdf` by truncating `basic-169.pdf`. Fixture 9 (`ppt-export`) is Ben's.
2. **Spike C, render benchmark** (`Spikes/RenderBench`, a SwiftPM executable). Render every page of every fixture at 1080p, 1440p and 4K with `CGContext.drawPDFPage`, report per-page timings, and check that annotation icons from fixtures 4–5 never reach the bitmap. Measure the warm-cache handoff cost. Output `docs/spikes/C-render.md`.
3. **Spike A, iPad external display** (`Spikes/ExternalDisplay`, XcodeGen project). Minimal UIKit-scene app with a shared counter, one view per screen, external scene declared with the non-interactive external-display role. Verify on the Simulator's external display; leave default/extended/Stage Manager and backgrounding behaviour on real hardware to Ben. Output `docs/spikes/A-external-display.md`.
4. **Spike B, Watch latency** (`Spikes/WatchLatency`, XcodeGen project): Watch app with a Next button on double tap, iPhone relay, Mac host. Transport A = WatchConnectivity → iPhone → Network framework/Bonjour → Mac. Transport B = Core Bluetooth, Mac as peripheral, Watch as central. Watch timestamps sends, host echoes, Watch computes RTT and reports median/p95. Transport A is verifiable on paired simulators; Transport B and the real numbers need hardware. Output `docs/spikes/B-watch-latency.md`.
5. **Report** here with known issues and a Ben device checklist, then merge `m0-spikes` into `main`.

Spikes are throwaway: each has its own `project.yml` or `Package.swift` under `Spikes/` so nothing leaks into the real targets.
