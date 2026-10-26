import CoreGraphics
import Foundation

/// Integer pixel dimensions of a bitmap.
public struct PixelSize: Hashable, Sendable {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = max(1, width)
        self.height = max(1, height)
    }

    public var bytes: Int { width * height * 4 }
    public var cgSize: CGSize { CGSize(width: width, height: height) }

    /// Largest size with `aspectRatio` (width / height) that fits inside `bounds`.
    public static func fit(aspectRatio: CGFloat, in bounds: PixelSize) -> PixelSize {
        guard aspectRatio > 0 else { return bounds }
        let boundsRatio = CGFloat(bounds.width) / CGFloat(bounds.height)
        if aspectRatio >= boundsRatio {
            return PixelSize(width: bounds.width, height: Int((CGFloat(bounds.width) / aspectRatio).rounded()))
        } else {
            return PixelSize(width: Int((CGFloat(bounds.height) * aspectRatio).rounded()), height: bounds.height)
        }
    }
}

/// A sub-rectangle of the page in normalised coordinates of the rotated page, origin top-left.
/// `.full` is the whole page; notes-split mode (SPEC §5.1.4) uses the slide half.
public struct CropRect: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public static let full = CropRect(x: 0, y: 0, width: 1, height: 1)
    public static let leftHalf = CropRect(x: 0, y: 0, width: 0.5, height: 1)
    public static let rightHalf = CropRect(x: 0.5, y: 0, width: 0.5, height: 1)
    public static let topHalf = CropRect(x: 0, y: 0, width: 1, height: 0.5)
    public static let bottomHalf = CropRect(x: 0, y: 0.5, width: 1, height: 0.5)

    public var isFull: Bool { self == .full }
}

/// Identifies a rendered bitmap (SPEC §3.3): page, pixel size, crop and colour space.
public struct RenderRequest: Hashable, Sendable {
    public var pageIndex: Int
    public var pixelSize: PixelSize
    public var crop: CropRect
    public var colorSpace: ColorSpaceID

    public init(pageIndex: Int, pixelSize: PixelSize, crop: CropRect = .full, colorSpace: ColorSpaceID = .sRGB) {
        self.pageIndex = pageIndex
        self.pixelSize = pixelSize
        self.crop = crop
        self.colorSpace = colorSpace
    }
}

/// A hashable stand-in for a `CGColorSpace`. Named spaces map directly; display profiles are keyed by their ICC data.
public struct ColorSpaceID: Hashable, Sendable, CustomStringConvertible {
    public let name: String
    private let iccData: Data?

    public static let sRGB = ColorSpaceID(name: CGColorSpace.sRGB as String, iccData: nil)
    public static let displayP3 = ColorSpaceID(name: CGColorSpace.displayP3 as String, iccData: nil)

    private init(name: String, iccData: Data?) {
        self.name = name
        self.iccData = iccData
    }

    /// Captures any RGB colour space; falls back to sRGB for spaces that are neither named nor ICC-based.
    public init(_ colorSpace: CGColorSpace) {
        if let cfName = colorSpace.name {
            self.init(name: cfName as String, iccData: nil)
        } else if let icc = colorSpace.copyICCData() as Data? {
            self.init(name: "icc-\(icc.hashValue)", iccData: icc)
        } else {
            self = .sRGB
        }
    }

    public var cgColorSpace: CGColorSpace {
        if let iccData, let cs = CGColorSpace(iccData: iccData as CFData) { return cs }
        return CGColorSpace(name: name as CFString) ?? CGColorSpace(name: CGColorSpace.sRGB)!
    }

    public var description: String { name }
}
