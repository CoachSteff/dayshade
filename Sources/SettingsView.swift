import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers
import CoreLocation

enum Pane: String, CaseIterable, Identifiable {
    case colors, logos, bars, general
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .colors: "paintpalette.fill"
        case .logos: "seal.fill"
        case .bars: "rectangle.split.1x2.fill"
        case .general: "gearshape.fill"
        }
    }
    var tint: Color {
        switch self {
        case .colors: .thocViolet
        case .logos: Color(hex: "1894E9")
        case .bars: Color(hex: "00B3A6")
        case .general: .gray
        }
    }
}

struct SettingsView: View {
    @Bindable var state: WallState
    let preview: WindowState
    let location: LocationService
    var exportFrame: () -> Void

    @State private var pane: Pane = Pane(rawValue: UserDefaults.standard.string(forKey: "settingsPane") ?? "") ?? .colors

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { p in
                Label {
                    Text(p.title)
                } icon: {
                    Image(systemName: p.symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(p.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .tag(p)
                .padding(.vertical, 3)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            VStack(spacing: 0) {
                // Pinned above the scrolling cards, so it stays in view while you edit further down.
                PreviewCard(state: state, preview: preview)
                    .frame(height: 210)
                    .padding(.horizontal, 24).padding(.vertical, 16)
                Divider()
                ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch pane {
                    case .colors: ColorsPane(state: state, location: location)
                    case .logos: LogosPane(state: state, preview: preview)
                    case .bars: BarsPane(state: state, preview: preview)
                    case .general: GeneralPane(state: state, exportFrame: exportFrame)
                    }
                }
                .padding(24)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle(pane.title)
        }
        .tint(.thocViolet)
        .toggleStyle(.switch)
    }
}

// MARK: - Shared building blocks

struct Card<Content: View>: View {
    var title: String? = nil
    var caption: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    if let caption { Text(caption).font(.callout).foregroundStyle(.secondary) }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var low = "", high = ""
    /// How the value reads; a percentage by default (1.0 = 100%).
    var format: (Double) -> String = { "\(Int(($0 * 100).rounded()))%" }

    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .font(.callout.weight(.medium)).monospacedDigit()
                    .foregroundStyle(editing ? Color.thocViolet : .secondary)
            }
            HStack(spacing: 10) {
                Text(low).font(.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .trailing)
                Slider(value: $value, in: range) { editing = $0 }
                    .overlay(alignment: .topLeading) {
                        // A bubble that rides above the knob while dragging.
                        GeometryReader { g in
                            let f = (value - range.lowerBound) / max(0.0001, range.upperBound - range.lowerBound)
                            Text(format(value))
                                .font(.caption.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Color.thocViolet, in: Capsule())
                                .fixedSize()
                                .position(x: 10 + f * (g.size.width - 20), y: -16)
                                .opacity(editing ? 1 : 0)
                                .scaleEffect(editing ? 1 : 0.8, anchor: .bottom)
                                .animation(.easeOut(duration: 0.15), value: editing)
                        }
                        .allowsHitTesting(false)
                    }
                Text(high).font(.caption).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
            }
        }
    }
}

func hexBinding(_ hex: Binding<String>) -> Binding<Color> {
    Binding(get: { Color(hex: hex.wrappedValue) }, set: { hex.wrappedValue = $0.hex })
}

/// A live miniature of the main display, so every change is visible as you make it.
struct PreviewCard: View {
    let state: WallState
    let preview: WindowState

    var body: some View {
        let size = preview.screenSize
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        // Setting changes show at once; the slow drift only needs a couple of frames a second here,
        // which keeps Settings light. Full speed while a day is playing.
        WallpaperView(state: state, window: preview, maxFPS: state.previewStart == nil ? 2 : 15)
            .aspectRatio(size.width / max(1, size.height), contentMode: .fit)
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.15)))
            // The shadow sits on a static shape: a shadow on the animating view itself is re-blurred every frame.
            .background(shape.fill(.black).shadow(color: .black.opacity(0.25), radius: 14, y: 6))
            .frame(maxWidth: .infinity)
    }
}

struct PaletteSwatch: View {
    let palette: Palette
    var body: some View {
        MeshGradient(width: 3, height: 3,
                     points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.5, 0.5], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
                     colors: palette.colors.map { $0.rgb.color }, colorSpace: .perceptual)
    }
}

// MARK: - Colours

struct ColorsPane: View {
    @Bindable var state: WallState
    let location: LocationService

    var body: some View {
        Card(title: "Appearance", caption: "Auto follows macOS light and dark mode.") {
            Picker("Appearance", selection: $state.settings.appearance) {
                Label("Auto", systemImage: "circle.lefthalf.filled").tag(AppearanceMode.auto)
                Label("Light", systemImage: "sun.max.fill").tag(AppearanceMode.light)
                Label("Dark", systemImage: "moon.fill").tag(AppearanceMode.dark)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }

        SchemesCard(state: state)

        Card(title: "Feel") {
            SliderRow(title: "Motion", value: $state.settings.motion, range: 0...3, low: "Still", high: "Lively")
            SliderRow(title: "Vibrance", value: $state.settings.vibrance, range: 0.4...1.3, low: "Muted", high: "Vivid")
            SliderRow(title: "Dark mode depth", value: $state.settings.depth, range: 0.4...1.15, low: "Dusky", high: "Deep")
            SliderRow(title: "Grain", value: $state.settings.grain, range: 0...1, low: "Clean", high: "Paper")
        }

        TimeCard(state: state, location: location)
    }
}

struct SchemesCard: View {
    @Bindable var state: WallState

    var body: some View {
        Card(title: "Colour schemes",
             caption: "Day cycle blends Night, Dawn, Morning, Midday, Afternoon, Golden hour and Dusk with the sun, so editing those changes the cycle too. Pick any scheme to keep it all day.") {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                swatch(id: "cycle", name: "Day cycle") {
                    LinearGradient(colors: ["dawn", "morning", "midday", "golden", "dusk", "night"].map { cyclePalette($0).colors[4].rgb.color },
                                   startPoint: .leading, endPoint: .trailing)
                }
                ForEach(state.settings.schemes) { scheme in
                    swatch(id: scheme.id, name: scheme.name) { PaletteSwatch(palette: scheme.palette) }
                        .contextMenu { actions(for: scheme) }
                }
                Button(action: newScheme) {
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                            .overlay(Image(systemName: "plus").font(.title3).foregroundStyle(.secondary))
                            .frame(height: 44)
                        Text("New").font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            HStack {
                Button("Import…", systemImage: "square.and.arrow.down", action: importSchemes)
                Button("Export All…", systemImage: "square.and.arrow.up") { export(state.settings.schemes, name: "Dayshade schemes") }
            }
            .controlSize(.small)

            if let i = state.settings.schemes.firstIndex(where: { $0.id == state.settings.scheme }) {
                Divider()
                editor($state.settings.schemes[i])
            }
        }
    }

    private func cyclePalette(_ id: String) -> Palette {
        state.settings.schemes.first { $0.id == id }?.palette ?? ColorSchemeItem.builtins.first { $0.id == id }!.palette
    }

    private func swatch<S: View>(id: String, name: String, @ViewBuilder fill: () -> S) -> some View {
        let selected = state.settings.scheme == id
        return Button { state.settings.scheme = id } label: {
            VStack(spacing: 6) {
                fill()
                    .frame(height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(selected ? Color.thocViolet : .white.opacity(0.12), lineWidth: selected ? 2.5 : 1))
                Text(name).font(.caption).foregroundStyle(selected ? .primary : .secondary).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func editor(_ scheme: Binding<ColorSchemeItem>) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(0..<3) { r in
                    GridRow {
                        ForEach(0..<3) { c in
                            ColorPicker("", selection: hexBinding(scheme.colors[r * 3 + c]), supportsOpacity: false)
                                .labelsHidden()
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: scheme.name).textFieldStyle(.roundedBorder)
                Text("Each well is a point on the screen: the top row is the top edge, the middle one sits behind the logo.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack { actions(for: scheme.wrappedValue) }
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private func actions(for scheme: ColorSchemeItem) -> some View {
        Button("Duplicate", systemImage: "plus.square.on.square") { duplicate(scheme) }
        Button("Export…", systemImage: "square.and.arrow.up") { export([scheme], name: scheme.name) }
        if let original = scheme.original {
            Button("Reset", systemImage: "arrow.uturn.backward") { replace(scheme.id, with: original) }
                .disabled(original == scheme)
        } else {
            Button("Delete", systemImage: "trash", role: .destructive) { delete(scheme) }
        }
    }

    // MARK: Actions

    private func add(_ scheme: ColorSchemeItem) {
        state.settings.schemes.append(scheme)
        state.settings.scheme = scheme.id
    }

    private func newScheme() {
        let (palette, _) = state.palette(at: Date())
        let n = state.settings.schemes.filter { !$0.builtin }.count + 1
        add(ColorSchemeItem(id: UUID().uuidString, name: "My scheme \(n)", colors: palette.hexStrings))
    }

    private func duplicate(_ s: ColorSchemeItem) {
        add(ColorSchemeItem(id: UUID().uuidString, name: s.name + " copy", colors: s.colors))
    }

    private func replace(_ id: String, with s: ColorSchemeItem) {
        if let i = state.settings.schemes.firstIndex(where: { $0.id == id }) { state.settings.schemes[i] = s }
    }

    private func delete(_ s: ColorSchemeItem) {
        if state.settings.scheme == s.id { state.settings.scheme = "cycle" }
        state.settings.schemes.removeAll { $0.id == s.id }
    }

    private func export(_ schemes: [ColorSchemeItem], name: String) {
        let files = schemes.map { SchemeFile(name: $0.name, colors: $0.colors) }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = files.count == 1 ? try? enc.encode(files[0]) : try? enc.encode(files) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = name + ".json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? data.write(to: url)
    }

    /// Accepts one scheme or a list, as written by Export. Imported schemes are always added as new ones.
    private func importSchemes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        var added = 0
        for url in panel.urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            let files = (try? JSONDecoder().decode([SchemeFile].self, from: data))
                ?? (try? JSONDecoder().decode(SchemeFile.self, from: data)).map { [$0] } ?? []
            for f in files where !f.colors.isEmpty {
                add(ColorSchemeItem(id: UUID().uuidString, name: f.name, colors: Palette(hexStrings: f.colors).hexStrings))
                added += 1
            }
        }
        if added == 0 {
            let alert = NSAlert()
            alert.messageText = "No colour schemes found"
            alert.informativeText = "A scheme file looks like {\"name\": \"Sea\", \"colors\": [\"00CABF\", … nine colours]}."
            alert.runModal()
        }
    }
}

struct TimeCard: View {
    @Bindable var state: WallState
    let location: LocationService
    @State private var query = ""

    var body: some View {
        let times = sunTimes(on: Date(), latitude: state.settings.latitude, longitude: state.settings.longitude)
        Card(title: "Time of day", caption: "Colours follow the real sun where you are.") {
            Picker("Location", selection: modeBinding) {
                Label("Use my location", systemImage: "location.fill").tag(LocationMode.auto)
                Label("Choose a place", systemImage: "magnifyingglass").tag(LocationMode.manual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 14) {
                Image(systemName: state.settings.locationMode == .auto ? "location.circle.fill" : "mappin.circle.fill")
                    .font(.title2).foregroundStyle(Color.thocViolet)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.settings.place).font(.body.weight(.medium))
                    Text(String(format: "%.2f°, %.2f°", state.settings.latitude, state.settings.longitude))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if location.busy { ProgressView().controlSize(.small) }
                Label(times.rise.map { $0.formatted(date: .omitted, time: .shortened) } ?? "–", systemImage: "sunrise.fill")
                Label(times.set.map { $0.formatted(date: .omitted, time: .shortened) } ?? "–", systemImage: "sunset.fill")
            }

            if state.settings.locationMode == .auto {
                HStack {
                    Button("Update Location", systemImage: "location") { location.locate() }
                    Text("Approximate, city level. Refreshes when your Mac wakes.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    TextField("Search for a city or address", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { location.search(query) }
                    Button("Search") { location.search(query) }
                }
                ForEach(Array(location.results.enumerated()), id: \.offset) { _, mark in
                    Button {
                        location.choose(mark)
                        query = ""
                    } label: {
                        HStack {
                            Image(systemName: "mappin.and.ellipse")
                            Text([mark.locality ?? mark.name, mark.administrativeArea, mark.country]
                                .compactMap { $0 }.joined(separator: ", "))
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 2)
                }
            }
            if let message = location.message {
                Text(message).font(.callout).foregroundStyle(.orange)
            }

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Try a time")
                    Spacer()
                    Text(scrubLabel).monospacedDigit().foregroundStyle(.secondary)
                }
                HStack {
                    Slider(value: Binding(get: { state.scrubHour ?? currentHour }, set: { state.scrubHour = $0 }), in: 0...24)
                    Button("Now") { state.scrubHour = nil }.disabled(state.scrubHour == nil)
                    Button("Play a day") { state.playDay() }
                }
            }
        }
    }

    private var modeBinding: Binding<LocationMode> {
        Binding(get: { state.settings.locationMode }, set: { mode in
            state.settings.locationMode = mode
            if mode == .auto { location.locate() }
        })
    }

    private var currentHour: Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return Double(c.hour!) + Double(c.minute!) / 60
    }

    private var scrubLabel: String {
        guard let h = state.scrubHour else { return "Now" }
        return String(format: "%02d:%02d", Int(h) % 24, Int((h - floor(h)) * 60))
    }
}

/// One row in the Logos or Bars list.
struct ItemRow<Thumb: View>: View {
    let name: String
    let detail: String
    @Binding var enabled: Bool
    let selected: Bool
    var onSelect: () -> Void
    var onDelete: () -> Void
    @ViewBuilder var thumb: Thumb

    var body: some View {
        HStack(spacing: 12) {
            thumb
                .frame(width: 72, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading) {
                Text(name).lineLimit(1)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $enabled).labelsHidden()
            Button(action: onDelete) { Image(systemName: "trash") }.buttonStyle(.borderless)
        }
        .padding(8)
        .background(selected ? Color.thocViolet.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

@MainActor
private func screenAspect(_ w: WindowState) -> CGFloat { w.screenSize.width / max(1, w.screenSize.height) }

// MARK: - Logos

struct LogosPane: View {
    @Bindable var state: WallState
    let preview: WindowState
    @State private var selected: UUID?

    var body: some View {
        Card(title: "Logos", caption: "Add your own marks in SVG, PDF or PNG. Transparent edges are trimmed automatically.") {
            ForEach($state.settings.logos) { $logo in
                ItemRow(name: logo.name, detail: logo.scope.label, enabled: $logo.enabled,
                        selected: selectedID == logo.id, onSelect: { selected = logo.id }, onDelete: { remove(logo) }) {
                    ZStack {
                        PaletteSwatch(palette: .night)
                        if let img = Logo.image(for: logo.path) {
                            LogoImage(image: img, item: logo, dark: 1, k: 0.1).padding(6)
                        } else {
                            Image(systemName: "exclamationmark.triangle").foregroundStyle(.white)
                        }
                    }
                }
            }
            HStack {
                Button("Add Logo…", systemImage: "plus") { addFile() }
                ForEach([LogoItem.coachsteff, .thoc], id: \.path) { item in
                    if !state.settings.logos.contains(where: { $0.path == item.path }) {
                        Button("Add \(item.name)") { add(item) }
                    }
                }
            }
        }

        if !state.settings.logos.isEmpty {
            Card(title: "Placement", caption: "Violet is the selected logo, grey your other logos, teal your bars. Drag a logo to move it, drag its bottom-right corner to resize it, or drag across empty cells to redraw it.") {
                ZoneGrid(zones: zones, selected: selectionBinding, aspect: screenAspect(preview)) { id, rect in
                    if let i = state.settings.logos.firstIndex(where: { $0.id == id }) { state.settings.logos[i].rect = rect }
                }
            }
        }

        if let i = state.settings.logos.firstIndex(where: { $0.id == selectedID }) {
            let logo = $state.settings.logos[i]
            Card(title: "Look") {
                TextField("Name", text: logo.name).textFieldStyle(.roundedBorder)
                Picker("Colour", selection: logo.tint) {
                    ForEach(LogoTint.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if logo.wrappedValue.tint == .custom {
                    ColorPicker("Tint", selection: hexBinding(logo.tintHex), supportsOpacity: false)
                }
                SliderRow(title: "Opacity", value: logo.opacity, range: 0.1...1, low: "Faint", high: "Solid")
                Toggle("Soft shadow", isOn: logo.shadow)
                Picker("Show on", selection: logo.scope) {
                    ForEach(ScreenScope.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }

    private var selectedID: UUID? { selected ?? state.settings.logos.first?.id }
    private var selectionBinding: Binding<UUID?> { Binding(get: { selectedID }, set: { selected = $0 }) }

    private var zones: [GridZone] {
        state.settings.bars.filter(\.enabled).compactMap { bar in
            barGridRect(bar, window: preview).map { GridZone(id: bar.id, rect: $0, label: bar.name, kind: .ghost) }
        } + state.settings.logos.map { GridZone(id: $0.id, rect: $0.rect, label: $0.name, kind: .editable, enabled: $0.enabled) }
    }

    private func add(_ item: LogoItem) {
        state.settings.logos.append(item)
        selected = item.id
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Logo.allowedTypes
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let path = Logo.importFile(url) else { return }
        add(LogoItem(name: url.deletingPathExtension().lastPathComponent, path: path, rect: .cells(19, 13, 4, 2)))
    }

    private func remove(_ logo: LogoItem) {
        state.settings.logos.removeAll { $0.id == logo.id }
        Logo.removeFile(logo.path)
        if selected == logo.id { selected = nil }
    }
}

// MARK: - Bars

struct BarsPane: View {
    @Bindable var state: WallState
    let preview: WindowState
    @State private var selected: UUID?

    var body: some View {
        Card(title: "Bars and shelves", caption: "Glassy panels that sit on the wallpaper, under your desktop icons: a strip under the menu bar, a shelf behind the Dock, or zones for files.") {
            if state.settings.bars.isEmpty {
                Text("No bars yet.").foregroundStyle(.secondary)
            }
            ForEach($state.settings.bars) { $bar in
                ItemRow(name: bar.name, detail: bar.placement.label, enabled: $bar.enabled,
                        selected: selectedID == bar.id, onSelect: { selected = bar.id },
                        onDelete: { remove(bar) }) {
                    BarThumb(bar: bar, preview: preview)
                }
            }
            Menu("Add Bar", systemImage: "plus") {
                Button("Under the menu bar") {
                    add(BarItem(name: "Menu bar strip", placement: .menuBar, opacity: 0.14, cornerRadius: 0, border: false))
                }
                Button("Behind the Dock") { add(BarItem(name: "Dock shelf", placement: .dock, cornerRadius: 22)) }
                Button("Custom area") { add(BarItem(name: "Shelf \(state.settings.bars.count + 1)", placement: .custom)) }
            }
            .fixedSize()
        }

        if !state.settings.bars.isEmpty {
            Card(title: "Placement", caption: "Violet is the selected bar, grey your other custom bars, teal the menu bar and Dock bars (they follow the system), blue your logos. Drag a custom bar to move it, its bottom-right corner to resize it, or across empty cells to redraw it.") {
                ZoneGrid(zones: zones, selected: selectionBinding, aspect: screenAspect(preview)) { id, rect in
                    if let i = state.settings.bars.firstIndex(where: { $0.id == id }) { state.settings.bars[i].rect = rect }
                }
                if let i = selectedIndex {
                    let bar = $state.settings.bars[i]
                    Divider()
                    Picker("Sits", selection: bar.placement) {
                        ForEach(BarPlacement.allCases) { Text($0.label).tag($0) }
                    }
                    if bar.wrappedValue.placement == .dock {
                        SliderRow(title: "Width", value: bar.dockWidth, range: 0.15...1, low: "Narrow", high: "Full")
                        Text("Follows the Dock's height and side. Hidden while the Dock hides itself.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }

        if let i = selectedIndex {
            let bar = $state.settings.bars[i]
            Card(title: "Look") {
                TextField("Name", text: bar.name).textFieldStyle(.roundedBorder)
                Picker("Glass", selection: bar.style) {
                    ForEach(BarStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if bar.wrappedValue.style == .custom {
                    ColorPicker("Tint", selection: hexBinding(bar.tintHex), supportsOpacity: false)
                }
                SliderRow(title: "Opacity", value: bar.opacity, range: 0.03...0.8, low: "Airy", high: "Solid")
                SliderRow(title: "Corner radius", value: bar.cornerRadius, range: 0...40, low: "Square", high: "Round",
                          format: { "\(Int($0.rounded())) pt" })
                Toggle("Hairline edge", isOn: bar.border)
                Toggle("Drop shadow", isOn: bar.shadow)
                Picker("Show on", selection: bar.scope) {
                    ForEach(ScreenScope.allCases) { Text($0.label).tag($0) }
                }
            }
        }
    }

    private var selectedID: UUID? { selected ?? state.settings.bars.first?.id }
    private var selectedIndex: Int? { state.settings.bars.firstIndex { $0.id == selectedID } }
    private var selectionBinding: Binding<UUID?> { Binding(get: { selectedID }, set: { selected = $0 }) }

    private var zones: [GridZone] {
        state.settings.logos.filter(\.enabled).map { GridZone(id: $0.id, rect: $0.rect, label: $0.name, kind: .ghost, tint: .logoBlue) }
        + state.settings.bars.compactMap { bar in
            if bar.placement == .custom {
                return GridZone(id: bar.id, rect: bar.rect, label: bar.name, kind: .editable, enabled: bar.enabled)
            }
            return barGridRect(bar, window: preview).map { GridZone(id: bar.id, rect: $0, label: bar.name, kind: .locked, enabled: bar.enabled) }
        }
    }

    private func add(_ bar: BarItem) {
        state.settings.bars.append(bar)
        selected = bar.id
    }

    private func remove(_ bar: BarItem) {
        state.settings.bars.removeAll { $0.id == bar.id }
        if selected == bar.id { selected = nil }
    }
}

/// A tiny screen showing where a bar sits.
struct BarThumb: View {
    let bar: BarItem
    let preview: WindowState

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                PaletteSwatch(palette: .midday)
                if let r = barGridRect(bar, window: preview)?.cg(in: g.size) {
                    RoundedRectangle(cornerRadius: min(4, bar.cornerRadius * 0.15), style: .continuous)
                        .fill(.white.opacity(0.55))
                        .overlay(RoundedRectangle(cornerRadius: min(4, bar.cornerRadius * 0.15), style: .continuous)
                            .strokeBorder(.white, lineWidth: 0.5))
                        .frame(width: max(2, r.width), height: max(2, r.height))
                        .offset(x: r.minX, y: r.minY)
                }
            }
        }
    }
}

// MARK: - General

struct GeneralPane: View {
    @Bindable var state: WallState
    var exportFrame: () -> Void
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var confirmReset = false

    var body: some View {
        Card(title: "Startup and menu bar") {
            Toggle("Open at login", isOn: Binding(get: { loginEnabled }, set: setLogin))
            if let loginError { Text(loginError).font(.callout).foregroundStyle(.red) }
            Toggle("Show icon in the menu bar", isOn: $state.settings.showMenuIcon)
            if !state.settings.showMenuIcon {
                Text("To get back here, open Dayshade again from your Applications folder.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }

        Card(title: "Animation") {
            Toggle("Pause animation", isOn: $state.userPaused)
            Toggle("Hide logos and bars", isOn: $state.settings.overlaysHidden)
            Picker("Frame rate", selection: $state.settings.frameRate) {
                ForEach(FrameRate.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Drawing stops while the screen sleeps or a full-screen app covers it, and slows down in Low Power Mode.")
                .font(.callout).foregroundStyle(.secondary)
        }

        Card(title: "System wallpaper") {
            Toggle("Keep the system wallpaper in step", isOn: $state.settings.syncSystemWallpaper)
            Text("Every ten minutes, saves a still of the current colours as your macOS wallpaper, so the lock screen and Mission Control match. Replaces the wallpaper you have set now.")
                .font(.callout).foregroundStyle(.secondary)
            Group {
                Toggle("Show logos on the login screen", isOn: $state.settings.loginScreenLogos)
                Toggle("Show bars on the login screen", isOn: $state.settings.loginScreenBars)
            }
            .disabled(!state.settings.syncSystemWallpaper)
            Button("Export Current Frame…", systemImage: "square.and.arrow.up", action: exportFrame)
        }

        Card {
            HStack {
                Text("Dayshade \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset All Settings…", role: .destructive) { confirmReset = true }
            }
        }
        .confirmationDialog("Reset every setting to the defaults?", isPresented: $confirmReset) {
            Button("Reset", role: .destructive) { state.settings = WallSettings() }
        } message: {
            Text("Logos you added stay on disk but are removed from the wallpaper.")
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "\(error.localizedDescription) Move Dayshade to your Applications folder and try again."
        }
        loginEnabled = SMAppService.mainApp.status == .enabled
    }
}
