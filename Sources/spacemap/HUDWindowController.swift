import AppKit
import SwiftUI

class HUDWindowController {
    // Why the HUD is on screen, not just whether. A manual show is sticky; a show
    // triggered by a desktop switch is transient and auto-hides when its timer fires.
    private enum Visibility {
        case hidden
        case sticky      // shown by hotkey or menu; stays until toggled off
        case transient   // shown by a space change; auto-hides
    }

    private var panel: NSPanel?
    private var visibility: Visibility = .hidden
    private var autoHideTimer: Timer?
    // Space changes spacemap itself caused (cell click, drag-to-move) must not
    // auto-show the HUD. yabai may emit zero, one or several space_changed signals
    // per operation, so a consumable flag is unreliable — use a short time window.
    private var suppressAutoShowUntil: Date = .distantPast
    private var config = ConfigReader.load()
    private var hoveredCell: Int? = nil
    // Snapshot of grid state taken when HUD opens; reused for hover rerenders so
    // the thumbnail layout doesn't flicker during a drag and cachedWindows stays stable.
    private var currentState: GridState? = nil
    let dragHandler = WindowDragHandler()

    init() {
        dragHandler.onHoverCell = { [weak self] cell in
            guard let self, visibility != .hidden, let state = currentState else { return }
            hoveredCell = cell
            if let p = panel { renderState(state, panel: p) }
        }
        dragHandler.onDropInCell = { [weak self] windowID, spaceIndex in
            guard let self else { return }
            suppressAutoShow()
            YabaiClient.moveWindow(windowID, toSpace: spaceIndex)
            hoveredCell = nil
            refreshState()
        }
    }

    func toggle() {
        switch visibility {
        case .hidden:
            show(as: .sticky)
        case .transient:
            // Promote to sticky: the user wants a closer look at what just flashed up.
            // Refresh first so the window layout is current before they interact with it,
            // then start the drag handler the transient show deliberately skipped.
            cancelAutoHide()
            visibility = .sticky
            refreshState()
            dragHandler.start()
        case .sticky:
            hide()
        }
    }

    private func show(as mode: Visibility) {
        config = ConfigReader.load()
        let focusedIndex = YabaiClient.queryFocusedSpaceIndex()

        if panel == nil { panel = makePanel() }
        guard let panel else { return }

        let state = YabaiClient.buildGridState(config: config, focusedIndex: focusedIndex)
        currentState = state
        dragHandler.cachedWindows = state.windows
        // Capture focused window before HUD renders, so drag handler knows what the user had active.
        dragHandler.focusedWindowIDAtOpen = (try? YabaiClient.queryFocusedWindow()) ?? nil
        renderState(state, panel: panel)
        updateCellFrames(state: state, panel: panel)
        // Skip the global CGEventTap for a transient show: dragging a window into a HUD
        // that vanishes in ~2s isn't a real workflow, and spinning the tap up and down on
        // every desktop switch is pure churn. Promotion to sticky starts it.
        if mode != .transient { dragHandler.start() }
        visibility = mode
    }

    // Called by SocketListener on space_changed.
    // If the HUD is already up, keep it current (rules 1 & 3). If it's hidden, flash it
    // up for config.autoShowDuration seconds (rule 2).
    func handleSpaceChange() {
        if visibility != .hidden {
            refreshState()
            // Rule 3: another switch inside the window restarts the timer from 0.
            // Deliberately refreshState() rather than show() — re-running show() would
            // rebuild and re-center the panel, which visibly flickers on fast switching.
            if visibility == .transient { scheduleAutoHide() }
            return
        }

        // Reload before the duration check, or the opt-out deadlocks: config is otherwise
        // only reassigned inside show(), and show() is gated behind this very check — so
        // with AUTO_SHOW_DURATION=0 at launch the feature could never turn itself back on.
        config = ConfigReader.load()
        guard config.autoShowDuration > 0 else { return }
        guard Date() >= suppressAutoShowUntil else { return }

        show(as: .transient)
        scheduleAutoHide()
    }

    // Called before spacemap's own yabai space mutations, so the space_changed signal
    // they provoke doesn't re-open a HUD the user just dismissed by clicking a cell.
    private func suppressAutoShow(for seconds: TimeInterval = 1.0) {
        suppressAutoShowUntil = Date().addingTimeInterval(seconds)
    }

    private func scheduleAutoHide() {
        cancelAutoHide()
        // SocketListener marshals to main before calling us, so a run-loop Timer is safe.
        // Registered in .common rather than scheduledTimer's .default: the main run loop
        // switches to event-tracking while the status-bar menu is open, and a .default
        // timer would stall there instead of hiding on schedule.
        let timer = Timer(timeInterval: config.autoShowDuration, repeats: false) { [weak self] _ in
            self?.hide()
        }
        RunLoop.main.add(timer, forMode: .common)
        autoHideTimer = timer
    }

    private func cancelAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private func refreshState() {
        guard let panel else { return }
        let focused = YabaiClient.queryFocusedSpaceIndex()
        let state = YabaiClient.buildGridState(config: config, focusedIndex: focused)
        currentState = state
        dragHandler.cachedWindows = state.windows
        renderState(state, panel: panel)
        updateCellFrames(state: state, panel: panel)
    }

    private func renderState(_ state: GridState, panel: NSPanel) {
        let hovered = hoveredCell
        let gridView = GridView(state: state, hoveredCell: hovered) { [weak self] index in
            self?.suppressAutoShow()
            YabaiClient.focusSpace(index)
            self?.hide()
        }
        let size = gridView.idealSize

        let hostingView = NSHostingView(rootView: gridView)
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.setContentSize(size)

        if let screen = NSScreen.main {
            let x = screen.frame.midX - size.width / 2
            let y = screen.frame.midY - size.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        panel.orderFrontRegardless()
    }

    func hide() {
        // Load-bearing: a manual hide during a transient window would otherwise leave a
        // live timer that later hides a HUD the user has since deliberately shown.
        cancelAutoHide()
        panel?.orderOut(nil)
        dragHandler.stop()
        visibility = .hidden
        hoveredCell = nil
        currentState = nil
    }

    private func updateCellFrames(state: GridState, panel: NSPanel) {
        let cellWidth: CGFloat = 80
        let cellHeight: CGFloat = 50
        let gap: CGFloat = 6
        let padding: CGFloat = 12
        // Expand hit rects by half the gap on each side so there are no dead zones
        // between cells — the cursor always lands in whichever cell it's closest to.
        let slotWidth = cellWidth + gap
        let slotHeight = cellHeight + gap

        var frames: [(spaceIndex: Int, frame: CGRect)] = []
        let origin = panel.frame.origin
        let totalHeight = CGFloat(state.config.rows) * (cellHeight + gap) - gap + padding * 2

        // CGEvent.location uses top-left origin (Y increases downward).
        // NSPanel.frame uses bottom-left origin (Y increases upward).
        // Convert panel origin to CGEvent coords: cgY = screenHeight - appKitY - height
        guard let screen = NSScreen.screens.first else { return }
        let screenHeight = screen.frame.height

        for row in 0..<state.config.rows {
            for col in 0..<state.config.cols {
                let spaceIndex = row * state.config.cols + col + 1
                let x = origin.x + padding + CGFloat(col) * (cellWidth + gap) - gap / 2
                // AppKit top of this slot (highest AppKit Y):
                let appKitSlotTop = origin.y + totalHeight - padding - CGFloat(row) * (cellHeight + gap) - gap / 2
                // Convert to CGEvent Y (top-left origin): cgY = screenHeight - appKitTop
                let cgY = screenHeight - appKitSlotTop
                frames.append((spaceIndex: spaceIndex, frame: CGRect(x: x, y: cgY, width: slotWidth, height: slotHeight)))
            }
        }

        dragHandler.cellFrames = frames
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hasShadow = true
        return p
    }
}
