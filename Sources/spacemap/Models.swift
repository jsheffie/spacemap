import Foundation
import CoreGraphics

enum CellStyle { case rects, icons, hybrid }

struct HotkeyConfig {
    var keyCode: CGKeyCode
    var modifiers: CGEventFlags

    // Default: Ctrl+Page Down
    static let `default` = HotkeyConfig(keyCode: 121, modifiers: .maskControl)
}

struct GridConfig {
    var cols: Int
    var rows: Int
    var cellStyle: CellStyle
    var hotkey: HotkeyConfig
    var socketHealthInterval: Int
    // Seconds to show the HUD after a desktop switch when it's hidden. 0 disables.
    var autoShowDuration: Double
    // Per-column background tints as 0xRRGGBB, cycled when the count != cols.
    // Empty means the feature is off and cells keep their plain dark fill.
    // Stored numerically, not as SwiftUI Colors, to keep this file SwiftUI-free.
    var spaceColors: [UInt32]
    // How much of a column's color survives into its desktop wallpaper: 1.0 is the
    // band color itself, 0.0 is black. Wallpapers are muted by default because a
    // desktop is looked at all day where the HUD band is glanced at for a second.
    var desktopColorMute: Double
    // Per-column header labels, positionally indexed: entry i names column i+1.
    // Empty means the feature is off and no header row is drawn at all -- the
    // panel then measures exactly as it did before the header existed.
    var columnNames: [String]

    static let `default` = GridConfig(cols: 8, rows: 2, cellStyle: .rects, hotkey: .default, socketHealthInterval: 60, autoShowDuration: 2.0, spaceColors: [], desktopColorMute: 0.38, columnNames: [])

    // The tint for a zero-based column, or nil when unconfigured. Cycling keeps
    // short and long palettes on one path; the isEmpty guard is what stops
    // `% count` from trapping on a key that parsed to nothing (SPACE_COLORS=).
    func color(forColumn col: Int) -> UInt32? {
        guard !spaceColors.isEmpty else { return nil }
        return spaceColors[col % spaceColors.count]
    }

    // The label for a zero-based column, or nil when unnamed. Deliberately does
    // NOT cycle the way color(forColumn:) does: a short palette repeating across
    // columns reads as intentional banding, but a repeated *name* would claim two
    // columns are the same thing. Past the end of the list a column is unnamed.
    // Blank entries are holes -- COLUMN_NAMES=a,,c leaves column 2 unnamed rather
    // than shifting c left into it.
    func name(forColumn col: Int) -> String? {
        guard col >= 0, col < columnNames.count else { return nil }
        let name = columnNames[col]
        return name.isEmpty ? nil : name
    }
}

struct YabaiSpace: Decodable {
    let id: Int
    let index: Int
    let display: Int
    let hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case id, index, display
        case hasFocus = "has-focus"
    }
}

struct YabaiWindow: Decodable {
    let id: Int
    let app: String
    let space: Int
    let frame: WindowFrame
    let isHidden: Bool
    let isMinimized: Bool

    struct WindowFrame: Decodable {
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat
    }

    enum CodingKeys: String, CodingKey {
        case id, app, space, frame
        case isHidden = "is-hidden"
        case isMinimized = "is-minimized"
    }

    var cgFrame: CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }
}

struct YabaiDisplay: Decodable {
    let id: Int
    let index: Int
    let frame: YabaiWindow.WindowFrame

    var cgFrame: CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }
}

struct GridState {
    let config: GridConfig
    let spaces: [YabaiSpace]
    let windows: [YabaiWindow]
    // Keyed by display *index* (1-based arrangement order), because that is what
    // YabaiSpace.display holds -- not the display id. On a single-display Mac id and
    // index are both 1, so keying by id would look correct and break once docked.
    let displayFrames: [Int: CGRect]
    // Fallback for a space whose display has no entry in displayFrames.
    let displayBounds: CGRect
    let focusedIndex: Int?

    func windows(forSpace index: Int) -> [YabaiWindow] {
        windows.filter { $0.space == index }
    }

    // The frame of the display that owns this space, for scaling window rects.
    func displayFrame(forSpace index: Int) -> CGRect {
        guard let space = spaces.first(where: { $0.index == index }),
              let frame = displayFrames[space.display] else { return displayBounds }
        return frame
    }
}
