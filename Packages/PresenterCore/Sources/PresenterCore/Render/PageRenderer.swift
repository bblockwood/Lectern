import CoreGraphics
import Foundation

/// Rasterises one page region into a BGRX bitmap with Apple's renderer (SPEC §3.3, Spike C recipe).
/// Draws page content only: annotations never reach the bitmap.
public enum PageRenderer {
    public static func render(page: CGPDFPage, pageSize: CGSize, request: RenderRequest) -> CGImage? {
        let size = request.pixelSize
        let colorSpace = request.colorSpace.cgColorSpace
        guard let ctx = CGContext(data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        // Some PDFs have transparent backgrounds: paint white first.
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        // Destination rect of the whole page, positioned so that the crop region fills the context.
        let crop = request.crop
        let fullWidth = CGFloat(size.width) / crop.width
        let fullHeight = CGFloat(size.height) / crop.height
        let originX = -crop.x * fullWidth
        let originY = -(1 - crop.y - crop.height) * fullHeight   // CG origin is bottom-left; crop is top-left based
        let target = CGRect(x: originX, y: originY, width: fullWidth, height: fullHeight)

        ctx.interpolationQuality = .high
        ctx.setShouldAntialias(true)
        ctx.setAllowsFontSmoothing(true)
        ctx.setShouldSmoothFonts(true)
        ctx.saveGState()
        ctx.concatenate(page.getDrawingTransform(.cropBox, rect: target, rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(page)
        ctx.restoreGState()
        return ctx.makeImage()
    }
}
