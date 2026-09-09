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

    static let `default` = GridConfig(cols: 8, rows: 2, cellStyle: .rects, hotkey: .default, socketHealthInterval: 60, autoShowDuration: 2.0)
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
