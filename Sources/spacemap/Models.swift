import CoreGraphics
import SpacemapCore

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

    static let `default` = GridConfig(cols: 8, rows: 2, cellStyle: .rects, hotkey: .default, socketHealthInterval: 60)
}

struct GridState {
    let config: GridConfig
    let spaces: [YabaiSpace]
    let windows: [YabaiWindow]
    let displayBounds: CGRect
    let focusedIndex: Int?

    func windows(forSpace index: Int) -> [YabaiWindow] {
        windows.filter { $0.space == index }
    }
}
