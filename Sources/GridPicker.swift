import SwiftUI

/// Something drawn on the placement grid. Editable zones can be moved and resized; locked zones
/// (menu bar strip, Dock shelf) follow the system and can only be selected; ghosts are other items, for reference.
struct GridZone: Identifiable {
    enum Kind { case editable, locked, ghost }
    let id: UUID
    var rect: GridRect
    var label: String
    var kind: Kind
    var enabled = true
    var tint: Color = .barTeal
}

/// A miniature screen made of cells, showing every zone as tinted cells.
/// Drag inside a zone to move it, drag its bottom-right cell to resize, drag across empty cells to redraw the
/// selected one. The pointer changes to show which of those a drag will do.
struct ZoneGrid: View {
    let zones: [GridZone]
    @Binding var selected: UUID?
    var aspect: CGFloat
    var onChange: (UUID, GridRect) -> Void

    private let cols = GridRect.cols, rows = GridRect.rows

    private struct Cells { var c, r, w, h: Int }
    private enum Drag { case move(UUID, Int, Int, Cells), resize(UUID, Cells), draw(UUID, Int, Int), none }
    private enum Hit { case zone(GridZone, corner: Bool), locked(GridZone), empty }

    @State private var drag: Drag?
    @State private var hover: Hit?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                let cw = geo.size.width / CGFloat(cols), ch = geo.size.height / CGFloat(rows)
                Canvas { ctx, _ in
                    for r in 0..<rows {
                        for c in 0..<cols {
                            let cell = CGRect(x: CGFloat(c) * cw, y: CGFloat(r) * ch, width: cw, height: ch).insetBy(dx: 1.5, dy: 1.5)
                            ctx.fill(Path(roundedRect: cell, cornerRadius: min(cw, ch) * 0.2), with: .color(cellColor(c, r)))
                        }
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case let .active(p) = phase { hover = hit(p, cw, ch) } else { hover = nil }
                }
                .pointerStyle(pointer)
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { v in dragChanged(v, cw, ch) }
                    .onEnded { v in
                        drag = nil
                        hover = hit(v.location, cw, ch)
                    })
            }
            .aspectRatio(aspect, contentMode: .fit)

            HStack {
                Text(footer).font(.callout).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                Spacer()
                if let z = selectedZone, z.kind == .editable {
                    Menu("Snap to") {
                        Button("Centre") { snap(z, 0.5, 0.5) }
                        Divider()
                        Button("Top left") { snap(z, 0, 0) }
                        Button("Top centre") { snap(z, 0.5, 0) }
                        Button("Top right") { snap(z, 1, 0) }
                        Button("Bottom left") { snap(z, 0, 1) }
                        Button("Bottom centre") { snap(z, 0.5, 1) }
                        Button("Bottom right") { snap(z, 1, 1) }
                    }
                    .fixedSize()
                }
            }
        }
    }

    // MARK: Drawing

    private var selectedZone: GridZone? { zones.first { $0.id == selected } }

    private var hoveredID: UUID? {
        switch hover {
        case let .zone(z, _): z.id
        case let .locked(z): z.id
        default: nil
        }
    }

    /// Colour alone tells the zones apart: violet is selected, grey is your other items, a tint marks
    /// bars or logos from the other pane. Hovering lightens a zone.
    private func cellColor(_ c: Int, _ r: Int) -> Color {
        if let z = selectedZone, z.kind == .editable, contains(z.rect, c, r) { return .thocViolet }
        if let z = zones.last(where: { $0.kind == .editable && contains($0.rect, c, r) }) {
            let lift = z.id == hoveredID ? 0.15 : 0
            return .gray.opacity((z.enabled ? 0.5 : 0.3) + lift)
        }
        if let z = zones.last(where: { $0.kind == .locked && overlaps($0.rect, c, r) }) {
            let strength = z.id == selected ? 0.85 : z.id == hoveredID ? 0.6 : 0.4
            return z.tint.opacity(z.enabled ? strength : strength * 0.5)
        }
        if let z = zones.last(where: { $0.kind == .ghost && overlaps($0.rect, c, r) }) {
            return z.tint.opacity(z.enabled ? 0.45 : 0.2)
        }
        return .gray.opacity(0.16)
    }

    private var pointer: PointerStyle {
        switch drag {
        case .move: return .grabActive
        case .resize: return .frameResize(position: .bottomTrailing)
        case .draw: return .rectSelection
        default: break
        }
        switch hover {
        case let .zone(_, corner): return corner ? .frameResize(position: .bottomTrailing) : .grabIdle
        case .locked: return .link
        case .empty: return selectedZone?.kind == .editable ? .rectSelection : .default
        case nil: return .default
        }
    }

    private var footer: String {
        if let id = hoveredID, id != selected, let z = zones.first(where: { $0.id == id }) {
            return z.kind == .locked ? "\(z.label) · follows the system" : z.label
        }
        guard let z = selectedZone else { return "Click a zone to select it." }
        switch z.kind {
        case .locked: return "\(z.label) follows the system and can't be moved."
        case .ghost: return ""
        case .editable:
            let c = cells(z.rect)
            return "\(z.label) · \(c.w) × \(c.h) cells"
        }
    }

    // MARK: Interaction

    /// What a press at this point would grab. The selected zone wins when zones overlap, then the topmost.
    private func hit(_ p: CGPoint, _ cw: CGFloat, _ ch: CGFloat) -> Hit {
        let (c, r) = cell(p, cw, ch)
        let editable = zones.filter { $0.kind == .editable }
        if let z = editable.first(where: { $0.id == selected && contains($0.rect, c, r) })
            ?? editable.last(where: { contains($0.rect, c, r) }) {
            let k = cells(z.rect)
            return .zone(z, corner: c == k.c + k.w - 1 && r == k.r + k.h - 1 && (k.w > 1 || k.h > 1))
        }
        if let z = zones.last(where: { $0.kind == .locked && overlaps($0.rect, c, r) }) { return .locked(z) }
        return .empty
    }

    private func dragChanged(_ v: DragGesture.Value, _ cw: CGFloat, _ ch: CGFloat) {
        if drag == nil {
            let (sc, sr) = cell(v.startLocation, cw, ch)
            switch hit(v.startLocation, cw, ch) {
            case let .zone(z, corner):
                selected = z.id
                drag = corner ? .resize(z.id, cells(z.rect)) : .move(z.id, sc, sr, cells(z.rect))
            case let .locked(z):
                selected = z.id
                drag = Drag.none
            case .empty:
                if let z = selectedZone, z.kind == .editable { drag = .draw(z.id, sc, sr) } else { drag = Drag.none }
            }
        }

        let (pc, pr) = cell(v.location, cw, ch)
        switch drag {
        case let .move(id, sc, sr, o):
            let c = max(0, min(cols - o.w, o.c + pc - sc)), r = max(0, min(rows - o.h, o.r + pr - sr))
            onChange(id, .cells(c, r, o.w, o.h))
        case let .resize(id, o):
            onChange(id, .cells(o.c, o.r, max(1, min(cols - o.c, pc - o.c + 1)), max(1, min(rows - o.r, pr - o.r + 1))))
        case let .draw(id, sc, sr):
            onChange(id, .cells(min(sc, pc), min(sr, pr), abs(sc - pc) + 1, abs(sr - pr) + 1))
        default:
            break
        }
    }

    /// Moves a zone to an edge or the centre, keeping its size and a one-cell margin.
    private func snap(_ z: GridZone, _ fx: Double, _ fy: Double) {
        let c = cells(z.rect)
        func place(_ f: Double, _ free: Int) -> Int { f == 0 ? min(1, free) : f == 1 ? max(0, free - 1) : free / 2 }
        onChange(z.id, .cells(place(fx, cols - c.w), place(fy, rows - c.h), c.w, c.h))
    }

    private func cells(_ g: GridRect) -> Cells {
        let c = Int((g.x * Double(cols)).rounded()), r = Int((g.y * Double(rows)).rounded())
        return Cells(c: c, r: r, w: max(1, Int((g.w * Double(cols)).rounded())), h: max(1, Int((g.h * Double(rows)).rounded())))
    }

    private func cell(_ p: CGPoint, _ cw: CGFloat, _ ch: CGFloat) -> (Int, Int) {
        (max(0, min(cols - 1, Int(p.x / cw))), max(0, min(rows - 1, Int(p.y / ch))))
    }

    private func contains(_ g: GridRect, _ c: Int, _ r: Int) -> Bool {
        let x = (Double(c) + 0.5) / Double(cols), y = (Double(r) + 0.5) / Double(rows)
        return x > g.x && x < g.x + g.w && y > g.y && y < g.y + g.h
    }

    /// For zones that don't line up with the grid, like the menu bar strip: a cell counts once a quarter of it is covered.
    private func overlaps(_ g: GridRect, _ c: Int, _ r: Int) -> Bool {
        let cw = 1 / Double(cols), ch = 1 / Double(rows)
        let x0 = Double(c) * cw, y0 = Double(r) * ch
        let w = max(0, min(x0 + cw, g.x + g.w) - max(x0, g.x)), h = max(0, min(y0 + ch, g.y + g.h) - max(y0, g.y))
        return w * h >= 0.25 * cw * ch
    }
}

extension Color {
    static let thocViolet = Color(hex: "9B5DE5")
    static let barTeal = Color(hex: "00B3A6")
    static let logoBlue = Color(hex: "1894E9")
}
