import Foundation

// macOS's "Automatically rearrange Spaces based on most recent use" (System Settings ->
// Desktop & Dock -> Mission Control) reorders spaces behind the app's back. spacemap's
// whole premise is that desktop N is always in the same grid cell, so with this on the
// grid silently points at the wrong desktops -- no error, just a map that lies.
//
// Backing pref: com.apple.dock mru-spaces.
enum MRUSpaces {
    enum State {
        case compatible    // explicitly false: spaces stay put
        case rearranging   // explicitly true: spaces reorder, grid unreliable
        case unknown       // never set, or an unexpected type
    }

    private static let domain = "com.apple.dock" as CFString
    private static let key = "mru-spaces" as CFString

    // Read through CFPreferences rather than shelling to `defaults`: `defaults` is a
    // separate process with its own view of cfprefsd's cache and can disagree with us
    // right after a write, and this runs on every HUD open where a subprocess spawn
    // would be pure waste.
    //
    // On an account that has never touched the setting the key is absent entirely
    // (verified: it stays absent across a Dock restart -- the Dock does not write a
    // default back). Absent reads as .unknown, which callers MUST treat as needing a
    // fix, since macOS's effective default is believed to be *enabled*. Mapping
    // .unknown to compatible would silently skip the warning for exactly the users who
    // have never touched the setting.
    static func state() -> State {
        CFPreferencesAppSynchronize(domain)
        guard let value = CFPreferencesCopyAppValue(key, domain) else { return .unknown }
        guard let number = value as? NSNumber else { return .unknown }
        return number.boolValue ? .rearranging : .compatible
    }

    static func needsFixing() -> Bool {
        switch state() {
        case .compatible: return false
        case .rearranging, .unknown: return true
        }
    }

    // Writes the pref, then restarts the Dock so it picks the change up (the Dock reads
    // mru-spaces at launch, so the order matters).
    //
    // The write goes through `defaults` rather than CFPreferencesSetAppValue on purpose:
    // this is the canonical, known-good sequence every setup guide runs, and it flushes
    // through a separate process before the Dock is killed. Writing another app's domain
    // in-process and immediately killing that app is the case where cfprefsd caching
    // bites hardest.
    @discardableResult
    static func disableRearranging() -> Bool {
        guard run("/usr/bin/defaults", ["write", "com.apple.dock", "mru-spaces", "-bool", "false"]) else {
            return false
        }
        return run("/usr/bin/killall", ["Dock"])
    }

    private static func run(_ path: String, _ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: path)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            return false
        }
    }
}
