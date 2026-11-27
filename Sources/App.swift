import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = WallState()
    private var windows: [(NSWindow, WindowState)] = []
    private var statusItem: NSStatusItem!
    private var appearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ note: Notification) {
        applyAppearance(animated: false)
        appearanceObservation = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            Task { @MainActor in self?.applyAppearance(animated: true) }
        }

        buildWindows()
        buildMenu()

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
                Task { @MainActor in self?.state.systemAsleep = asleep }
            }
        }
    }

    private func applyAppearance(animated: Bool) {
        let forced = UserDefaults.standard.string(forKey: "forceAppearance")
        let dark = forced.map { $0 == "dark" }
            ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        state.setDark(dark, animated: animated)
    }

    // One borderless window per display, sitting at desktop level: below the desktop icons, above the system wallpaper.
    private func buildWindows() {
        windows.forEach { $0.0.orderOut(nil) }
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
            let ws = WindowState()
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
        statusItem.button?.image = Logo.menuIcon ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "THOC Wall")
        statusItem.menu = NSMenu()
        statusItem.menu?.delegate = self
    }

    @objc private func togglePause() { state.userPaused.toggle() }
    @objc private func toggleLogo() { state.showLogo.toggle() }
    @objc private func previewDay() { state.previewStart = Date() }
    @objc private func toggleLogin() {
        let svc = SMAppService.mainApp
        do {
            if svc.status == .enabled { try svc.unregister() } else { try svc.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change Open at Login"
            alert.informativeText = error.localizedDescription + "\n\nMove THOC Wall to your Applications folder and try again."
            alert.runModal()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        func item(_ title: String, _ action: Selector, on: Bool? = nil) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            if let on { i.state = on ? .on : .off }
            menu.addItem(i)
        }
        let sun = sunPosition(at: Date(), latitude: state.latitude, longitude: state.longitude)
        let info = NSMenuItem(title: String(format: "Sun at %.0f° %@", sun.elevation, sun.rising ? "and rising" : "and setting"),
                              action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        menu.addItem(.separator())
        item("Pause Animation", #selector(togglePause), on: state.userPaused)
        item("Show Logo", #selector(toggleLogo), on: state.showLogo)
        item("Preview a Whole Day (1 min)", #selector(previewDay))
        menu.addItem(.separator())
        item("Open at Login", #selector(toggleLogin), on: SMAppService.mainApp.status == .enabled)
        menu.addItem(NSMenuItem(title: "Quit THOC Wall", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }
}
