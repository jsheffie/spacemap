import AppKit
import SpacemapCore

extension YabaiClient {
    static func buildGridState(config: GridConfig, focusedIndex: Int?) -> GridState {
        let spaces = (try? querySpaces()) ?? []
        let windows = (try? queryWindows()) ?? []
        let displayBounds = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 2560, height: 1440)
        return GridState(config: config, spaces: spaces, windows: windows, displayBounds: displayBounds, focusedIndex: focusedIndex)
    }
}
