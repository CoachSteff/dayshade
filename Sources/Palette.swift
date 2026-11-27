import Foundation
import SwiftUI
import AppKit

struct RGB {
    var r, g, b: Double

    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }

    init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

// OKLab keeps blends between palettes clean instead of muddy grey midpoints.
struct Lab { var L, a, b: Double }

private func toLinear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
private func toGamma(_ c: Double) -> Double {
    let v = max(0, min(1, c))
    return v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
}

extension RGB {
    var lab: Lab {
        let r = toLinear(self.r), g = toLinear(self.g), b = toLinear(self.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return Lab(L: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                   a: 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                   b: 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }
}

extension Lab {
    var rgb: RGB {
        let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
        return RGB(toGamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                   toGamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                   toGamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    static func mix(_ x: Lab, _ y: Lab, _ t: Double) -> Lab {
        Lab(L: x.L + (y.L - x.L) * t, a: x.a + (y.a - x.a) * t, b: x.b + (y.b - x.b) * t)
    }

    /// Deep, jewel-toned version for dark mode. Darkened oranges and yellows read as brown and darkened
    /// greens as olive, so warm hues slide towards wine-rose and greens towards teal.
    func deepened(night: Double) -> Lab {
        var hue = atan2(b, a) * 180 / .pi
        if hue < 0 { hue += 360 }
        let chroma = (a * a + b * b).squareRoot()
        if hue >= 20 && hue < 135 { hue = 0 + (hue - 20) * 0.15 }
        else if hue >= 135 && hue < 175 { hue = 175 + (hue - 135) * 0.1 }
        let c = min(chroma * (1.15 - 0.2 * night), 0.17)
        let h = hue * .pi / 180
        return Lab(L: 0.22 + L * 0.30 - 0.07 * night, a: c * cos(h), b: c * sin(h))
    }
}

/// A 3x3 grid of colours, row by row from top-left, sampled from the THOC wallpapers.
struct Palette {
    var colors: [Lab]

    init(_ hexes: [UInt32]) { colors = hexes.map { RGB(hex: $0).lab } }
    init(labs: [Lab]) { colors = labs }

    static func mix(_ x: Palette, _ y: Palette, _ t: Double) -> Palette {
        Palette(labs: zip(x.colors, y.colors).map { Lab.mix($0, $1, t) })
    }

    // "default" wallpaper: the bright THOC teal / blue / violet
    static let midday = Palette([0x00CABF, 0x0EB6D6, 0x1894E9,
                                 0x49F2C7, 0xAAE6DA, 0x8F88F1,
                                 0xA1FCFE, 0xBBA0FB, 0xBD5EFA])
    // "focus": soft blue and lilac with a warm heart
    static let morning = Palette([0x5BAEFF, 0x9D98FE, 0xAE8EFF,
                                  0x98EAED, 0xF2B6CC, 0xAD91FC,
                                  0x4DFCFA, 0x9ED7F1, 0x7F8DFE])
    // "liquid": cool cyan afternoon
    static let afternoon = Palette([0x79FCFD, 0x76F8FD, 0x64BBFC,
                                    0x68B9E7, 0x64B1E5, 0x63CFF9,
                                    0x5C97DB, 0x62DBEA, 0x6BFBFC])
    // "warm": golden hour
    static let golden = Palette([0x46EFBC, 0x62C7D8, 0x4487FE,
                                 0xABDF96, 0xE8B4CE, 0xD29CE7,
                                 0xF0D450, 0xF7C179, 0xFC909C])
    // "dark" wallpaper: sunset pinks and yellows under a violet sky
    static let dusk = Palette([0x497CD7, 0x855BD2, 0xBA5CD6,
                               0x1FC5D5, 0x74B6CB, 0xFFAEC2,
                               0x00FACE, 0xA7F3AC, 0xFEF582])
    // First light: cool sky above, peach horizon below
    static let dawn = Palette([0x6E7FE0, 0x9A8CF0, 0xC49AF0,
                               0x7FC8E8, 0xEFA8C8, 0xF7A8C0,
                               0x8FE6DA, 0xFCCB9A, 0xFDB38C])
    static let night = Palette([0x3D52B8, 0x5E44B8, 0x8E4CC0,
                                0x2590B5, 0x4D68C0, 0xB05AA8,
                                0x14B5A5, 0x3F8FC0, 0x6656C0])
}

private func smooth(_ x: Double) -> Double {
    let t = max(0, min(1, x))
    return t * t * (3 - 2 * t)
}

/// Picks the palette for the sun's current position. Returns the palette and how "night" it is (0...1).
func paletteForSun(_ sun: SunPosition, _ p: (String) -> Palette) -> (Palette, Double) {
    let e = sun.elevation
    if e <= -12 { return (p("night"), 1) }
    let nightness = smooth((-e - 2) / 10)

    if sun.rising {
        if e < -4 { return (.mix(p("night"), p("dawn"), smooth((e + 12) / 8)), nightness) }
        if e < 6 { return (.mix(p("dawn"), p("morning"), smooth((e + 4) / 10)), nightness) }
        let top = max(sun.maxElevation * 0.85, 7)
        return (.mix(p("morning"), p("midday"), smooth((e - 6) / (top - 6))), 0)
    } else {
        if e < -2 { return (.mix(p("night"), p("dusk"), smooth((e + 12) / 10)), nightness) }
        if e < 8 { return (.mix(p("dusk"), p("golden"), smooth((e + 2) / 10)), nightness) }
        let top = max(sun.maxElevation * 0.85, 9)
        let f = max(0, min(1, (e - 8) / (top - 8)))
        if f < 0.5 { return (.mix(p("golden"), p("afternoon"), smooth(f * 2)), 0) }
        return (.mix(p("afternoon"), p("midday"), smooth((f - 0.5) * 2)), 0)
    }
}

struct SchemePreset: Identifiable {
    let id: String
    let name: String
    let palette: Palette
}

extension Palette {
    static let presets = [
        SchemePreset(id: "dawn", name: "Dawn", palette: .dawn),
        SchemePreset(id: "morning", name: "Morning", palette: .morning),
        SchemePreset(id: "midday", name: "Midday", palette: .midday),
        SchemePreset(id: "afternoon", name: "Afternoon", palette: .afternoon),
        SchemePreset(id: "golden", name: "Golden hour", palette: .golden),
        SchemePreset(id: "dusk", name: "Dusk", palette: .dusk),
        SchemePreset(id: "night", name: "Night", palette: .night),
    ]

    init(hexStrings: [String]) {
        let padded = (hexStrings + Array(repeating: "808080", count: 9)).prefix(9)
        colors = padded.map { RGB(hex: UInt32($0.trimmingCharacters(in: CharacterSet(charactersIn: "# ")), radix: 16) ?? 0x808080).lab }
    }

    var hexStrings: [String] { colors.map { $0.rgb.hex } }
}

extension RGB {
    var hex: String {
        String(format: "%02X%02X%02X", Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .gray
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }
}

extension Color {
    init(hex: String) { self = RGB(hex: UInt32(hex, radix: 16) ?? 0xFFFFFF).color }
    var hex: String { RGB(color: self).hex }
}
