import Cocoa

// Keyboard capture for editing a column name in the HUD (#52).
//
// Why a tap instead of a SwiftUI TextField: the panel is [.borderless,
// .nonactivatingPanel] under activation policy .prohibited, so it never becomes
// key and nothing in it can be first responder. Making it key would mean an
// NSPanel subclass overriding canBecomeKey plus borrowing .regular activation --
// and WindowDragHandler depends on the HUD never becoming frontmost, so the app
// under the cursor stays focused while you drag.
//
// The other half of the reason is that HUDWindowController.renderState builds a
// fresh NSHostingView on every render (hover, space_changed refresh, show). A
// focused text field would be destroyed mid-edit by a background desktop switch.
// Keystrokes landing in controller state instead means there is no first
// responder to lose: the buffer outlives every re-render.
//
// Lifecycle follows WindowDragHandler rather than HotkeyMonitor: started and
// stopped per edit, idempotent, and nils both handles on stop so start() works
// again. HotkeyMonitor is the wrong model -- it has no stop() and its isStarted
// latch never resets, because it is meant to live for the whole process.
class TextInputMonitor {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var onCharacter: ((String) -> Void)?
    var onBackspace: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    // Canonical values, matching ConfigReader.keyCodeFor's table.
    private static let keyReturn: Int64 = 36
    private static let keyEscape: Int64 = 53
    private static let keyDelete: Int64 = 51

    var isRunning: Bool { eventTap != nil }

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        // .defaultTap (not .listenOnly, which the drag handler uses) because this
        // has to *consume* keys: every keystroke that edits a name must not also
        // reach whatever app is frontmost underneath the HUD.
        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<TextInputMonitor>.fromOpaque(refcon).takeUnretainedValue()
                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                return monitor.handle(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else {
            print("spacemap: could not create text input tap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

        switch keyCode {
        case Self.keyReturn:
            DispatchQueue.main.async { [weak self] in self?.onCommit?() }
            return nil
        case Self.keyEscape:
            DispatchQueue.main.async { [weak self] in self?.onCancel?() }
            return nil
        case Self.keyDelete:
            DispatchQueue.main.async { [weak self] in self?.onBackspace?() }
            return nil
        default:
            break
        }

        // Command means a system shortcut (Cmd-Tab, Cmd-Q); let it through
        // untouched rather than swallowing it into the name being typed.
        if event.flags.contains(.maskCommand) {
            return Unmanaged.passUnretained(event)
        }

        // Ask the event for its own text rather than mapping keycodes: the
        // keycode->character mapping is layout dependent, so a hand-rolled table
        // types gibberish on anything but US QWERTY.
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0 else { return Unmanaged.passUnretained(event) }

        let text = String(utf16CodeUnits: chars, count: length)

        // Drop anything that isn't real text. Arrows, PgUp/PgDn and the function
        // keys come back from keyboardGetUnicodeString as NSUpArrowFunctionKey-style
        // scalars in the Private Use Area (U+F700-U+F8FF) -- category .privateUse,
        // not .control -- so filtering on .control alone lets them into the buffer
        // as invisible garbage. Still swallowed (return nil) rather than passed
        // through: while editing, these keys belong to the HUD.
        let isText = text.unicodeScalars.allSatisfy { scalar in
            let category = scalar.properties.generalCategory
            return category != .control && category != .privateUse && category != .format
        }
        guard isText else { return nil }

        // "=" and "," are the two separators the config and the names list split
        // on, so a name containing either could not be read back. Swallow them
        // rather than passing them through to the app underneath.
        let filtered = text.filter { $0 != "=" && $0 != "," }
        guard !filtered.isEmpty else { return nil }

        DispatchQueue.main.async { [weak self] in self?.onCharacter?(filtered) }
        return nil
    }
}
