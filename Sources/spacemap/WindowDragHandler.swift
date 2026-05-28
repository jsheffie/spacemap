import Cocoa
import SpacemapCore

// Detects when the user drags a real macOS window over the HUD.
// Uses a passive global CGEventTap to track mouse position and NSWorkspace to
// identify which app's window is being dragged.
class WindowDragHandler {
    var onHoverCell: ((Int?) -> Void)?      // called with cell spaceIndex or nil
    var onDropInCell: ((Int, Int) -> Void)? // (windowID, spaceIndex)

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Set by HUDWindowController before the HUD becomes visible.
    // Frames are in CGEvent bottom-left-origin screen coordinates.
    var cellFrames: [(spaceIndex: Int, frame: CGRect)] = []
    // Cached window list populated at HUD-open time.
    var cachedWindows: [YabaiWindow] = []
    // The yabai window that had focus when the HUD opened.
    var focusedWindowIDAtOpen: Int? = nil

    private var lastHoveredCell: Int? = nil
    private var draggedWindowID: Int? = nil
    private var dragStartPoint: CGPoint? = nil
    private var frontmostAppAtMouseDown: String? = nil
    private var isDragging = false

    func start() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue)
        )

        let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .tailAppendEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon -> Unmanaged<CGEvent>? in
                guard let refcon else { return nil }
                let handler = Unmanaged<WindowDragHandler>.fromOpaque(refcon).takeUnretainedValue()
                let cgPoint = event.location
                switch type {
                case .leftMouseDown:    handler.handleMouseDown(at: cgPoint)
                case .leftMouseDragged: handler.handleDrag(at: cgPoint)
                case .leftMouseUp:      handler.handleMouseUp(at: cgPoint)
                default: break
                }
                return nil
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let tap else { return }
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
        reset()
    }

    private func reset() {
        isDragging = false
        draggedWindowID = nil
        dragStartPoint = nil
        lastHoveredCell = nil
        frontmostAppAtMouseDown = nil
    }

    private func handleMouseDown(at cgPoint: CGPoint) {
        dragStartPoint = cgPoint
        isDragging = false
        draggedWindowID = nil
        // Record frontmost app at mouseDown. The HUD is .nonactivatingPanel so it never
        // becomes frontmost — the app whose window was clicked stays frontmost throughout.
        frontmostAppAtMouseDown = NSWorkspace.shared.frontmostApplication?.localizedName
    }

    private func handleDrag(at cgPoint: CGPoint) {
        guard !cellFrames.isEmpty else { return }

        if !isDragging {
            guard let start = dragStartPoint,
                  hypot(cgPoint.x - start.x, cgPoint.y - start.y) > 5 else { return }
            isDragging = true
            draggedWindowID = findDraggedWindowID(atCG: start)
        }

        let cell = cellSpaceIndex(forCG: cgPoint)
        if cell != lastHoveredCell {
            lastHoveredCell = cell
            DispatchQueue.main.async { [weak self] in self?.onHoverCell?(cell) }
        }
    }

    private func handleMouseUp(at cgPoint: CGPoint) {
        defer { reset() }
        guard isDragging,
              let cell = cellSpaceIndex(forCG: cgPoint),
              let windowID = draggedWindowID else {
            if lastHoveredCell != nil {
                DispatchQueue.main.async { [weak self] in self?.onHoverCell?(nil) }
            }
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onHoverCell?(nil)
            self?.onDropInCell?(windowID, cell)
        }
    }

    private func cellSpaceIndex(forCG cgPoint: CGPoint) -> Int? {
        for entry in cellFrames where entry.frame.contains(cgPoint) {
            return entry.spaceIndex
        }
        return nil
    }

    // AXUIElementCopyElementAtPosition uses top-left-origin; CGEvent uses bottom-left.
    private func cgToAX(_ cgPoint: CGPoint) -> CGPoint {
        guard let screen = NSScreen.screens.first else { return cgPoint }
        return CGPoint(x: cgPoint.x, y: screen.frame.height - cgPoint.y)
    }

    // Identify the window being dragged using frontmost app at mouseDown time.
    // For apps with multiple windows, prefer the one focused when the HUD opened,
    // falling back to closest by position.
    private func findDraggedWindowID(atCG cgPoint: CGPoint) -> Int? {
        guard let appName = frontmostAppAtMouseDown else {
            return focusedWindowIDAtOpen
        }

        var candidates = cachedWindows.filter { $0.app == appName }
        if candidates.isEmpty {
            candidates = ((try? YabaiClient.queryWindows()) ?? []).filter { $0.app == appName }
        }

        guard !candidates.isEmpty else { return focusedWindowIDAtOpen }

        if candidates.count == 1 { return candidates[0].id }

        // Multiple windows — prefer the focused one.
        if let focused = focusedWindowIDAtOpen, candidates.contains(where: { $0.id == focused }) {
            return focused
        }

        // Last resort: closest to click point.
        let axPoint = cgToAX(cgPoint)
        return candidates.min {
            hypot($0.cgFrame.minX - axPoint.x, $0.cgFrame.minY - axPoint.y) <
            hypot($1.cgFrame.minX - axPoint.x, $1.cgFrame.minY - axPoint.y)
        }?.id
    }
}
