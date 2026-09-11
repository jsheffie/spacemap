import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hud = HUDWindowController()
    private var hotkey: HotkeyMonitor?
    private var socketListener: SocketListener?
    private let socketPath = "/tmp/spacemap_\(NSUserName()).socket"
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.prohibited)
        setupMenubar()
        // Delay slightly so TCC/LaunchServices finishes registering the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let config = ConfigReader.load()
            self.startHotkey(config: config)
            self.socketListener = SocketListener(
                socketPath: self.socketPath,
                healthInterval: config.socketHealthInterval,
                onEvent: { [weak self] in self?.hud.handleSpaceChange() }
            )
            YabaiClient.registerSignals(socketPath: self.socketPath)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        YabaiClient.removeSignals()
        socketListener?.stop()
    }

    private func setupMenubar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "spacemap")
        }
        let menu = NSMenu()
        // Everyday actions first, then the occasional permissions trip, then quit --
        // each group separated so the destructive item isn't adjacent to a common one.
        menu.addItem(NSMenuItem(title: "Show/Hide Map", action: #selector(toggleHUD), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Repaint spacemap", action: #selector(repaintHUD), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Apply desktop colors", action: #selector(applyDesktopColors), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Restart spacemap", action: #selector(restartApp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility Permissions", action: #selector(openAccessibility), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit spacemap", action: #selector(confirmQuit), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleHUD() { hud.toggle() }

    @objc private func repaintHUD() { hud.repaint() }

    @objc private func applyDesktopColors() { hud.applyDesktopColors() }

    @objc private func confirmQuit() {
        let alert = NSAlert()
        alert.messageText = "Quit spacemap?"
        alert.informativeText = "The desktop grid overlay and its hotkey will stop working until you launch spacemap again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        // Esc should cancel, not quit -- NSAlert only wires that up for a button
        // literally titled "Cancel", which this is, but be explicit about it.
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        // The app is .prohibited, so it has no activation of its own and the alert
        // would open behind whatever the user is looking at. Borrow regular activation
        // for the lifetime of the dialog, then hand it back.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(.prohibited)

        if response == .alertFirstButtonReturn { NSApp.terminate(nil) }
    }

    @objc private func openAccessibility() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func restartApp() {
        let bundlePath = Bundle.main.bundleURL.path
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 1 && open \"\(bundlePath)\" --args --restarting"]
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
        NSApp.terminate(nil)
    }

    private func startHotkey(config: GridConfig) {
        let monitor = HotkeyMonitor(config: config.hotkey) { [weak self] in
            self?.hud.toggle()
        }
        monitor.start()
        hotkey = monitor
    }
}

@main
struct SpacemapEntry {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
