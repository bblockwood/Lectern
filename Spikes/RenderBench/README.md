# Spike C: render benchmark

Times per-page rasterisation of every fixture with `CGContext.drawPDFPage` at 1080p, 1440p and 4K,
checks that annotations never reach the bitmap, measures thumbnail throughput, concurrency scaling,
colour-space cost and the warm-cache layer handoff. Findings: `docs/spikes/C-render.md`.

    swift run -c release RenderBench ../../Fixtures            # full run, Markdown to stdout
    swift run -c release RenderBench ../../Fixtures --quick    # skip huge.pdf at 1440p/4K
    swift run -c release RenderBench ../../Fixtures --dump DIR # also write 1080p PNGs of every page to DIR
