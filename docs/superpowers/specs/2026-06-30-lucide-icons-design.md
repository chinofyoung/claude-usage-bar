# Lucide-style Flat Icons — Design

**Date:** 2026-06-30
**Status:** Approved (pending spec review)

## Goal

Replace the app's SF Symbols with flat, uniform-stroke icons matching the
[Lucide](https://lucide.dev) aesthetic, across both the in-app UI (menu bar +
popover + settings) and the macOS app icon.

## Background

The app currently uses SF Symbols throughout:

| Location | Current SF Symbol | Lucide replacement |
|---|---|---|
| Status bar (AppDelegate) | `clock`, `calendar`, `sparkles` | `clock`, `calendar-days`, `sparkles` |
| Popover rows (PopoverView) | `clock`, `calendar`, `sparkles` | same as above |
| Popover footer | `arrow.clockwise`, `gear`, `power` | `refresh-cw`, `settings`, `power` |
| Settings (SettingsView) | `lock.fill` | `lock` |
| App icon | `Resources/AppIcon.icns` (existing) | regenerated, Lucide `activity` glyph |

Lucide icons are stroke-only, drawn on a 24×24 viewBox with `stroke-width="2"`,
`stroke-linecap="round"`, `stroke-linejoin="round"`, `fill="none"`.

## Chosen Approach: native vector rendering (no bundled assets, no dependency)

Each Lucide glyph's **verbatim path data** (the exact `d` strings / `circle` /
`rect` primitives from Lucide's own SVGs) is embedded as Swift constants and turned
into a `CGPath` by a tiny in-house reader, then rendered into an `NSImage` marked
`isTemplate = true` so the system tints it for the menu bar, popover, and control
states automatically.

**Refinement discovered during planning:** the 8 required glyphs use *only* move,
line (`L/H/V`), circular arc (`A` with rx==ry), and close commands — plus `circle`
and rounded-`rect` primitives. **No cubic/quadratic béziers.** A ~120-line reader
covering exactly that subset is lower-risk than hand-deriving arc-to-curve math
separately for each of the 8 icons, and it keeps the geometry verbatim-faithful to
Lucide. This is still no third-party dependency and no bundled asset files — the
path data lives as string constants in source.

### Why this over the alternatives

- **vs. bundling Lucide `.svg`/`.pdf` assets + `Bundle.module`:** The `Makefile`
  hand-copies resources (`Info.plist`, `AppIcon.icns`) and does **not** bundle
  SwiftPM resource bundles. Using `Bundle.module` would require new Makefile steps
  and risks the resource bundle being missing from the packaged `.app`. There is
  also no SVG→PDF converter installed (`rsvg-convert`/`cairosvg`/`inkscape` all
  absent; only `sips` + `iconutil`).
- **vs. a third-party SVG dependency (e.g. SwiftDraw):** unnecessary for 8 fixed
  glyphs and would add a dependency to a dependency-free project. Our reader handles
  only the tiny command subset these icons actually use (no general SVG parser, no
  bézier handling).

### Trade-off accepted

Adding a *new* icon later means hand-translating one more glyph (a few lines),
rather than dropping in an `.svg`. Acceptable for a small, stable icon set.

## Components

### 1. `LucideIcon` (new file: `Sources/ClaudeUsageBar/Views/LucideIcon.swift`)

A single, self-contained unit responsible for producing Lucide icon images.

```
enum LucideIcon: String, CaseIterable {
    case clock, calendar, sparkles, refresh, settings, power, lock

    // Draws the glyph's CGPath into a 24x24 coordinate space.
    private func path() -> CGPath

    // Renders to a template NSImage (AppKit / status bar).
    // pointSize defaults to the call site's need; weight maps to line width.
    func image(pointSize: CGFloat, weight: NSFont.Weight = .medium) -> NSImage
}
```

- **Drawing model:** Each `case` builds a `CGMutablePath` in Lucide's 24×24
  coordinate space using `move`/`addLine`/`addCurve`/`addArc`/`addRoundedRect`,
  matching the source SVG geometry exactly. Strokes are applied at render time with
  `lineWidth` scaled from the 2px@24 stroke ratio to the requested size, with
  `.round` cap and join.
- **Template image:** Render into an `NSImage` via `NSImage(size:flipped:drawingHandler:)`
  (or a bitmap/`CGContext`), then set `image.isTemplate = true`. The size accounts
  for stroke width so the 2px stroke is not clipped at the bounds (inset the 24×24
  box by half the stroke before scaling).
- **Coordinate flip:** AppKit is y-up; SVG is y-down. The drawing space applies a
  vertical flip so glyphs render upright.

### 2. SwiftUI wrapper

A thin SwiftUI view so popover/settings code stays declarative:

```
struct LucideIconView: View {
    let icon: LucideIcon
    var size: CGFloat = 13
    var body: some View {
        Image(nsImage: icon.image(pointSize: size))
            .renderingMode(.template)   // tints with .foregroundColor
    }
}
```

`.renderingMode(.template)` lets existing `.foregroundColor(...)` modifiers in the
popover keep working unchanged.

### 3. Call-site changes

- **AppDelegate.swift** — `iconAttachment(symbolName:color:)` currently builds an
  `NSTextAttachment` from `NSImage(systemSymbolName:)`. Change it to take a
  `LucideIcon` and use `icon.image(pointSize: 11, weight: .medium)`; keep the
  existing per-segment color tinting (`image.withTintColor`-equivalent on the
  template). The three call sites pass `.clock`, `.calendar`, `.sparkles`.
- **PopoverView.swift** — replace `Image(systemName:)` for the 3 metric rows
  (`iconName` becomes a `LucideIcon`) and the footer buttons
  (`arrow.clockwise`→`.refresh`, `gear`→`.settings`, `power`→`.power`) with
  `LucideIconView`. Preserve existing sizes/colors/layout.
- **SettingsView.swift** — replace `Image(systemName: "lock.fill")` with the Lucide
  `.lock` icon at the same size/treatment.

### 4. `useIcons` toggle

Unchanged in behavior. It still shows/hides icons in the status bar and popover —
now the Lucide icons instead of SF Symbols. No setting added or renamed.

### 5. App icon

- **Glyph:** Lucide `activity` (a pulse / line-graph), white stroke.
- **Background:** flat graphite `#1E1E22` rounded square ("squircle"-ish corner
  radius following macOS app-icon proportions, with the glyph inset ~20% padding).
- **Generation:** a script `Scripts/generate-appicon.sh` (or `.swift`) renders the
  composed icon (background + centered white `activity` glyph) to PNGs at the
  standard sizes (16, 32, 64, 128, 256, 512 @1x and @2x → 16…1024), assembles an
  `.iconset`, and runs `iconutil -c icns` to produce `Resources/AppIcon.icns`.
  The `activity` glyph is **not** part of the in-app `LucideIcon` enum (it is never
  shown in-app); its `CGPath` lives in the generator, built with the same drawing
  primitives as `LucideIcon` so the two share style, not code paths.
- **Makefile:** no change required — `make app` already copies
  `Resources/AppIcon.icns` into the bundle. Regeneration is a dev-time step.

## Data flow

No runtime data flow change. Icons are pure presentation:

```
LucideIcon.path()  ->  stroke into CGContext  ->  template NSImage
                                                      |
                            AppDelegate (status bar) -+- PopoverView / SettingsView (SwiftUI)
```

## Error handling

Rendering is deterministic and total — there is no I/O, no parsing, no external
resource, so there are no runtime failure modes to handle. If a glyph's path is
empty (programming error), the produced image is blank but valid; the test suite
guards against this.

## Testing

New `Tests/ClaudeUsageBarTests/LucideIconTests.swift`:

- For every `LucideIcon` case, `image(pointSize:)` returns an `NSImage` whose
  `size` matches the requested point size (within rounding) and whose `isTemplate`
  is `true`.
- The rendered image is non-blank: rasterize to a bitmap and assert at least one
  non-transparent pixel (guards against an empty/mis-built `CGPath`).
- Existing tests continue to pass (`swift test`, full suite).

Manual verification (via `make run`): menu bar shows the three Lucide metric icons;
popover rows + footer render Lucide glyphs; settings shows the Lucide lock; the
toggle still hides/shows them; the dock/Finder app icon shows the new graphite
`activity` icon.

## Out of scope

- No change to usage logic, polling, keychain, or settings model fields.
- No new user-facing settings (no icon-style picker).
- No bundled SVG assets; no third-party dependencies.

## Build / packaging impact

- In-app icons: zero Makefile changes (pure code).
- App icon: replaces the committed `Resources/AppIcon.icns`; regenerated by a
  dev-time script. No change to `make app` / `make app-universal`.
