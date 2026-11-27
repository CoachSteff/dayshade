# How THOC Wall works

A short map of the code for anyone changing it. Everything lives in `Sources/`; `build.sh` compiles it with `swiftc` into an app bundle, with no Xcode project and no packages.

## The picture

The wallpaper is one SwiftUI view, `WallpaperView`, drawn in a borderless window per display.

- **Window level.** Each window sits at `kCGDesktopWindowLevel`: above the system wallpaper, below the Finder's desktop icons. It ignores mouse events, so clicks reach the desktop. Windows are rebuilt when displays change (`AppDelegate.buildWindows`).
- **Gradient.** A 3 × 3 `MeshGradient` in the perceptual colour space. The four corners stay put; the edge midpoints slide along their edges and the centre wanders, on sine waves with periods of four to seven minutes (`meshPoints`). The outer ring of colours also sways back and forth around the edge (`meshColors`), so the light drifts without turning the composition upside down.
- **Frame rate.** A `TimelineView` drives frames at 30, 20 or 10 fps (Settings › General), capped at 10 in Low Power Mode. It pauses when the screen sleeps, the session is inactive, or the window is fully covered (`NSWindow.occlusionState`).
- **Overlays.** Grain is a tiled noise image in overlay blend. Bars (`BarShape`) and logos (`LogoImage`) are positioned from fractions of the screen, so the same code draws the desktop, the Settings preview and exported stills.

## Colour

`Palette.swift` holds the maths.

- Colours are blended in **OKLab**, which keeps the midpoint between two colours bright instead of muddy grey.
- **Day cycle.** `Sun.swift` computes the sun's elevation from the date and your latitude and longitude (NOAA's low-precision formula, no network needed). `paletteForSun` maps elevation to a blend of the seven schemes. Above the horizon it works relative to today's highest sun, so short winter days still reach midday colours.
- **Dark mode** is a transform, not a second set of schemes. `Lab.deepened` lowers lightness and keeps chroma. Darkened oranges read as brown and darkened greens as olive, so it shifts warm hues towards wine-rose and greens towards teal. The *Dark mode depth* slider blends between the original and the deepened colour.
- **Crossfades.** Switching light and dark fades over four seconds, switching schemes over one and a half (`WallState.darkness`, `WallState.palette`).

## State and settings

- `WallState` (`@Observable`) holds the live state: the saved `WallSettings`, pause flags, the scrubbed or previewed time, and the animation clock. Changing the Motion slider re-anchors the clock, so speed changes without a jump.
- `WallSettings` (`Settings.swift`) is one `Codable` struct saved as JSON in user defaults under `settings.v1`. On load the stored keys are laid over the defaults, so settings saved by an older version keep working when fields are added.
- `WindowState` describes one display: its size, the menu bar height and the Dock insets, read from `NSScreen.frame` and `visibleFrame`. Menu bar strips and Dock shelves use these, through `barFrame`.

## Settings window

`SettingsView.swift` holds the four panes (Colours, Logos, Bars, General), hosted in a normal `NSWindow` because the app is a menu bar accessory.

- **Live preview.** Pinned above the scrolling cards. It redraws at 2 fps, or 15 while *Play a day* runs. Settings changes still show immediately, because they trigger a redraw on their own. A full-speed preview in a window this size cost about 1.3% CPU per frame.
- **Placement grid.** `ZoneGrid` (`GridPicker.swift`) draws every logo or bar as tinted cells and turns a drag into a move, a corner resize or a redraw. The pointer style tells you which, before you press.
- **Location.** `LocationService` (`Location.swift`) uses Core Location for an approximate fix and `CLGeocoder` for search and place names. It only prompts when you choose *Use my location*.

## Lessons kept in the code

- A SwiftUI `.shadow` on an animating view is re-blurred every frame. Put the shadow on a static shape behind it (see `PreviewCard`).
- `ImageRenderer` renders `MeshGradient` correctly, which is what makes `--render`, *Export Current Frame* and the system wallpaper sync possible.
