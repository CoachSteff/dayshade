import Foundation

/// A rectangle on the screen in fractions (0...1) from the top-left, snapped to a 24 x 16 grid in the editor.
struct GridRect: Codable, Equatable {
    static let cols = 24
    static let rows = 16

    var x: Double, y: Double, w: Double, h: Double

    func cg(in size: CGSize) -> CGRect {
        CGRect(x: x * size.width, y: y * size.height, width: w * size.width, height: h * size.height)
    }

    static func cells(_ c: Int, _ r: Int, _ w: Int, _ h: Int) -> GridRect {
        GridRect(x: Double(c) / Double(cols), y: Double(r) / Double(rows),
                 w: Double(w) / Double(cols), h: Double(h) / Double(rows))
    }
}

enum ScreenScope: String, Codable, CaseIterable, Identifiable {
    case all, main
    var id: String { rawValue }
    var label: String { self == .all ? "Every display" : "Main display only" }
}

enum LogoTint: String, Codable, CaseIterable, Identifiable {
    case original, white, black, custom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct LogoItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var path: String                 // "builtin:coachsteff", "builtin:thoc" or a file in Application Support
    var rect: GridRect
    var opacity = 0.92
    var tint = LogoTint.original
    var tintHex = "FFFFFF"
    var shadow = true
    var scope = ScreenScope.all
    var enabled = true

    static let coachsteff = LogoItem(name: "CoachSteff", path: "builtin:coachsteff", rect: .cells(9, 6, 6, 4))
    static let thoc = LogoItem(name: "The House of Coaching", path: "builtin:thoc", rect: .cells(9, 7, 6, 2))
}

enum BarPlacement: String, Codable, CaseIterable, Identifiable {
    case menuBar, dock, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .menuBar: "Under the menu bar"
        case .dock: "Behind the Dock"
        case .custom: "Custom area"
        }
    }
}

enum BarStyle: String, Codable, CaseIterable, Identifiable {
    case auto, light, dark, custom
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct BarItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var placement: BarPlacement
    var rect = GridRect.cells(2, 12, 6, 3)
    var dockWidth = 0.55
    var style = BarStyle.auto
    var tintHex = "FFFFFF"
    var opacity = 0.18
    var cornerRadius = 16.0
    var border = true
    var shadow = false
    var scope = ScreenScope.all
    var enabled = true
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case auto, light, dark
    var id: String { rawValue }
}

enum FrameRate: String, Codable, CaseIterable, Identifiable {
    case smooth, gentle, saver
    var id: String { rawValue }
    var fps: Double { switch self { case .smooth: 30; case .gentle: 20; case .saver: 10 } }
    var label: String { switch self { case .smooth: "Smooth"; case .gentle: "Gentle"; case .saver: "Battery saver" } }
}

struct WallSettings: Codable, Equatable {
    var appearance = AppearanceMode.auto
    var scheme = "cycle"             // "cycle" or the id of one of `schemes`
    var schemes = ColorSchemeItem.builtins
    var motion = 1.0
    var vibrance = 1.0
    var depth = 1.0
    var grain = 0.0
    var frameRate = FrameRate.smooth
    var locationMode = LocationMode.manual
    var place = "Brussels, Belgium"
    var latitude = 50.85
    var longitude = 4.35
    var logos = [LogoItem.coachsteff]
    var bars: [BarItem] = []
    var overlaysHidden = false
    var showMenuIcon = true
    var syncSystemWallpaper = false
    var loginScreenLogos = false     // only used by the system wallpaper sync
    var loginScreenBars = false

    private static let key = "settings.v1"

    /// Stored values are laid over the defaults, so settings saved by an older version still load.
    static func load() -> WallSettings {
        migrateFromThocWall()
        let fallback = WallSettings()
        guard let data = UserDefaults.standard.data(forKey: key),
              let stored = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let defaultsData = try? JSONEncoder().encode(fallback),
              var merged = try? JSONSerialization.jsonObject(with: defaultsData) as? [String: Any]
        else { return fallback }
        merged.merge(stored) { _, new in new }
        // Before schemes became a list there was one "custom" palette; keep it.
        if stored["schemes"] == nil, let old = stored["custom"] as? [String],
           var list = merged["schemes"] as? [[String: Any]] {
            list.append(["id": "custom", "name": "Custom", "colors": old, "builtin": false])
            merged["schemes"] = list
        }
        guard let mergedData = try? JSONSerialization.data(withJSONObject: merged),
              let settings = try? JSONDecoder().decode(WallSettings.self, from: mergedData)
        else { return fallback }
        return settings
    }

    /// Dayshade was called THOC Wall, with its own settings and logo folder. Bring both across once.
    private static func migrateFromThocWall() {
        let d = UserDefaults.standard
        guard d.data(forKey: key) == nil,
              var data = UserDefaults(suiteName: "be.thehouseofcoaching.wall")?.data(forKey: key) else { return }
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent("THOC Wall"), new = support.appendingPathComponent("Dayshade")
        if fm.fileExists(atPath: old.path) && !fm.fileExists(atPath: new.path) {
            try? fm.moveItem(at: old, to: new)
        }
        // Logo paths are stored in full, so point them at the moved folder. JSON escapes slashes.
        if var text = String(data: data, encoding: .utf8) {
            text = text.replacingOccurrences(of: "\\/THOC Wall\\/", with: "\\/Dayshade\\/")
                .replacingOccurrences(of: "/THOC Wall/", with: "/Dayshade/")
            data = Data(text.utf8)
        }
        d.set(data, forKey: key)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}


enum LocationMode: String, Codable, CaseIterable, Identifiable {
    case auto, manual
    var id: String { rawValue }
}

/// A 3 x 3 palette. The seven built-ins drive the day cycle and can be edited or reset, but not deleted.
struct ColorSchemeItem: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var colors: [String]
    var builtin = false

    var palette: Palette { Palette(hexStrings: colors) }

    static let builtins = Palette.presets.map {
        ColorSchemeItem(id: $0.id, name: $0.name, colors: $0.palette.hexStrings, builtin: true)
    }

    var original: ColorSchemeItem? { Self.builtins.first { $0.id == id } }
}

/// The shape of an exported scheme file: `{"name": "...", "colors": ["RRGGBB", ...9]}`, or a list of them.
struct SchemeFile: Codable {
    var name: String
    var colors: [String]
}
