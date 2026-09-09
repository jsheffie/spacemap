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
        menu.addItem(NSMenuItem(title: "Show/Hide Map", action: #selector(toggleHUD), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open Accessibility Permissions", action: #selector(openAccessibility), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Restart spacemap", action: #selector(restartApp), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit spacemap", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item
    }

    @objc private func toggleHUD() { hud.toggle() }

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
