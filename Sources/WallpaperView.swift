import SwiftUI

struct WallpaperView: View {
    let state: WallState
    let window: WindowState
    var fixedDate: Date? = nil
    var maxFPS: Double = 60
    var hideLogos = false
    var hideBars = false

    var body: some View {
        let paused = state.userPaused || state.systemAsleep || !window.visible
        if let date = fixedDate {
            frame(at: date)
        } else {
            TimelineView(.animation(minimumInterval: 1 / min(state.fps, maxFPS), paused: paused)) { ctx in
                frame(at: ctx.date)
            }
        }
    }

    private func frame(at now: Date) -> some View {
        let s = state.settings
        let t = state.phase(at: now)
        let (palette, night) = state.palette(at: now)
        let dark = state.darkness(at: now)

        return GeometryReader { geo in
            // Previews are smaller than the real screen; scale point sizes like radii with them.
            let k = geo.size.width / max(1, window.screenSize.width)
            ZStack(alignment: .topLeading) {
                MeshGradient(width: 3, height: 3,
                             points: meshPoints(t),
                             colors: meshColors(palette, night: night, dark: dark, t: t, s: s),
                             smoothsColors: true,
                             colorSpace: .perceptual)
                if s.grain > 0 {
                    Image(nsImage: Grain.tile)
                        .resizable(resizingMode: .tile)
                        .blendMode(.overlay)
                        .opacity(s.grain * 0.55)
                }
                if !s.overlaysHidden {
                    ForEach(s.bars.filter { $0.enabled && !hideBars && shows($0.scope) }) { bar in
                        if let r = barFrame(bar, window: window, size: geo.size) {
                            BarShape(bar: bar, dark: dark, k: k)
                                .frame(width: r.width, height: r.height)
                                .position(x: r.midX, y: r.midY)
                        }
                    }
                    ForEach(s.logos.filter { $0.enabled && !hideLogos && shows($0.scope) }) { logo in
                        if let img = Logo.image(for: logo.path) {
                            let r = logo.rect.cg(in: geo.size)
                            LogoImage(image: img, item: logo, dark: dark, k: k)
                                .frame(width: r.width, height: r.height)
                                .position(x: r.midX, y: r.midY)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func shows(_ scope: ScreenScope) -> Bool { scope == .all || window.isMain }

    // Edge midpoints slide along their edge, the centre wanders. Periods of 4 to 7 minutes keep it calm.
    private func meshPoints(_ t: Double) -> [SIMD2<Float>] {
        func p(_ x: Double, _ y: Double) -> SIMD2<Float> { SIMD2(Float(x), Float(y)) }
        return [
            p(0, 0), p(0.5 + 0.20 * sin(t / 53), 0), p(1, 0),
            p(0, 0.5 + 0.20 * sin(t / 67 + 1)),
            p(0.5 + 0.17 * sin(t / 41 + 2), 0.5 + 0.15 * cos(t / 59)),
            p(1, 0.5 + 0.20 * cos(t / 71)),
            p(0, 1), p(0.5 + 0.20 * cos(t / 47 + 3), 1), p(1, 1),
        ]
    }

    // The outer ring of colours sways back and forth around the edge, so the light seems to drift
    // without turning the composition upside down.
    private func meshColors(_ palette: Palette, night: Double, dark: Double, t: Double, s: WallSettings) -> [Color] {
        let ring = [0, 1, 2, 5, 8, 7, 6, 3]
        let shift = 1.4 * sin(2 * .pi * t / 720)
        var labs = palette.colors
        for (i, slot) in ring.enumerated() {
            let pos = Double(i) + shift + 8
            let a = Int(pos.rounded(.down))
            let f = pos - Double(a)
            labs[slot] = Lab.mix(palette.colors[ring[a % 8]], palette.colors[ring[(a + 1) % 8]], f)
        }
        return labs.map { lab in
            let v = Lab(L: lab.L, a: lab.a * s.vibrance, b: lab.b * s.vibrance)
            let deep = Lab.mix(v, v.deepened(night: night), s.depth)
            return Lab.mix(v, deep, dark).rgb.color
        }
    }
}

struct LogoImage: View {
    let image: NSImage
    let item: LogoItem
    let dark: Double
    let k: Double

    var body: some View {
        Group {
            if item.tint == .original {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(nsImage: image).renderingMode(.template).resizable().interpolation(.high)
                    .foregroundStyle(item.tint == .white ? .white : item.tint == .black ? .black : Color(hex: item.tintHex))
            }
        }
        .aspectRatio(contentMode: .fit)
        .opacity(item.opacity)
        .shadow(color: .black.opacity(item.shadow ? 0.10 + 0.10 * (1 - dark) : 0), radius: 18 * k)
    }
}

/// A translucent glass panel: tinted fill, a soft top sheen and a hairline edge.
struct BarShape: View {
    let bar: BarItem
    let dark: Double
    let k: Double

    var body: some View {
        let fill: Color = switch bar.style {
        case .auto: Color(white: 1 - dark)
        case .light: .white
        case .dark: .black
        case .custom: Color(hex: bar.tintHex)
        }
        let shape = RoundedRectangle(cornerRadius: bar.cornerRadius * k, style: .continuous)
        shape
            .fill(fill.opacity(bar.opacity))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom)))
            .overlay(shape.strokeBorder(.white.opacity(bar.border ? 0.28 : 0), lineWidth: max(0.5, k)))
            .shadow(color: .black.opacity(bar.shadow ? 0.18 : 0), radius: 20 * k, y: 6 * k)
    }
}

enum Grain {
    /// A small tile of random grey noise, laid over the gradient to give it a printed, paper-like texture.
    static let tile: NSImage = {
        let px = 256
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                   samplesPerPixel: 1, hasAlpha: false, isPlanar: false,
                                   colorSpaceName: .deviceWhite, bytesPerRow: px, bitsPerPixel: 8)!
        var rng = SystemRandomNumberGenerator()
        for i in 0..<(px * px) { rep.bitmapData![i] = UInt8.random(in: 60...196, using: &rng) }
        let img = NSImage(size: NSSize(width: px / 2, height: px / 2))
        img.addRepresentation(rep)
        return img
    }()
}

/// Where a bar sits on a screen of `size` points. Menu bar strips and Dock shelves follow the real system metrics.
@MainActor
func barFrame(_ bar: BarItem, window: WindowState, size: CGSize) -> CGRect? {
    let k = size.width / max(1, window.screenSize.width)
    switch bar.placement {
    case .custom:
        return bar.rect.cg(in: size)
    case .menuBar:
        return CGRect(x: 0, y: 0, width: size.width, height: window.menuBarHeight * k)
    case .dock:
        let d = window.dockInsets, pad = 4 * k
        if d.bottom > 0 {
            let w = size.width * bar.dockWidth, h = d.bottom * k - pad
            return CGRect(x: (size.width - w) / 2, y: size.height - h - pad, width: w, height: h)
        }
        if d.left > 0 || d.right > 0 {
            let h = size.height * bar.dockWidth, w = max(d.left, d.right) * k - pad
            let x = d.left > 0 ? pad : size.width - w - pad
            return CGRect(x: x, y: (size.height - h) / 2, width: w, height: h)
        }
        return nil  // Dock is hidden
    }
}

/// The same, as fractions of the screen, for the placement grid.
@MainActor
func barGridRect(_ bar: BarItem, window: WindowState) -> GridRect? {
    let s = window.screenSize
    guard let r = barFrame(bar, window: window, size: s), s.width > 0, s.height > 0 else { return nil }
    return GridRect(x: r.minX / s.width, y: r.minY / s.height, w: r.width / s.width, h: r.height / s.height)
}
