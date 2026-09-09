import Foundation
import CoreGraphics

enum ConfigReader {
    static func load() -> GridConfig {
        let path = NSString(string: "~/.config/spacemap/config").expandingTildeInPath
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return .default
        }

        var cols = GridConfig.default.cols
        var rows = GridConfig.default.rows
        var cellStyle = GridConfig.default.cellStyle
        var hotkey = GridConfig.default.hotkey
        var socketHealthInterval = GridConfig.default.socketHealthInterval
        var autoShowDuration = GridConfig.default.autoShowDuration

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.isEmpty else { continue }
            let parts = trimmed.components(separatedBy: "=")
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            switch key {
            case "GRID_COLS": cols = Int(value) ?? cols
            case "GRID_ROWS": rows = Int(value) ?? rows
            case "CELL_STYLE":
                switch value {
                case "icons":  cellStyle = .icons
                case "hybrid": cellStyle = .hybrid
                default:       cellStyle = .rects
                }
            case "HOTKEY":
                if let parsed = parseHotkey(value) {
                    hotkey = parsed
                } else {
                    print("spacemap: unrecognized HOTKEY '\(value)', using default")
                }
            case "SOCKET_HEALTH_INTERVAL":
                if let v = Int(value), v > 0 {
                    socketHealthInterval = v
                } else {
                    print("spacemap: invalid SOCKET_HEALTH_INTERVAL '\(value)', using default")
                }
            case "AUTO_SHOW_DURATION":
                // 0 is valid here and means "disabled", unlike SOCKET_HEALTH_INTERVAL.
                if let v = Double(value), v >= 0 {
                    autoShowDuration = v
                } else {
                    print("spacemap: invalid AUTO_SHOW_DURATION '\(value)', using default")
                }
            default: break
            }
        }

        return GridConfig(cols: cols, rows: rows, cellStyle: cellStyle, hotkey: hotkey, socketHealthInterval: socketHealthInterval, autoShowDuration: autoShowDuration)
    }

    private static func parseHotkey(_ value: String) -> HotkeyConfig? {
        let tokens = value.lowercased().components(separatedBy: "+").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !tokens.isEmpty else { return nil }

        let modifierTokens = tokens.dropLast()
        let keyToken = tokens.last!

        var modifiers: CGEventFlags = []
        for token in modifierTokens {
            switch token {
            case "ctrl":  modifiers.insert(.maskControl)
            case "cmd":   modifiers.insert(.maskCommand)
            case "alt":   modifiers.insert(.maskAlternate)
            case "shift": modifiers.insert(.maskShift)
            default:
                print("spacemap: unknown modifier '\(token)' in HOTKEY")
                return nil
            }
        }

        guard let keyCode = keyCodeFor(keyToken) else {
            print("spacemap: unknown key '\(keyToken)' in HOTKEY")
            return nil
        }

        return HotkeyConfig(keyCode: keyCode, modifiers: modifiers)
    }

    private static func keyCodeFor(_ token: String) -> CGKeyCode? {
        let named: [String: CGKeyCode] = [
            "space": 49, "tab": 48, "return": 36, "enter": 36,
            "escape": 53, "delete": 51, "backspace": 51,
            "pgdn": 121, "pagedown": 121, "pgup": 116, "pageup": 116,
            "home": 115, "end": 119,
            "left": 123, "right": 124, "down": 125, "up": 126,
            "f1": 122, "f2": 120, "f3": 99,  "f4": 118,
            "f5": 96,  "f6": 97,  "f7": 98,  "f8": 100,
            "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        ]
        if let code = named[token] { return code }

        let alphanum: [String: CGKeyCode] = [
            "a": 0,  "s": 1,  "d": 2,  "f": 3,  "h": 4,  "g": 5,
            "z": 6,  "x": 7,  "c": 8,  "v": 9,  "b": 11, "q": 12,
            "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18,
            "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24,
            "9": 25, "7": 26, "-": 27, "8": 28, "0": 29, "o": 31,
            "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
            "n": 45, "m": 46,
        ]
        return alphanum[token]
    }
}
