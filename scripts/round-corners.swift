#!/usr/bin/env swift

// Makes every pixel outside the icon's rounded rectangle transparent.
//
// qlmanage flattens any SVG render onto an OPAQUE WHITE background. The PNG it
// produces does carry an alpha channel, but the corners left empty by the SVG's
// rx="232" come out as (255,255,255,255) - opaque white, not transparent.
// Invisible in the macOS 26 Dock, which re-masks app icons, and plainly visible
// everywhere else: the GitHub README, a dark browser tab strip, and macOS 14 and
// 15, which show the PNG as-is.
//
// The radius reuses the SVG's own proportion (232 of 1024) so the cut follows
// the original outline instead of inventing a different one.
//
// Uses only frameworks shipped with macOS. Usage:
//   swift scripts/round-corners.swift input.png output.png

import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("round-corners: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage: round-corners.swift <input.png> <output.png>") }

let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

guard let image = NSImage(contentsOf: input),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("cannot read: \(input.path)")
}

let width = source.width
let height = source.height
let radius = CGFloat(width) * 232.0 / 1024.0

guard let context = CGContext(data: nil,
                              width: width,
                              height: height,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fail("cannot create the drawing context")
}

let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
context.clear(bounds)
context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
context.clip()
context.draw(source, in: bounds)

guard let masked = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: masked).representation(using: .png, properties: [:]) else {
    fail("cannot encode the PNG")
}

do { try data.write(to: output) }
catch { fail("cannot write: \(output.path) - \(error.localizedDescription)") }
