import Foundation
import AppKit

enum YabaiClient {
    private static let yabaiPath = "/opt/homebrew/bin/yabai"

    static func querySpaces() throws -> [YabaiSpace] {
        let output = try shell(yabaiPath, "-m", "query", "--spaces")
        return try JSONDecoder().decode([YabaiSpace].self, from: Data(output.utf8))
    }

    static func queryWindows() throws -> [YabaiWindow] {
        let output = try shell(yabaiPath, "-m", "query", "--windows")
        return try JSONDecoder().decode([YabaiWindow].self, from: Data(output.utf8))
    }

    static func queryDisplays() throws -> [YabaiDisplay] {
        let output = try shell(yabaiPath, "-m", "query", "--displays")
        return try JSONDecoder().decode([YabaiDisplay].self, from: Data(output.utf8))
    }

    static func queryFocusedWindow() throws -> Int? {
        let output = try shell(yabaiPath, "-m", "query", "--windows", "--window")
        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(YabaiWindow.self, from: data) else { return nil }
        return json.id
    }

    static func queryFocusedSpaceIndex() -> Int? {
        let output = (try? shell(yabaiPath, "-m", "query", "--spaces", "--space")) ?? ""
        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(YabaiSpace.self, from: data) else { return nil }
        return json.index
    }

    static func registerSignals(socketPath: String) {
        let action = "echo 1 | nc -U \(socketPath)"
        _ = try? shell(yabaiPath, "-m", "signal", "--add",
                       "label=spacemap_space_changed",
                       "event=space_changed",
                       "action=\(action)")
    }

    static func removeSignals() {
        _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_space_changed")
    }

    static func focusSpace(_ index: Int) {
        _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(index)")
    }

    static func moveWindow(_ windowID: Int, toSpace spaceIndex: Int) {
        _ = try? shell(yabaiPath, "-m", "window", "\(windowID)", "--space", "\(spaceIndex)")
    }

    static func buildGridState(config: GridConfig, focusedIndex: Int?) -> GridState {
        let spaces = (try? querySpaces()) ?? []
        let windows = (try? queryWindows()) ?? []
        let displays = (try? queryDisplays()) ?? []

        // Key by index, matching YabaiSpace.display. See the note in GridState.
        var displayFrames: [Int: CGRect] = [:]
        for display in displays { displayFrames[display.index] = display.cgFrame }

        // Fallback when yabai can't be reached. yabai frames are top-left origin in
        // points; NSScreen.frame is bottom-left, so only its size is meaningful here.
        let fallbackSize = NSScreen.main?.frame.size ?? CGSize(width: 2560, height: 1440)
        let displayBounds = displayFrames[1]
            ?? CGRect(origin: .zero, size: fallbackSize)

        return GridState(
            config: config,
            spaces: spaces,
            windows: windows,
            displayFrames: displayFrames,
            displayBounds: displayBounds,
            focusedIndex: focusedIndex
        )
    }

    private static func shell(_ args: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
