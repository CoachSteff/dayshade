import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class WallState {
    var settings: WallSettings {
        didSet { settingsChanged(from: oldValue) }
    }
    var userPaused = false
    var systemAsleep = false
    var previewStart: Date?
    var scrubHour: Double?           // set while scrubbing the time slider in Settings
    @ObservationIgnored var onSettingsChange: (() -> Void)?
    @ObservationIgnored var persist = true

    // For testing: `-simulatedHour 19.5` on the command line pins the clock.
    let simulatedHour: Double?

    private var systemDark = false
    private var darkFrom = 0.0
    private var darkTo = 0.0
    private var darkChanged = Date.distantPast
    private var phaseAnchor = Date().timeIntervalSinceReferenceDate
    private var phaseAnchorTime = Date()
    private var fromPalette: (Palette, Double)?
    private var paletteChanged = Date.distantPast

    init() {
        settings = WallSettings.load()
        let d = UserDefaults.standard
        simulatedHour = d.object(forKey: "simulatedHour") != nil ? d.double(forKey: "simulatedHour") : nil
    }

    var fps: Double {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? min(10, settings.frameRate.fps) : settings.frameRate.fps
    }

    private func settingsChanged(from old: WallSettings) {
        let now = Date()
        if old.motion != settings.motion {
            phaseAnchor += now.timeIntervalSince(phaseAnchorTime) * old.motion
            phaseAnchorTime = now
        }
        if old.scheme != settings.scheme || old.latitude != settings.latitude || old.longitude != settings.longitude {
            fromPalette = basePalette(old, at: now)
            paletteChanged = now
        }
        if old.appearance != settings.appearance { applyDark(animated: true) }
        if persist { settings.save() }
        onSettingsChange?()
    }

    /// Runs 24 hours of colour in one minute.
    func playDay() {
        scrubHour = nil
        let start = Date()
        previewStart = start
        DispatchQueue.main.asyncAfter(deadline: .now() + 61) { [weak self] in
            if self?.previewStart == start { self?.previewStart = nil }
        }
    }

    // MARK: Light and dark

    func setSystemDark(_ dark: Bool, animated: Bool) {
        systemDark = dark
        applyDark(animated: animated)
    }

    var isDark: Bool {
        switch settings.appearance {
        case .auto: systemDark
        case .light: false
        case .dark: true
        }
    }

    private func applyDark(animated: Bool) {
        let target = isDark ? 1.0 : 0.0
        guard target != darkTo || !animated else { return }
        darkFrom = animated ? darkness(at: Date()) : target
        darkTo = target
        darkChanged = Date()
    }

    /// 0 = light, 1 = dark, with a slow 4-second crossfade in between.
    func darkness(at now: Date) -> Double {
        let p = min(1, max(0, now.timeIntervalSince(darkChanged) / 4))
        return darkFrom + (darkTo - darkFrom) * p * p * (3 - 2 * p)
    }

    // MARK: Time and colour

    /// Animation time in seconds; runs faster or slower with the Motion slider without jumping.
    func phase(at now: Date) -> Double {
        phaseAnchor + now.timeIntervalSince(phaseAnchorTime) * settings.motion
    }

    /// The time the colours should reflect: real time, a scrubbed or pinned hour, or a sped-up preview day.
    func clock(at now: Date) -> Date {
        let midnight = Calendar.current.startOfDay(for: now)
        if let start = previewStart, now.timeIntervalSince(start) < 60 {
            let elapsed = now.timeIntervalSince(start)
            let offset = start.timeIntervalSince(midnight) + elapsed / 60 * 86400
            return midnight.addingTimeInterval(offset.truncatingRemainder(dividingBy: 86400))
        }
        if let h = scrubHour ?? simulatedHour { return midnight.addingTimeInterval(h * 3600) }
        return now
    }

    func sun(at now: Date) -> SunPosition {
        sunPosition(at: clock(at: now), latitude: settings.latitude, longitude: settings.longitude)
    }

    private func basePalette(_ s: WallSettings, at now: Date) -> (Palette, Double) {
        let sun = sunPosition(at: clock(at: now), latitude: s.latitude, longitude: s.longitude)
        let lookup = { (id: String) in
            s.schemes.first { $0.id == id }?.palette ?? ColorSchemeItem.builtins.first { $0.id == id }!.palette
        }
        let (cycle, night) = paletteForSun(sun, lookup)
        if s.scheme == "cycle" { return (cycle, night) }
        return (s.schemes.first { $0.id == s.scheme }?.palette ?? cycle, night)
    }

    /// The palette to draw now, crossfading for 1.5 s after the scheme changes.
    func palette(at now: Date) -> (Palette, Double) {
        let target = basePalette(settings, at: now)
        guard let from = fromPalette else { return target }
        let p = min(1, max(0, now.timeIntervalSince(paletteChanged) / 1.5))
        if p >= 1 { return target }
        let s = p * p * (3 - 2 * p)
        return (Palette.mix(from.0, target.0, s), from.1 + (target.1 - from.1) * s)
    }
}

/// What a wallpaper window knows about its display, so bars can line up with the menu bar and Dock.
@MainActor @Observable
final class WindowState {
    var visible = true
    var isMain = true
    var screenSize = CGSize(width: 1512, height: 982)
    var menuBarHeight = 33.0
    var dockInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    init(screen: NSScreen? = nil) {
        guard let screen else { return }
        update(from: screen)
    }

    func update(from screen: NSScreen) {
        let f = screen.frame, v = screen.visibleFrame
        isMain = screen == NSScreen.screens.first
        screenSize = f.size
        menuBarHeight = max(f.maxY - v.maxY, screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        dockInsets = NSEdgeInsets(top: 0, left: v.minX - f.minX, bottom: v.minY - f.minY, right: f.maxX - v.maxX)
    }
}
