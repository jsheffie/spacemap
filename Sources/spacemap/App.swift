import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let hud = HUDWindowController()
    private var hotkey: HotkeyMonitor?
    private var socketListener: SocketListener?
    private let socketPath = "/tmp/spacemap_\(NSUserName()).socket"
    private var statusItem: NSStatusItem?
    // Both hidden unless mru-spaces is wrong (#22). Stored so refreshOrderingWarning()
    // can toggle them without rebuilding the menu.
    private var fixOrderingItem: NSMenuItem?
    private var fixOrderingSeparator: NSMenuItem?

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
            self.refreshOrderingWarning()
        }
        // Re-check whenever the HUD opens, so the warning clears itself as soon as the
        // user fixes the setting -- by any route, including System Settings directly.
        hud.onShow = { [weak self] in self?.refreshOrderingWarning() }
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
        menu.delegate = self
        // The space-ordering warning sits above everything, hidden unless it applies:
        // a permanently visible item advertising a problem you don't have is clutter.
        let fixItem = NSMenuItem(title: "⚠ Fix Space Ordering…", action: #selector(fixSpaceOrdering), keyEquivalent: "")
        let fixSeparator = NSMenuItem.separator()
        fixItem.isHidden = true
        fixSeparator.isHidden = true
        menu.addItem(fixItem)
        menu.addItem(fixSeparator)
        fixOrderingItem = fixItem
        fixOrderingSeparator = fixSeparator
        // Everyday actions first, then the occasional permissions trip, then quit --
        // each group separated so the destructive item isn't adjacent to a common one.
        menu.addItem(NSMenuItem(title: "Show/Hide Map", action: #selector(toggleHUD), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Repaint spacemap", action: #selector(repaintHUD), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Apply desktop colors", action: #selector(applyDesktopColors), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Rename columns…", action: #selector(renameColumns), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reset column names", action: #selector(resetColumnNames), keyEquivalent: ""))
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
    // Entry point for renaming when there is no header to click: COLUMN_NAMES unset
    // means no header is drawn, so a fresh install has no click target (#52).
    @objc private func renameColumns() { hud.beginEditing(column: 0) }
    @objc private func resetColumnNames() { hud.resetColumnNames() }

    // The item is only ever *seen* when the menubar icon is clicked, so refresh at
    // display time too: fix the setting by hand, never open the HUD, click the menubar,
    // and the warning would otherwise be stale.
    func menuWillOpen(_ menu: NSMenu) {
        refreshOrderingWarning()
    }

    private func refreshOrderingWarning() {
        let needsFixing = MRUSpaces.needsFixing()
        fixOrderingItem?.isHidden = !needsFixing
        fixOrderingSeparator?.isHidden = !needsFixing
        let symbol = needsFixing ? "exclamationmark.triangle.fill" : "square.grid.3x3"
        statusItem?.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "spacemap")
    }

    @objc private func fixSpaceOrdering() {
        let alert = NSAlert()
        alert.messageText = "Fix space ordering?"
        alert.informativeText = """
            spacemap needs desktops to stay in a fixed order, but macOS is set to rearrange \
            them by most recent use — so the grid may point at the wrong desktop.

            "Fix It" turns off that setting and restarts the Dock. Your windows and desktops \
            are not affected, but the Dock will disappear for a second.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Fix It")
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        // Same activation dance as confirmQuit: the app is .prohibited, so without
        // borrowing .regular the alert opens behind whatever the user is looking at.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(.prohibited)

        switch response {
        case .alertFirstButtonReturn:
            applyOrderingFix()
        case .alertSecondButtonReturn:
            openMissionControlSettings()
        default:
            break
        }
    }

    private func applyOrderingFix() {
        guard MRUSpaces.disableRearranging() else {
            presentOrderingFixFailure()
            return
        }
        // killall Dock restarts the process that owns Mission Control, so cached space
        // indices can shift underneath us. Give the Dock a moment to come back, then
        // re-query rather than trusting what we had. repaint() re-reads config and
        // rebuilds the grid from a fresh yabai query.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshOrderingWarning()
            self?.hud.repaint()
        }
    }

    private func presentOrderingFixFailure() {
        let alert = NSAlert()
        alert.messageText = "Couldn't change the setting"
        alert.informativeText = """
            spacemap couldn't turn off "Automatically rearrange Spaces based on most recent \
            use". You can change it yourself in System Settings → Desktop & Dock → Mission \
            Control.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.last?.keyEquivalent = "\u{1b}"

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        NSApp.setActivationPolicy(.prohibited)

        if response == .alertFirstButtonReturn { openMissionControlSettings() }
    }

    // Desktop & Dock is the Dock pane (Expose.prefPane has no usable Info.plist on
    // macOS 15). Note the window opens on whichever space System Settings last used,
    // not necessarily the current one.
    private func openMissionControlSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.dock")!
        NSWorkspace.shared.open(url)
    }

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
