import AppKit
import PresenterCore
import PresenterProtocol
import QuartzCore

/// A CALayer-backed slide surface (SPEC §3.3). It only ever swaps `contents` for a finished bitmap; it never
/// draws, never clears to blank between pages, and letterboxes with the surround colour.
final class SlideSurfaceView: NSView {
    private let slideLayer = CALayer()
    private var imageAspect: CGFloat?
    private var displayLink: CADisplayLink?
    private var trackingArea: NSTrackingArea?

    /// Link rects of the page on screen (SPEC §4.3). Clicks inside them call `onLinkActivate`.
    var links: [PageLink] = [] {
        didSet { if links.isEmpty != oldValue.isEmpty { window?.invalidateCursorRects(for: self) } }
    }
    var onLinkActivate: ((LinkID) -> Void)?

    // Pointer and ink (SPEC §6.4, §8). Coordinates are normalised to the displayed slide image.
    var pointerTrackingEnabled = false
    var inkTrackingEnabled = false
    var onPointerMove: ((NormalizedPoint) -> Void)?
    var onPointerExit: (() -> Void)?
    var onInkBegin: ((NormalizedPoint) -> Void)?
    var onInkAppend: ((NormalizedPoint) -> Void)?
    var onInkEnd: (() -> Void)?

    private let pointerLayer = CALayer()
    private let inkLayer = CALayer()
    private var strokeLayers: [CAShapeLayer] = []
    private var isInking = false

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

        inkLayer.actions = ["bounds": NSNull(), "position": NSNull(), "sublayers": NSNull()]
        slideLayer.addSublayer(inkLayer)

        pointerLayer.isHidden = true
        pointerLayer.backgroundColor = CGColor(red: 1, green: 0.1, blue: 0.1, alpha: 1)
        pointerLayer.shadowColor = CGColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
        pointerLayer.shadowOpacity = 0.9
        pointerLayer.shadowOffset = .zero
        pointerLayer.actions = ["position": NSNull(), "hidden": NSNull(), "bounds": NSNull(), "cornerRadius": NSNull()]
        slideLayer.addSublayer(pointerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { false }
    /// Clicks on the audience window (which never becomes key) must still reach us.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Where the slide image sits inside the view, in view coordinates.
    var slideFrame: CGRect { slideLayer.frame }

    // MARK: - Links

    /// The link under a point in view coordinates, if any.
    func link(at point: NSPoint) -> PageLink? {
        guard !links.isEmpty, let normalized = normalizedPoint(for: point) else { return nil }
        return LinkHitTester.link(at: normalized, in: links)
    }

    /// Maps a view point to normalised slide coordinates (origin top-left), nil outside the slide.
    func normalizedPoint(for point: NSPoint) -> NormalizedPoint? {
        let frame = slideLayer.frame
        guard frame.width > 0, frame.height > 0, frame.contains(point) else { return nil }
        return NormalizedPoint(x: (point.x - frame.minX) / frame.width, y: 1 - (point.y - frame.minY) / frame.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if inkTrackingEnabled {
            NSCursor.crosshair.set()
        } else if link(at: point) != nil {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
        if pointerTrackingEnabled {
            if let normalized = normalizedPoint(for: point) { onPointerMove?(normalized) } else { onPointerExit?() }
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        if pointerTrackingEnabled { onPointerExit?() }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if inkTrackingEnabled, let normalized = normalizedPoint(for: point) {
            isInking = true
            onInkBegin?(normalized)
            return
        }
        if let link = link(at: point) {
            onLinkActivate?(link.id)
        } else {
            super.mouseDown(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isInking else { return super.mouseDragged(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        if let normalized = normalizedPoint(for: point) { onInkAppend?(normalized) }
    }

    override func mouseUp(with event: NSEvent) {
        guard isInking else { return super.mouseUp(with: event) }
        isInking = false
        onInkEnd?()
    }

    // MARK: - Pointer and ink rendering

    /// Shows the pointer at a normalised position (nil hides it). A fading copy is left behind as the trail.
    func showPointer(at position: NormalizedPoint?) {
        guard let position else {
            pointerLayer.isHidden = true
            return
        }
        let frame = slideLayer.bounds
        let diameter = max(4, frame.height * 0.012)
        let center = CGPoint(x: frame.minX + position.x * frame.width, y: frame.minY + (1 - position.y) * frame.height)
        if !pointerLayer.isHidden, pointerLayer.position != center {
            let trail = CALayer()
            trail.bounds = pointerLayer.bounds
            trail.cornerRadius = pointerLayer.cornerRadius
            trail.position = pointerLayer.position
            trail.backgroundColor = pointerLayer.backgroundColor
            trail.opacity = 0.6
            slideLayer.insertSublayer(trail, below: pointerLayer)
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0.6
            fade.toValue = 0
            fade.duration = 0.3
            fade.isRemovedOnCompletion = false
            fade.fillMode = .forwards
            trail.add(fade, forKey: "fade")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { trail.removeFromSuperlayer() }
        }
        pointerLayer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        pointerLayer.cornerRadius = diameter / 2
        pointerLayer.shadowRadius = diameter * 0.6
        pointerLayer.position = center
        pointerLayer.isHidden = false
    }

    var inkStrokeCount: Int { strokeLayers.count }

    /// Redraws strokes as vectors in slide coordinates; `opacity(for:)` lets ephemeral strokes fade.
    func showInk(_ strokes: [InkStroke], opacity: (InkStroke) -> Float) {
        for layer in strokeLayers { layer.removeFromSuperlayer() }
        strokeLayers.removeAll()
        let frame = slideLayer.bounds
        inkLayer.frame = frame
        guard frame.width > 0, frame.height > 0 else { return }
        for stroke in strokes where stroke.points.count >= 1 {
            let path = CGMutablePath()
            let points = stroke.points.map { CGPoint(x: $0.x * frame.width, y: (1 - $0.y) * frame.height) }
            path.move(to: points[0])
            if points.count == 1 { path.addLine(to: points[0]) }
            for point in points.dropFirst() { path.addLine(to: point) }
            let shape = CAShapeLayer()
            shape.path = path
            shape.strokeColor = CGColor(red: stroke.color.red, green: stroke.color.green, blue: stroke.color.blue, alpha: stroke.color.alpha)
            shape.fillColor = nil
            shape.lineWidth = max(1, stroke.width * frame.height)
            shape.lineCap = .round
            shape.lineJoin = .round
            shape.opacity = opacity(stroke)
            shape.actions = ["opacity": NSNull(), "path": NSNull()]
            inkLayer.addSublayer(shape)
            strokeLayers.append(shape)
        }
    }

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
        inkLayer.frame = slideLayer.bounds
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
