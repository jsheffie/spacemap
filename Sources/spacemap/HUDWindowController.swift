import AppKit
import SwiftUI
import SpacemapCore

class HUDWindowController {
    private var panel: NSPanel?
    private var isVisible = false
    private var config = ConfigReader.load()
    private var hoveredCell: Int? = nil
    // Snapshot of grid state taken when HUD opens; reused for hover rerenders so
    // the thumbnail layout doesn't flicker during a drag and cachedWindows stays stable.
    private var currentState: GridState? = nil
    let dragHandler = WindowDragHandler()

    init() {
        dragHandler.onHoverCell = { [weak self] cell in
            guard let self, isVisible, let state = currentState else { return }
            hoveredCell = cell
            if let p = panel { renderState(state, panel: p) }
        }
        dragHandler.onDropInCell = { [weak self] windowID, spaceIndex in
            guard let self else { return }
            YabaiClient.moveWindow(windowID, toSpace: spaceIndex)
            hoveredCell = nil
            refreshState()
        }
    }

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    private func show() {
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
        dragHandler.start()
        isVisible = true
    }

    // Called by SocketListener on space_changed. Only updates if HUD is already visible.
    func refresh() {
        guard isVisible else { return }
        refreshState()
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
        panel?.orderOut(nil)
        dragHandler.stop()
        isVisible = false
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
