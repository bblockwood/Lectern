// Builds the macOS AppIcon asset catalog from Lectern-2048.png (Ben's full-bleed square artwork).
//
//   swift Design/AppIcon/make-appicon.swift
//
// A classic Mac app icon carries its own rounded-square shape with transparent corners: the artwork is scaled
// to the 824/1024 body of Apple's icon grid, masked with continuous corners (radius 185.4/1024), and written
// at the ten sizes the catalog expects, plus a 1024 preview next to the sources.
import AppKit
import SwiftUI

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = scriptDir.deletingLastPathComponent().deletingLastPathComponent()
let source = scriptDir.appendingPathComponent("Lectern-2048.png")
let appiconset = root.appendingPathComponent("Apps/macOS/Assets.xcassets/AppIcon.appiconset")
guard let artwork = NSImage(contentsOf: source) else { fatalError("cannot read \(source.path)") }

struct MacIcon: View {
    let artwork: NSImage
    let canvas: CGFloat
    var body: some View {
        let body = canvas * 824 / 1024
        ZStack {
            Color.clear
            Image(nsImage: artwork)
                .resizable()
                .interpolation(.high)
                .frame(width: body, height: body)
                .clipShape(RoundedRectangle(cornerRadius: canvas * 185.4 / 1024, style: .continuous))
        }
        .frame(width: canvas, height: canvas)
    }
}

@MainActor
func render(_ points: CGFloat, scale: CGFloat) -> Data {
    let renderer = ImageRenderer(content: MacIcon(artwork: artwork, canvas: points))
    renderer.scale = scale
    guard let cg = renderer.cgImage else { fatalError("render failed at \(points)@\(scale)x") }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
}

try? FileManager.default.createDirectory(at: appiconset, withIntermediateDirectories: true)
var images: [[String: String]] = []
for (size, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let name = "icon_\(size)x\(size)@\(scale)x.png"
    try! MainActor.assumeIsolated { render(CGFloat(size), scale: CGFloat(scale)) }.write(to: appiconset.appendingPathComponent(name))
    images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
}
let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try! JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]).write(to: appiconset.appendingPathComponent("Contents.json"))
try! MainActor.assumeIsolated { render(1024, scale: 1) }.write(to: scriptDir.appendingPathComponent("Lectern-mac-1024.png"))
print("wrote \(images.count) images to \(appiconset.path)")
