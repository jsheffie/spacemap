import Foundation

public enum YabaiClient {
    public static let yabaiPath = "/opt/homebrew/bin/yabai"

    public static func querySpaces() throws -> [YabaiSpace] {
        let output = try shell(yabaiPath, "-m", "query", "--spaces")
        return try JSONDecoder().decode([YabaiSpace].self, from: Data(output.utf8))
    }

    public static func queryWindows() throws -> [YabaiWindow] {
        let output = try shell(yabaiPath, "-m", "query", "--windows")
        return try JSONDecoder().decode([YabaiWindow].self, from: Data(output.utf8))
    }

    public static func queryFocusedWindow() throws -> Int? {
        let output = try shell(yabaiPath, "-m", "query", "--windows", "--window")
        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(YabaiWindow.self, from: data) else { return nil }
        return json.id
    }

    public static func queryFocusedSpaceIndex() -> Int? {
        let output = (try? shell(yabaiPath, "-m", "query", "--spaces", "--space")) ?? ""
        guard let data = output.data(using: .utf8),
              let json = try? JSONDecoder().decode(YabaiSpace.self, from: data) else { return nil }
        return json.index
    }

    public static func registerSignals(socketPath: String) {
        let action = "echo 1 | nc -U \(socketPath)"
        _ = try? shell(yabaiPath, "-m", "signal", "--add",
                       "label=spacemap_space_changed",
                       "event=space_changed",
                       "action=\(action)")
    }

    public static func removeSignals() {
        _ = try? shell(yabaiPath, "-m", "signal", "--remove", "spacemap_space_changed")
    }

    public static func focusSpace(_ index: Int) {
        _ = try? shell(yabaiPath, "-m", "space", "--focus", "\(index)")
    }

    public static func moveWindow(_ windowID: Int, toSpace spaceIndex: Int) {
        _ = try? shell(yabaiPath, "-m", "window", "\(windowID)", "--space", "\(spaceIndex)")
    }

    public static func shell(_ args: String...) throws -> String {
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
