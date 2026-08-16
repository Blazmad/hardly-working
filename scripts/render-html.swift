#!/usr/bin/env swift

// Rend un fichier HTML local en PNG, à des dimensions exactes.
//
// Sert à fabriquer l'image d'aperçu Open Graph depuis assets/og-image.html,
// ce qui évite de dessiner la carte à la main : elle reprend littéralement les
// couleurs et les polices de la landing page, dans le même moteur de rendu.
//
// Passe par WebKit plutôt que par un navigateur installé, pour que le dépôt
// reste constructible avec les seuls outils livrés par macOS. Usage :
//   swift scripts/render-html.swift page.html sortie.png 1200 630

import AppKit
import WebKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-html: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 5,
      let width = Double(args[3]), let height = Double(args[4]) else {
    fail("usage : render-html.swift <page.html> <sortie.png> <largeur> <hauteur>")
}

let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
guard FileManager.default.fileExists(atPath: input.path) else { fail("introuvable : \(input.path)") }

// NSApplication doit exister pour que WebKit dispose d'une boucle d'exécution.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let frame = NSRect(x: 0, y: 0, width: width, height: height)
let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())

final class Delegate: NSObject, WKNavigationDelegate {
    var finished = false
    var failure: String?
    func webView(_ w: WKWebView, didFinish n: WKNavigation!) { finished = true }
    func webView(_ w: WKWebView, didFail n: WKNavigation!, withError e: Error) {
        failure = e.localizedDescription; finished = true
    }
    func webView(_ w: WKWebView, didFailProvisionalNavigation n: WKNavigation!, withError e: Error) {
        failure = e.localizedDescription; finished = true
    }
}

let delegate = Delegate()
webView.navigationDelegate = delegate
webView.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())

// Attente du chargement, avec plafond pour ne jamais bloquer indéfiniment.
let loadDeadline = Date().addingTimeInterval(30)
while !delegate.finished && Date() < loadDeadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
if let failure = delegate.failure { fail("chargement échoué : \(failure)") }
guard delegate.finished else { fail("délai dépassé au chargement") }

// didFinish signale la fin du chargement, pas la fin de la mise en page ni la
// résolution des polices. Une image capturée trop tôt sort sans son texte.
let settleDeadline = Date().addingTimeInterval(1.0)
while Date() < settleDeadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
}

let config = WKSnapshotConfiguration()
config.rect = frame

var snapshot: NSImage?
var snapshotError: String?
var done = false
webView.takeSnapshot(with: config) { image, error in
    snapshot = image
    snapshotError = error?.localizedDescription
    done = true
}

let snapDeadline = Date().addingTimeInterval(30)
while !done && Date() < snapDeadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
if let snapshotError { fail("capture échouée : \(snapshotError)") }
guard let image = snapshot,
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("capture vide")
}

guard let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
    fail("encodage PNG impossible")
}

do { try data.write(to: output) }
catch { fail("écriture impossible : \(output.path) — \(error.localizedDescription)") }

FileHandle.standardOutput.write(Data("rendu \(cg.width)×\(cg.height) → \(output.path)\n".utf8))
