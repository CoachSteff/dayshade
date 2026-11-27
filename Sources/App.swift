import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let state = WallState()
    private var windows: [(NSWindow, WindowState)] = []
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private let previewWindow = WindowState(screen: NSScreen.screens.first)
    private var appearanceObservation: NSKeyValueObservation?
    private var syncTimer: Timer?
    private lazy var location = LocationService(state: state)

    func applicationDidFinishLaunching(_ note: Notification) {
        applyAppearance(animated: false)
        // Testing aid: `-snapshotSettings out.png -settingsPane logos` saves a picture of Settings and quits.
        if let out = UserDefaults.standard.string(forKey: "snapshotSettings") {
            state.persist = false
            openSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                func scrollers(_ v: NSView) -> [NSScrollView] { ((v as? NSScrollView).map { [$0] } ?? []) + v.subviews.flatMap(scrollers) }
                let content = self?.settingsWindow?.contentView
                let page = content.flatMap { scrollers($0).compactMap(\.documentView).max { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height } }
                if let view = page ?? content,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                NSApp.terminate(nil)
            }
            return
        }
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.applyAppearance(animated: true) }
        }

        buildWindows()
        buildMenu()
        state.onSettingsChange = { [weak self] in self?.applySettings() }
        applySettings()

        let nc = NotificationCenter.default
        nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.buildWindows() }
        }
        let ws = NSWorkspace.shared.notificationCenter
        for (name, asleep) in [(NSWorkspace.screensDidSleepNotification, true),
                               (NSWorkspace.screensDidWakeNotification, false),
                               (NSWorkspace.sessionDidResignActiveNotification, true),
                               (NSWorkspace.sessionDidBecomeActiveNotification, false)] {
            ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.state.systemAsleep = asleep
                    if !asleep { self?.location.refreshIfAuto() }
                }
            }
        }

        location.refreshIfAuto()
        if UserDefaults.standard.bool(forKey: "openSettings") { openSettings() }
    }

    /// Opening the app again from Finder (e.g. with the menu bar icon hidden) brings up Settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    private func applyAppearance(animated: Bool) {
        let forced = UserDefaults.standard.string(forKey: "forceAppearance")
        let dark = forced.map { $0 == "dark" }
            ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        state.setSystemDark(dark, animated: animated)
    }

    private var lastLoginOverlays: [Bool] = []

    private func applySettings() {
        statusItem?.isVisible = state.settings.showMenuIcon
        let login = [state.settings.loginScreenLogos, state.settings.loginScreenBars]
        if state.settings.syncSystemWallpaper {
            if syncTimer == nil {
                syncTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.syncSystemWallpaper() }
                }
                syncSystemWallpaper()
            } else if lastLoginOverlays != login {
                syncSystemWallpaper()
            }
            lastLoginOverlays = login
        } else {
            syncTimer?.invalidate()
            syncTimer = nil
        }
    }

    // One borderless window per display, sitting at desktop level: below the desktop icons, above the system wallpaper.
    private func buildWindows() {
        windows.forEach { $0.0.orderOut(nil) }
        previewWindow.update(from: NSScreen.screens.first ?? NSScreen.main!)
        windows = NSScreen.screens.map { screen in
            let win = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            win.setFrame(screen.frame, display: false)
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            win.ignoresMouseEvents = true
            win.isOpaque = true
            win.hasShadow = false
            win.backgroundColor = .black
            win.isReleasedWhenClosed = false
            let ws = WindowState(screen: screen)
            win.contentView = NSHostingView(rootView: WallpaperView(state: state, window: ws))
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: win, queue: .main) { [weak win] _ in
                Task { @MainActor in ws.visible = win?.occlusionState.contains(.visible) ?? true }
            }
            win.orderFront(nil)
            return (win, ws)
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sun.horizon", accessibilityDescription: "Dayshade")
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
    }

    // MARK: Settings window

    @objc func openSettings() {
        if settingsWindow == nil {
            let host = NSHostingController(rootView: SettingsView(state: state, preview: previewWindow, location: location,
                                                                  exportFrame: { [weak self] in self?.exportFrame() }))
            let win = NSWindow(contentViewController: host)
            win.title = "Dayshade"
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            win.setContentSize(NSSize(width: 860, height: 760))
            win.minSize = NSSize(width: 720, height: 520)
            win.isReleasedWhenClosed = false
            win.delegate = self
            win.center()
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                   object: win, queue: .main) { [weak self, weak win] _ in
                Task { @MainActor in self?.previewWindow.visible = win?.occlusionState.contains(.visible) ?? false }
            }
            settingsWindow = win
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ note: Notification) {
        guard (note.object as? NSWindow) == settingsWindow else { return }
        state.scrubHour = nil
    }

    // MARK: Stills

    private func renderStill(for ws: WindowState, scale: CGFloat, hideLogos: Bool = false, hideBars: Bool = false) -> Data? {
        let view = WallpaperView(state: state, window: ws, fixedDate: Date(), hideLogos: hideLogos, hideBars: hideBars)
            .frame(width: ws.screenSize.width, height: ws.screenSize.height)
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let cg = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }

    private func exportFrame() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "Dayshade \(Date().formatted(.dateTime.year().month().day().hour().minute())).png"
            .replacingOccurrences(of: ":", with: ".").replacingOccurrences(of: "/", with: "-")
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url,
              let png = renderStill(for: previewWindow, scale: NSScreen.screens.first?.backingScaleFactor ?? 2) else { return }
        try? png.write(to: url)
    }

    /// Saves a still per display and sets it as the macOS wallpaper, so the lock screen and Mission Control match.
    private func syncSystemWallpaper() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dayshade/Stills", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Int(Date().timeIntervalSince1970)
        for (win, ws) in windows {
            guard let screen = win.screen,
                  let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let png = renderStill(for: ws, scale: screen.backingScaleFactor,
                                        hideLogos: !state.settings.loginScreenLogos,
                                        hideBars: !state.settings.loginScreenBars) else { continue }
            // A new file name each time, because macOS caches wallpapers by path.
            let old = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
            for f in old where f.hasPrefix("\(id)-") { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) }
            let url = dir.appendingPathComponent("\(id)-\(stamp).png")
            guard (try? png.write(to: url)) != nil else { continue }
            try? NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    }

    // MARK: Menu actions

    @objc private func showAbout() {
        let body = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.paragraphSpacing = 6
        let credits = NSAttributedString(string: """
            A living wallpaper: soft gradients that follow the sun and your light or dark mode.

            Made by Steff Vanhaverbeke.

            Copyleft: free software under the GNU General Public License, version 3 or later. You may use, study, share and change it, as long as what you share stays under the same licence.

            The CoachSteff and The House of Coaching logos are not covered by this licence.

            Source code: github.com/CoachSteff/dayshade
            """, attributes: [.font: body, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para])
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Dayshade"])
    }

    @objc private func togglePause() { state.userPaused.toggle() }
    @objc private func toggleOverlays() { state.settings.overlaysHidden.toggle() }
    @objc private func previewDay() { state.playDay() }
    @objc private func pickScheme(_ sender: NSMenuItem) { state.settings.scheme = sender.representedObject as? String ?? "cycle" }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector, on: Bool? = nil, key: String = "", to target: NSMenu? = nil) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.target = self
            if let on { i.state = on ? .on : .off }
            (target ?? menu).addItem(i)
            return i
        }
        _ = item("About Dayshade", #selector(showAbout))
        menu.addItem(.separator())
        let sun = state.sun(at: Date())
        let times = sunTimes(on: Date(), latitude: state.settings.latitude, longitude: state.settings.longitude)
        let fmt = { (d: Date?) in d?.formatted(date: .omitted, time: .shortened) ?? "–" }
        let info = NSMenuItem(title: String(format: "Sun at %.0f° · ", sun.elevation) + "rise \(fmt(times.rise)), set \(fmt(times.set))",
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())

        let schemes = NSMenu()
        for (id, name) in [("cycle", "Day Cycle")] + state.settings.schemes.map({ ($0.id, $0.name) }) {
            item(name, #selector(pickScheme(_:)), on: state.settings.scheme == id, to: schemes).representedObject = id
        }
        let schemeItem = NSMenuItem(title: "Colour Scheme", action: nil, keyEquivalent: "")
        schemeItem.submenu = schemes
        menu.addItem(schemeItem)
        _ = item("Pause Animation", #selector(togglePause), on: state.userPaused)
        _ = item("Show Logos and Bars", #selector(toggleOverlays), on: !state.settings.overlaysHidden)
        _ = item("Preview a Whole Day (1 min)", #selector(previewDay))
        menu.addItem(.separator())
        _ = item("Settings…", #selector(openSettings), key: ",")
        menu.addItem(NSMenuItem(title: "Quit Dayshade", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}
