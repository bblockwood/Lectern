import AppKit
import PresenterCore
import QuartzCore

/// A CALayer-backed slide surface (SPEC §3.3). It only ever swaps `contents` for a finished bitmap; it never
/// draws, never clears to blank between pages, and letterboxes with the surround colour.
final class SlideSurfaceView: NSView {
    private let slideLayer = CALayer()
    private var imageAspect: CGFloat?
    private var displayLink: CADisplayLink?

    var surroundColor: CGColor = CGColor(gray: 0, alpha: 1) {
        didSet { layer?.backgroundColor = surroundColor }
    }
    /// Called after layout, backing-scale or window changes; the controller re-fits the page.
    var onGeometryChange: (() -> Void)?
    /// Called on the first display-link tick after `requestFrameCallback()`: the tick's own vsync timestamp
    /// (the earliest the committed frame can be on glass) and its target timestamp (the latest).
    var onFrame: ((_ vsync: CFTimeInterval, _ target: CFTimeInterval) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.backgroundColor = surroundColor
        slideLayer.contentsGravity = .resizeAspect
        slideLayer.minificationFilter = .linear
        slideLayer.magnificationFilter = .linear
        slideLayer.isOpaque = true
        slideLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(),
                              "backgroundColor": NSNull(), "hidden": NSNull(), "contentsScale": NSNull()]
        layer?.addSublayer(slideLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    // MARK: - Geometry

    /// The view's size in backing pixels, nil before it is in a window.
    var pixelBounds: PixelSize? {
        guard window != nil, bounds.width >= 1, bounds.height >= 1 else { return nil }
        let backing = convertToBacking(bounds)
        return PixelSize(width: Int(backing.width.rounded()), height: Int(backing.height.rounded()))
    }

    /// The colour space of the screen the view is on, so renders match the display (SPEC §3.3).
    var colorSpaceID: ColorSpaceID {
        if let cs = window?.screen?.colorSpace?.cgColorSpace { return ColorSpaceID(cs) }
        return .sRGB
    }

    override func layout() {
        super.layout()
        updateSlideLayerFrame()
        onGeometryChange?()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        slideLayer.contentsScale = window?.backingScaleFactor ?? 2
        onGeometryChange?()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        slideLayer.contentsScale = window?.backingScaleFactor ?? 2
        displayLink?.invalidate()
        displayLink = nil
        onGeometryChange?()
    }

    // MARK: - Content

    func show(image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageAspect = CGFloat(image.width) / CGFloat(image.height)
        slideLayer.backgroundColor = nil
        slideLayer.contents = image
        slideLayer.isHidden = false
        updateSlideLayerFrame()
        CATransaction.commit()
    }

    func showSolid(_ color: CGColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageAspect = nil
        slideLayer.contents = nil
        slideLayer.backgroundColor = color
        slideLayer.frame = bounds
        slideLayer.isHidden = false
        CATransaction.commit()
    }

    func showNothing() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        slideLayer.isHidden = true
        CATransaction.commit()
    }

    private func updateSlideLayerFrame() {
        guard let aspect = imageAspect else {
            if slideLayer.backgroundColor != nil { slideLayer.frame = bounds }
            return
        }
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        var fitted = CGSize(width: size.width, height: size.width / aspect)
        if fitted.height > size.height { fitted = CGSize(width: size.height * aspect, height: size.height) }
        slideLayer.frame = CGRect(x: ((size.width - fitted.width) / 2).rounded(), y: ((size.height - fitted.height) / 2).rounded(),
                                  width: fitted.width.rounded(), height: fitted.height.rounded())
    }

    // MARK: - Frame callback (latency measurement)

    /// Arms a one-shot display link for the next frame. Nothing fires while the window is occluded or off screen.
    func requestFrameCallback() {
        guard window != nil else { return }
        displayLink?.invalidate()
        let link = displayLink(target: self, selector: #selector(displayLinkFired(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        link.invalidate()
        if displayLink === link { displayLink = nil }
        onFrame?(link.timestamp, link.targetTimestamp)
    }
}
