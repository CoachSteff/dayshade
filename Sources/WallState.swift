import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class WallState {
    var userPaused = false
    var systemAsleep = false
    var showLogo: Bool { didSet { UserDefaults.standard.set(showLogo, forKey: "showLogo") } }
    var previewStart: Date?

    // Location for sunrise/sunset. Defaults to Brussels; change with `defaults write be.thehouseofcoaching.wall latitude 51.05`
    let latitude: Double
    let longitude: Double
    // For testing: `-simulatedHour 19.5` on the command line pins the clock.
    let simulatedHour: Double?

    private var darkFrom = 0.0
    private var darkTo = 0.0
    private var darkChanged = Date.distantPast

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["showLogo": true, "latitude": 50.85, "longitude": 4.35])
        showLogo = d.bool(forKey: "showLogo")
        latitude = d.double(forKey: "latitude")
        longitude = d.double(forKey: "longitude")
        simulatedHour = d.object(forKey: "simulatedHour") != nil ? d.double(forKey: "simulatedHour") : nil
    }

    var fps: Double { ProcessInfo.processInfo.isLowPowerModeEnabled ? 15 : 30 }

    func setDark(_ dark: Bool, animated: Bool = true) {
        let target = dark ? 1.0 : 0.0
        guard target != darkTo else { return }
        darkFrom = animated ? darkness(at: Date()) : target
        darkTo = target
        darkChanged = Date()
    }

    /// 0 = light mode, 1 = dark mode, with a slow 4-second crossfade in between.
    func darkness(at now: Date) -> Double {
        let p = min(1, max(0, now.timeIntervalSince(darkChanged) / 4))
        let s = p * p * (3 - 2 * p)
        return darkFrom + (darkTo - darkFrom) * s
    }

    /// The time the colours should reflect: real time, a pinned hour, or a sped-up preview day.
    func clock(at now: Date) -> Date {
        if let start = previewStart {
            let elapsed = now.timeIntervalSince(start)
            if elapsed > 60 { previewStart = nil; return now }
            let midnight = Calendar.current.startOfDay(for: now)
            let startOffset = start.timeIntervalSince(midnight)
            return midnight.addingTimeInterval((startOffset + elapsed / 60 * 86400).truncatingRemainder(dividingBy: 86400))
        }
        if let h = simulatedHour {
            return Calendar.current.startOfDay(for: now).addingTimeInterval(h * 3600)
        }
        return now
    }
}

@MainActor @Observable
final class WindowState {
    var visible = true
}
