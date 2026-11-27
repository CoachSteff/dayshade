import AppKit
import UniformTypeIdentifiers

@MainActor
enum Logo {
    private static var cache: [String: NSImage] = [:]

    static var builtinURL: URL? {
        Bundle.main.url(forResource: "logo", withExtension: "svg")
            ?? URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
                .appendingPathComponent("../Resources/logo.svg").standardized
    }

    static var logoFolder: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dayshade/Logos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The image for a logo path, with transparent margins trimmed so it lines up with what you see.
    static func image(for path: String) -> NSImage? {
        if let hit = cache[path] { return hit }
        let url = path == "builtin:thoc" ? builtinURL : URL(fileURLWithPath: path)
        guard let url, let source = NSImage(contentsOf: url), let img = trimmed(source, cropX: nil) else { return nil }
        cache[path] = img
        return img
    }

    /// Copies a chosen file into Application Support so the logo survives the original moving.
    static func importFile(_ url: URL) -> String? {
        let dest = logoFolder.appendingPathComponent(UUID().uuidString + "." + url.pathExtension.lowercased())
        do { try FileManager.default.copyItem(at: url, to: dest) } catch { return nil }
        return dest.path
    }

    static func removeFile(_ path: String) {
        guard path.hasPrefix(logoFolder.path) else { return }
        try? FileManager.default.removeItem(atPath: path)
        cache[path] = nil
    }

    static let allowedTypes: [UTType] = [.svg, .png, .pdf, .jpeg, .heic, .tiff]

    /// Just the figure from the THOC logo, as a menu bar template icon.
    static let menuIcon: NSImage? = {
        guard let url = builtinURL, let svg = NSImage(contentsOf: url), let img = trimmed(svg, cropX: 480) else { return nil }
        let h = 18.0
        img.size = NSSize(width: h * img.size.width / img.size.height, height: h)
        img.isTemplate = true
        return img
    }()

    private static func trimmed(_ source: NSImage, cropX: Double?) -> NSImage? {
        let scale = max(1, min(4, 2048 / max(source.size.width, source.size.height) * 2))
        let w = Int(source.size.width * scale), h = Int(source.size.height * scale)
        guard w > 0, h > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        source.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()

        let maxX = cropX.map { Int($0 * scale) } ?? w
        var minPX = w, minPY = h, maxPX = 0, maxPY = 0
        guard let data = rep.bitmapData else { return nil }
        for y in 0..<h {
            let row = data + y * rep.bytesPerRow
            for x in 0..<maxX where row[x * 4 + 3] > 8 {
                minPX = min(minPX, x); maxPX = max(maxPX, x)
                minPY = min(minPY, y); maxPY = max(maxPY, y)
            }
        }
        guard maxPX > minPX, let cg = rep.cgImage?.cropping(to: CGRect(x: minPX, y: minPY,
                                                                       width: maxPX - minPX + 1,
                                                                       height: maxPY - minPY + 1)) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: Double(cg.width) / scale, height: Double(cg.height) / scale))
    }
}
