#!/usr/bin/env swift

// Rend transparents les pixels situés hors du rectangle arrondi de l'icône.
//
// Pourquoi : qlmanage aplatit tout rendu SVG sur un fond BLANC OPAQUE. Le
// PNG produit a bien un canal alpha, mais les coins laissés vides par le
// rx="232" du SVG en ressortent en (255,255,255,255) — du blanc opaque, pas
// du transparent. Invisible dans le Dock de macOS 26, qui remasque lui-même
// les icônes ; bien visible partout ailleurs (README GitHub, macOS 14 et 15,
// qui affichent le PNG tel quel).
//
// Le rayon reprend exactement la proportion du SVG (232 sur 1024) pour que la
// découpe suive le tracé d'origine au lieu d'en inventer un autre.
//
// N'utilise que des frameworks livrés avec macOS. Usage :
//   swift scripts/round-corners.swift entrée.png sortie.png

import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("round-corners: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 3 else { fail("usage : round-corners.swift <entrée.png> <sortie.png>") }

let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])

guard let image = NSImage(contentsOf: input),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("lecture impossible : \(input.path)")
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
    fail("création du contexte impossible")
}

let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
context.clear(bounds)
context.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
context.clip()
context.draw(source, in: bounds)

guard let masked = context.makeImage(),
      let data = NSBitmapImageRep(cgImage: masked).representation(using: .png, properties: [:]) else {
    fail("encodage PNG impossible")
}

do { try data.write(to: output) }
catch { fail("écriture impossible : \(output.path) — \(error.localizedDescription)") }
