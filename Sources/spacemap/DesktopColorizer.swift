import AppKit

// Sets each desktop's macOS wallpaper to a muted version of its grid column color, so
// the column cue exists even when the HUD is closed (#47).
//
// NSWorkspace.setDesktopImageURL applies to the *focused* space only -- verified by
// probe -- so coloring N desktops means walking them: focus, set, next. That's why this
// is only ever driven by an explicit menubar action and never on launch or on a
// space_changed signal.
enum DesktopColorizer {
    struct Result {
        var set = 0
        var skipped = 0
        // Spaces that reported a different focused index than we asked for, so we
        // declined to write rather than risk coloring the wrong desktop.
        var focusMismatched: [Int] = []

        var summary: String {
            var s = "spacemap: colored \(set) desktop\(set == 1 ? "" : "s")"
            if skipped > 0 { s += ", skipped \(skipped)" }
            if !focusMismatched.isEmpty { s += ", focus mismatch on \(focusMismatched)" }
            return s
        }
    }

    // MARK: - Color

    // Blend toward black, keeping `keep` of the original (DESKTOP_COLOR_MUTE). A desktop
    // is looked at all day where the HUD band is glanced at for a second, so the
    // wallpapers are muted by default: at 0.38 the whole palette lands at relative
    // luminance 0.013-0.075, which keeps white text and window chrome readable on top.
    static func muted(_ rgb: UInt32, keep: Double) -> UInt32 {
        let r = UInt32((Double((rgb >> 16) & 0xFF) * keep).rounded())
        let g = UInt32((Double((rgb >> 8) & 0xFF) * keep).rounded())
        let b = UInt32((Double(rgb & 0xFF) * keep).rounded())
        return (r << 16) | (g << 8) | b
    }

    // MARK: - PNG cache

    // macOS stores a *file URL reference*, not pixels, so these must outlive the process
    // and every reinstall. Deliberately not .build/ and not the app bundle: make dev1
    // wipes /Applications/spacemap.app, which would break every colored desktop at once.
    static var colorsDirectory: URL {
        URL(fileURLWithPath: NSString(string: "~/Library/Application Support/spacemap/colors")
            .expandingTildeInPath)
    }

    // A 64x64 solid PNG is plenty -- the wallpaper is a flat color and gets stretched by
    // the .imageScaling option below. Cached by filename so a repeat apply re-encodes
    // nothing.
    static func pngURL(for rgb: UInt32) -> URL? {
        let dir = colorsDirectory
        let url = dir.appendingPathComponent(String(format: "%06X.png", rgb))
        if FileManager.default.fileExists(atPath: url.path) { return url }

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("spacemap: could not create \(dir.path): \(error.localizedDescription)")
            return nil
        }

        let size = NSSize(width: 64, height: 64)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("spacemap: could not encode PNG for \(String(format: "%06X", rgb))")
            return nil
        }
        do {
            try png.write(to: url)
        } catch {
            print("spacemap: could not write \(url.path): \(error.localizedDescription)")
            return nil
        }
        return url
    }

    // MARK: - The walk

    // Colors every desktop the grid can actually show, one column color each. Returns
    // without touching anything when the palette is unconfigured.
    //
    // Bounded to rows * cols on purpose: yabai reports every space it knows about, and a
    // 25th desktop on an 8-wide grid would land on (25-1) % 8 == 0 and get colored as
    // column 1 despite having no cell in the HUD -- a desktop tinted for a column the
    // user can't see.
    static func applyColumnColors(config: GridConfig) -> Result {
        walk(config: config) { spaceIndex in
            let col = (spaceIndex - 1) % config.cols
            return config.color(forColumn: col).map { muted($0, keep: config.desktopColorMute) }
        }
    }

    private static func walk(config: GridConfig, colorFor: (Int) -> UInt32?) -> Result {
        var result = Result()
        if config.spaceColors.isEmpty {
            print("spacemap: SPACE_COLORS is not set, nothing to apply")
            return result
        }

        let spaces = (try? YabaiClient.querySpaces()) ?? []
        guard !spaces.isEmpty else {
            print("spacemap: could not query spaces from yabai")
            return result
        }
        let displayFrames = displayScreens()
        let maxIndex = config.rows * config.cols
        let origin = YabaiClient.queryFocusedSpaceIndex()

        for space in spaces.sorted(by: { $0.index < $1.index }) {
            guard space.index <= maxIndex, let rgb = colorFor(space.index) else {
                result.skipped += 1
                continue
            }
            guard let url = pngURL(for: rgb) else {
                result.skipped += 1
                continue
            }

            YabaiClient.focusSpace(space.index)
            // One confirmation, no retry loop: the probe showed focus landing on the
            // first poll every time, and each query is a ~50ms subprocess spawn. If the
            // assumption ever breaks, the mismatch is reported rather than mis-colored.
            guard YabaiClient.queryFocusedSpaceIndex() == space.index else {
                result.focusMismatched.append(space.index)
                result.skipped += 1
                continue
            }

            let screens = displayFrames[space.display].map { [$0] } ?? NSScreen.screens
            for screen in screens {
                do {
                    try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [
                        .imageScaling: NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue),
                        .allowClipping: NSNumber(value: true),
                    ])
                } catch {
                    print("spacemap: desktop \(space.index): \(error.localizedDescription)")
                }
            }
            result.set += 1
        }

        if let origin { YabaiClient.focusSpace(origin) }
        return result
    }

    // NSScreen keyed by yabai's display *index* (1-based arrangement order), matching
    // YabaiSpace.display -- the same keying GridState.displayFrames uses and for the same
    // reason. Only tested with a single display; multi-display falls back to all screens.
    private static func displayScreens() -> [Int: NSScreen] {
        var map: [Int: NSScreen] = [:]
        for (offset, screen) in NSScreen.screens.enumerated() {
            map[offset + 1] = screen
        }
        return map
    }
}
