import SwiftUI

struct WallpaperView: View {
    let state: WallState
    let window: WindowState
    var fixedDate: Date? = nil

    var body: some View {
        let paused = state.userPaused || state.systemAsleep || !window.visible
        if let date = fixedDate {
            frame(at: date)
        } else {
            TimelineView(.animation(minimumInterval: 1 / state.fps, paused: paused)) { ctx in
                frame(at: ctx.date)
            }
        }
    }

    private func frame(at now: Date) -> some View {
        let t = now.timeIntervalSinceReferenceDate
        let sun = sunPosition(at: state.clock(at: now), latitude: state.latitude, longitude: state.longitude)
        let (palette, night) = paletteForSun(sun)
        let dark = state.darkness(at: now)

        return GeometryReader { geo in
            ZStack {
                MeshGradient(width: 3, height: 3,
                             points: meshPoints(t),
                             colors: meshColors(palette, night: night, dark: dark, t: t),
                             smoothsColors: true,
                             colorSpace: .perceptual)
                if state.showLogo, let logo = Logo.full {
                    Image(nsImage: logo)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(geo.size.width, geo.size.height) * 0.30)
                        .opacity(0.92)
                        .shadow(color: .black.opacity(0.10 + 0.10 * (1 - dark)), radius: 18)
                }
            }
        }
        .ignoresSafeArea()
    }

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
    private func meshColors(_ palette: Palette, night: Double, dark: Double, t: Double) -> [Color] {
        let ring = [0, 1, 2, 5, 8, 7, 6, 3]
        let shift = 1.4 * sin(2 * .pi * t / 720)
        var labs = palette.colors
        for (i, slot) in ring.enumerated() {
            let pos = Double(i) + shift + 8
            let a = Int(pos.rounded(.down))
            let f = pos - Double(a)
            labs[slot] = Lab.mix(palette.colors[ring[a % 8]], palette.colors[ring[(a + 1) % 8]], f)
        }
        return labs.map { Lab.mix($0, $0.deepened(night: night), dark).rgb.color }
    }
}
