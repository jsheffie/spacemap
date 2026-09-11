import Foundation
import AppKit

// A finished grid query plus the focused window, since GridState has nowhere to
// carry the latter and the show-from-hidden path needs both from one round.
struct GridSnapshot {
    let state: GridState
    // nil unless the request asked for it; see buildGridSnapshotAsync.
    let focusedWindowID: Int?
}

enum YabaiClient {
    private static let yabaiPath = "/opt/homebrew/bin/yabai"

    // Serial so two space changes can't interleave their queries, and so a superseded
    // round is still sitting in the queue (not mid-fork) when the next one is enqueued.
    private static let queue = DispatchQueue(label: "com.spacemap.yabai")
    // Bumped on main, read on `queue`. A plain Int guarded by a lock rather than an
    // atomic: the contention here is two accesses per space change.
    private static let generationLock = NSLock()
    private static var currentGeneration = 0

    // Call on main before kicking off a request; the returned token is what the work
    // item checks itself against.
    static func nextGeneration() -> Int {
        generationLock.lock()
        defer { generationLock.unlock() }
        currentGeneration += 1
        return currentGeneration
    }

    private static func isCurrent(_ generation: Int) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return generation == currentGeneration
    }

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

    // Synchronous. Still used by DesktopColorizer, which walks spaces with the HUD
    // hidden and wants each step to complete before the next.
    static func buildGridState(config: GridConfig, focusedIndex: Int?) -> GridState {
        // yabai frames are top-left origin in points; NSScreen.frame is bottom-left,
        // so only its size is meaningful here. Main-thread-only, hence the parameter
        // on the assembly routine below.
        let fallbackSize = NSScreen.main?.frame.size ?? CGSize(width: 2560, height: 1440)
        return assembleGridState(config: config,
                                 focusedIndex: focusedIndex,
                                 fallbackScreenSize: fallbackSize)
    }

    // Runs the full query round off the main thread and delivers the result back on it.
    //
    // `generation` must come from nextGeneration(). The token is checked twice: once
    // before the first fork, so a superseded round costs nothing rather than running
    // and being discarded (#41), and once on delivery, so a round that finished while
    // a newer one was enqueued doesn't render stale state. A superseded round calls
    // back with nil.
    //
    // `captureFocusedWindow` gates the fifth query. Only a genuine HUD open needs it;
    // a refresh must not touch focusedWindowIDAtOpen.
    static func buildGridSnapshotAsync(
        config: GridConfig,
        fallbackScreenSize: CGSize,
        captureFocusedWindow: Bool,
        generation: Int,
        completion: @escaping (GridSnapshot?) -> Void
    ) {
        queue.async {
            guard isCurrent(generation) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let focusedIndex = queryFocusedSpaceIndex()
            let state = assembleGridState(config: config,
                                          focusedIndex: focusedIndex,
                                          fallbackScreenSize: fallbackScreenSize)
            let focusedWindow = captureFocusedWindow ? ((try? queryFocusedWindow()) ?? nil) : nil

            guard isCurrent(generation) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let snapshot = GridSnapshot(state: state, focusedWindowID: focusedWindow)
            DispatchQueue.main.async { completion(snapshot) }
        }
    }

    // Shared by the sync and async paths. Deliberately free of AppKit: the caller
    // supplies fallbackScreenSize because NSScreen is main-thread-only.
    private static func assembleGridState(
        config: GridConfig,
        focusedIndex: Int?,
        fallbackScreenSize: CGSize
    ) -> GridState {
        let spaces = (try? querySpaces()) ?? []
        let windows = (try? queryWindows()) ?? []
        let displays = (try? queryDisplays()) ?? []

        // Key by index, matching YabaiSpace.display. See the note in GridState.
        var displayFrames: [Int: CGRect] = [:]
        for display in displays { displayFrames[display.index] = display.cgFrame }

        // Fallback when yabai can't be reached.
        let displayBounds = displayFrames[1]
            ?? CGRect(origin: .zero, size: fallbackScreenSize)

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
        // Discarded rather than piped: an undrained stderr pipe deadlocks the child
        // the moment yabai writes more than its buffer holds.
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Read before wait, or a --windows payload larger than the pipe buffer wedges
        // the child writing while we block waiting for it to exit.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
