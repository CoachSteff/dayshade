import AppKit
import SwiftUI

// `THOC Wall --render out.png [--hour 7.5] [--dark] [--size 2560x1600]` writes a single frame and exits.
// Handy for previews, and for setting a matching still as the lock-screen wallpaper.
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
    MainActor.assumeIsolated {
        func value(_ flag: String) -> String? { args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
        let size = (value("--size") ?? "2560x1600").split(separator: "x").compactMap { Double($0) }
        let state = WallState()
        state.setDark(args.contains("--dark"), animated: false)
        var date = Date()
        if let h = value("--hour").flatMap(Double.init) {
            date = Calendar.current.startOfDay(for: date).addingTimeInterval(h * 3600)
        }
        let view = WallpaperView(state: state, window: WindowState(), fixedDate: date)
            .frame(width: size[0], height: size[1])
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cg = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("render failed\n".data(using: .utf8)!)
            exit(1)
        }
        try! png.write(to: URL(fileURLWithPath: args[i + 1]))
        exit(0)
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
