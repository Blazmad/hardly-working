#!/usr/bin/env swift
import CoreGraphics
import Foundation

/// Le compteur candidat pour l'app : ~0 correspond à kCGAnyInputEventType
/// (n'importe quel événement clavier ou souris).
func cgIdleSeconds() -> TimeInterval {
    let anyInput = CGEventType(rawValue: ~0)!
    return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
}

/// La référence connue : le compteur que lit déjà la version bash en production.
func ioregIdleSeconds() -> TimeInterval {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
    process.arguments = ["-c", "IOHIDSystem"]
    let pipe = Pipe()
    process.standardOutput = pipe
    try? process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    guard let line = output.split(separator: "\n").first(where: { $0.contains("HIDIdleTime") }),
          let raw = line.split(separator: "=").last,
          let nanoseconds = Double(raw.trimmingCharacters(in: .whitespaces))
    else { return -1 }
    return nanoseconds / 1_000_000_000
}

/// Déplace le curseur d'un pixel puis le ramène. Aucun clic.
func jiggleOnce() {
    let origin = CGEvent(source: nil)?.location ?? .zero
    for point in [CGPoint(x: origin.x + 1, y: origin.y), origin] {
        CGEvent(mouseEventSource: nil,
                mouseType: .mouseMoved,
                mouseCursorPosition: point,
                mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }
}

print("=== Hypothesis 1: does CGEventSource read the same counter as ioreg? ===")
print("Do not touch the mouse or keyboard for the next 12 seconds.")
for step in 1...4 {
    Thread.sleep(forTimeInterval: 3)
    print(String(format: "t=%2ds   CGEventSource=%6.1fs   ioreg=%6.1fs",
                 step * 3, cgIdleSeconds(), ioregIdleSeconds()))
}

print("")
print("=== Hypothesis 2: does a synthetic mouse event reset the counter? ===")
let before = cgIdleSeconds()
jiggleOnce()
Thread.sleep(forTimeInterval: 0.5)
let after = cgIdleSeconds()
print(String(format: "before=%.1fs   after=%.1fs", before, after))
print(after < before ? "PASS: the counter dropped." : "FAIL: the counter did not move.")
