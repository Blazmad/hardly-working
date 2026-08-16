#!/usr/bin/env swift

// Renders a local HTML file to a PNG at exact dimensions.
//
// Used to build the Open Graph preview image from assets/og-image.html, which
// avoids drawing the card by hand: it reuses the landing page's own colours and
// typefaces, in the same rendering engine.
//
// Goes through WebKit rather than an installed browser, so the repository stays
// buildable with only the tools macOS ships. Usage:
//   swift scripts/render-html.swift page.html output.png 1200 630

import AppKit
import WebKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("render-html: \(message)\n".utf8))
    exit(1)
}

let args = CommandLine.arguments
guard args.count == 5,
      let width = Double(args[3]), let height = Double(args[4]) else {
    fail("usage: render-html.swift <page.html> <output.png> <width> <height>")
}

let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
guard FileManager.default.fileExists(atPath: input.path) else { fail("not found: \(input.path)") }

// WebKit needs an NSApplication for its run loop to exist.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let frame = NSRect(x: 0, y: 0, width: width, height: height)
let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())

final class Delegate: NSObject, WKNavigationDelegate {
    var finished = false
    var failure: String?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finished = true
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failure = error.localizedDescription
        finished = true
    }

    func webView(_ webView: WKWebView,
                 didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        failure = error.localizedDescription
        finished = true
    }
}

let delegate = Delegate()
webView.navigationDelegate = delegate
webView.loadFileURL(input, allowingReadAccessTo: input.deletingLastPathComponent())

let loadDeadline = Date().addingTimeInterval(30)
while !delegate.finished && Date() < loadDeadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
if let failure = delegate.failure { fail("loading failed: \(failure)") }
guard delegate.finished else { fail("timed out while loading") }

// didFinish reports the end of loading, not the end of layout nor font
// resolution. A snapshot taken too early comes out without its text.
let settleDeadline = Date().addingTimeInterval(1.0)
while Date() < settleDeadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
}

let configuration = WKSnapshotConfiguration()
configuration.rect = frame

var snapshot: NSImage?
var snapshotError: String?
var done = false
webView.takeSnapshot(with: configuration) { image, error in
    snapshot = image
    snapshotError = error?.localizedDescription
    done = true
}

let snapshotDeadline = Date().addingTimeInterval(30)
while !done && Date() < snapshotDeadline {
    RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
}
if let snapshotError { fail("snapshot failed: \(snapshotError)") }
guard let image = snapshot,
      let rendered = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("empty snapshot")
}

guard let data = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else {
    fail("cannot encode the PNG")
}

do { try data.write(to: output) }
catch { fail("cannot write: \(output.path) - \(error.localizedDescription)") }

FileHandle.standardOutput.write(Data("rendered \(rendered.width)x\(rendered.height) -> \(output.path)\n".utf8))
