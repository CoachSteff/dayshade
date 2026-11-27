import AppKit

enum Logo {
    private static let svg: NSImage? = {
        let bundled = Bundle.main.url(forResource: "logo", withExtension: "svg")
        let dev = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent().appendingPathComponent("../Resources/logo.svg").standardized
        return [bundled, dev].compactMap { $0 }.lazy.compactMap { NSImage(contentsOf: $0) }.first
    }()

    /// Full logo with the SVG's empty margins trimmed, so it centres on what you actually see.
    static let full: NSImage? = render(cropX: nil)

    /// Just the figure, as a menu bar template icon.
    static let menuIcon: NSImage? = {
        guard let img = render(cropX: 480) else { return nil }
        let h = 18.0
        img.size = NSSize(width: h * img.size.width / img.size.height, height: h)
        img.isTemplate = true
        return img
    }()

    private static func render(cropX: Double?) -> NSImage? {
        guard let svg else { return nil }
        let scale = 2.0
        let w = Int(svg.size.width * scale), h = Int(svg.size.height * scale)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        svg.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
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
