import Foundation
import SpacemapCore

let UNREACHABLE_THRESHOLD = 16

func printUsage() {
    print("""
    Usage: spacemap-ls [options]

    Options:
      (no args)              List all windows grouped by space
      --kill <app-name>      Kill all windows of the named app (graceful)
      --kill --force <app>   Kill forcefully (SIGKILL)
      --kill-space <N>       Kill all apps on space N
      --kill-space --force <N>
      --help                 Show this help
    """)
}

func killApp(named appName: String, force: Bool) {
    let lowerTarget = appName.lowercased()
    var killed = false
    guard let windows = try? YabaiClient.queryWindows() else {
        fputs("error: could not query yabai windows\n", stderr)
        exit(1)
    }
    let matching = windows.filter { $0.app.lowercased() == lowerTarget }
    if matching.isEmpty {
        print("No windows found for app '\(appName)'")
        return
    }
    let pids = Set(matching.map { $0.pid })
    for pid in pids.sorted() {
        let sig = force ? SIGKILL : SIGTERM
        if kill(pid_t(pid), sig) == 0 {
            print("Killed \(appName) (PID \(pid))")
            killed = true
        } else {
            fputs("warning: kill(\(pid)) failed: \(String(cString: strerror(errno)))\n", stderr)
        }
    }
    if !killed {
        print("No processes killed for '\(appName)'")
    }
}

func killSpace(_ spaceIndex: Int, force: Bool) {
    guard let windows = try? YabaiClient.queryWindows() else {
        fputs("error: could not query yabai windows\n", stderr)
        exit(1)
    }
    let onSpace = windows.filter { $0.space == spaceIndex }
    if onSpace.isEmpty {
        print("No windows found on space \(spaceIndex)")
        return
    }
    let pids = Set(onSpace.map { $0.pid })
    let apps = Set(onSpace.map { $0.app })
    print("Killing apps on space \(spaceIndex): \(apps.sorted().joined(separator: ", "))")
    for pid in pids.sorted() {
        let sig = force ? SIGKILL : SIGTERM
        if kill(pid_t(pid), sig) == 0 {
            print("  Killed PID \(pid)")
        } else {
            fputs("  warning: kill(\(pid)) failed: \(String(cString: strerror(errno)))\n", stderr)
        }
    }
}

func listWindows() {
    let spaces: [YabaiSpace]
    let windows: [YabaiWindow]

    do {
        spaces = try YabaiClient.querySpaces()
        windows = try YabaiClient.queryWindows()
    } catch {
        fputs("error: could not query yabai — is yabai running?\n  \(error)\n", stderr)
        exit(1)
    }

    // Group windows by space
    var bySpace: [Int: [YabaiWindow]] = [:]
    for w in windows {
        bySpace[w.space, default: []].append(w)
    }

    // Also include spaces with no windows
    for s in spaces {
        if bySpace[s.index] == nil {
            bySpace[s.index] = []
        }
    }

    let spaceMap = Dictionary(spaces.map { ($0.index, $0) }, uniquingKeysWith: { a, _ in a })
    let allSpaceIndices = bySpace.keys.sorted()

    var hasUnreachable = false
    for idx in allSpaceIndices {
        let spaceWindows = bySpace[idx]!
        let display = spaceMap[idx].map { "display \($0.display)" } ?? "display ?"
        let unreachable = idx > UNREACHABLE_THRESHOLD
        if unreachable { hasUnreachable = true }

        let marker = unreachable ? "  *** UNREACHABLE (>\(UNREACHABLE_THRESHOLD)) ***" : ""
        print("Space \(idx) [\(display)]\(marker)")

        if spaceWindows.isEmpty {
            print("  (empty)")
        } else {
            // Deduplicate by app+pid for display
            let sorted = spaceWindows.sorted { $0.app < $1.app }
            for w in sorted {
                var flags: [String] = []
                if w.isHidden { flags.append("hidden") }
                if w.isMinimized { flags.append("minimized") }
                let flagStr = flags.isEmpty ? "" : " [\(flags.joined(separator: ","))]"
                print("  • \(w.app) (win \(w.id), pid \(w.pid))\(flagStr)")
            }
        }
        print("")
    }

    if hasUnreachable {
        print("NOTE: Apps marked UNREACHABLE are on spaces >\(UNREACHABLE_THRESHOLD).")
        print("      Use --kill-space <N> or --kill <AppName> to free them.")
    }
}

// --- Argument parsing ---

var args = CommandLine.arguments.dropFirst() // drop binary name

if args.isEmpty {
    listWindows()
} else {
    let first = args.first!
    switch first {
    case "--help", "-h":
        printUsage()
    case "--kill":
        args = args.dropFirst()
        let force = args.first == "--force"
        if force { args = args.dropFirst() }
        guard let appName = args.first else {
            fputs("error: --kill requires an app name\n", stderr)
            printUsage()
            exit(1)
        }
        killApp(named: appName, force: force)
    case "--kill-space":
        args = args.dropFirst()
        let force = args.first == "--force"
        if force { args = args.dropFirst() }
        guard let spaceStr = args.first, let spaceN = Int(spaceStr) else {
            fputs("error: --kill-space requires a space number\n", stderr)
            printUsage()
            exit(1)
        }
        killSpace(spaceN, force: force)
    default:
        fputs("error: unknown option '\(first)'\n", stderr)
        printUsage()
        exit(1)
    }
}
