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
    // Fired on every genuine HUD open. AppDelegate uses it to re-check the mru-spaces
    // setting (#22) without this controller needing to know menubar state exists.
    var onShow: (() -> Void)?
    // Set when a transient->sticky promotion lands before the show's query does, so the
    // refresh completion starts the drag handler the promotion couldn't. See toggle().
    private var startDragHandlerOnNextRefresh = false
    // Column-name editing (#52). Deliberately NOT a Visibility case: that enum
    // means *why* the HUD is on screen, and an edit has to hand back to whichever
    // of .sticky/.transient was in effect when it started. Kept on the controller
    // rather than in SwiftUI @State because renderState rebuilds the whole
    // NSHostingView on every render -- @State would not survive a space_changed.
    private var editingColumn: Int? = nil
    // Set when an edit is requested while the HUD is still opening; consumed by
    // show()'s completion. A timer would be a race -- show() is async since #41,
    // so a slow yabai round trip would leave the user typing into nothing.
    private var beginEditOnNextRender: Int? = nil
    private var editBuffer: String = ""
    private let textInput = TextInputMonitor()
    private var isEditing: Bool { editingColumn != nil }
    // The focused window a desktop walk must hand back to the reopened HUD, applied in
    // show()'s completion because the walk can't write it after an async show. See
    // runDesktopWalk().
    private var pendingFocusedWindowRestore: Int?

    init() {
        dragHandler.onHoverCell = { [weak self] cell in
            guard let self, visibility != .hidden, !isEditing, let state = currentState else { return }
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
        // The hotkey fires through HotkeyMonitor, which has no stop() and cannot be
        // suppressed, so an in-flight edit is defended here rather than by relying
        // on which tap sees the key first. Ctrl+<hotkey> mid-edit commits the name
        // instead of hiding the HUD out from under it.
        if isEditing {
            commitEditing()
            return
        }
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
            // Starting the tap needs populated caches: on the empty-cache path drops get
            // swallowed by the cellFrames.isEmpty guard and findDraggedWindowID falls back
            // to a blocking main-thread query. If the transient show's round hasn't landed
            // yet (refreshState() is async since #41), hand the job to the refresh
            // completion rather than starting now or dropping it.
            if currentState != nil {
                dragHandler.start()
            } else {
                startDragHandlerOnNextRefresh = true
            }
        case .sticky:
            hide()
        }
    }

    // Menubar "Repaint spacemap". Forces a fresh config read and yabai query, and
    // rebuilds + re-centers the panel -- unlike refreshState(), which deliberately
    // re-renders in place to avoid flicker on fast space switching. A resolution
    // change needs the re-center, since the panel is positioned from NSScreen.main.
    // Note this cannot fix stale yabai *window* frames: macOS never re-lays-out a
    // non-visible space, so those frames stay wrong (see #43 and CellView).
    func repaint() {
        cancelAutoHide()
        show(as: .sticky)
    }

    // Split across the yabai round trip (#41). Everything that decides *whether* and
    // *how* to show happens synchronously here; everything that needs query results
    // happens in the completion. visibility is assigned in this prologue rather than
    // at the end: handleSpaceChange() branches on it, so leaving it .hidden for the
    // ~50ms the queries take would let every space change in that window kick off
    // another full show instead of superseding this one.
    private func show(as mode: Visibility) {
        config = ConfigReader.load()

        // Must be read before the assignment below. A genuine open is the only time we
        // re-capture the focused window -- repainting an already-visible HUD must not
        // replace the window the user had active with whatever happens to be focused
        // now (repaint() and runDesktopWalk() both depend on this being false).
        let isGenuineOpen = visibility == .hidden
        // NSScreen is main-thread-only, so the background round can't read it itself.
        let fallbackSize = NSScreen.main?.frame.size ?? CGSize(width: 2560, height: 1440)

        visibility = mode
        let generation = YabaiClient.nextGeneration()

        YabaiClient.buildGridSnapshotAsync(
            config: config,
            fallbackScreenSize: fallbackSize,
            captureFocusedWindow: isGenuineOpen,
            generation: generation
        ) { [weak self] snapshot in
            guard let self else { return }
            // Consumed on every path, not just the success one: a superseded or
            // hidden-out reopen must not leave a stale ID to be applied at some
            // later, unrelated open.
            let restore = pendingFocusedWindowRestore
            pendingFocusedWindowRestore = nil
            guard let snapshot else { return }
            // A hide() between kickoff and landing wins: rendering here would put back
            // a HUD the user just dismissed, and start() would revive a stopped tap.
            guard visibility != .hidden else { return }

            // Deferred to here so the panel is never ordered front empty and then
            // filled a frame later -- a one-frame-late *refresh* is invisible, a
            // one-frame-late first paint is not.
            if panel == nil { panel = makePanel() }
            guard let panel else { return }

            let state = snapshot.state
            currentState = state
            dragHandler.cachedWindows = state.windows
            if let restore {
                // A desktop walk reopening the HUD: keep the window the user had before
                // the walk, not whatever the walk left focused.
                dragHandler.focusedWindowIDAtOpen = restore
            } else if isGenuineOpen {
                dragHandler.focusedWindowIDAtOpen = snapshot.focusedWindowID
            }
            renderState(state, panel: panel)
            // After renderState: reads panel.frame.origin, which renderState sets.
            updateCellFrames(state: state, panel: panel)
            // Skip the global CGEventTap for a transient show: dragging a window into a HUD
            // that vanishes in ~2s isn't a real workflow, and spinning the tap up and down on
            // every desktop switch is pure churn. Promotion to sticky starts it.
            if mode != .transient { dragHandler.start() }
            if let pending = beginEditOnNextRender {
                beginEditOnNextRender = nil
                beginEditing(column: pending)
            }
            onShow?()
        }
    }

    // Called by SocketListener on space_changed.
    // If the HUD is already up, keep it current (rules 1 & 3). If it's hidden, flash it
    // up for config.autoShowDuration seconds (rule 2).
    func handleSpaceChange() {
        // A background desktop switch must not disturb an edit: refreshState()
        // re-renders (destroying the hosting view the caret is drawn in) and the
        // transient branch would re-arm the auto-hide timer under a user who is
        // still typing.
        if isEditing { return }
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

    // MARK: - Column name editing (#52)

    // Entered by clicking a column header, or from the menubar when there is no
    // header to click (COLUMN_NAMES unset means showHeader is false, so a fresh
    // install has no click target).
    func beginEditing(column: Int) {
        guard column >= 0, column < config.cols else { return }
        // Editing while hidden would type into nothing; open first, and hand the
        // edit to show()'s completion rather than guessing at a delay.
        guard visibility != .hidden else {
            beginEditOnNextRender = column
            show(as: .sticky)
            return
        }
        // A pending auto-hide would yank the HUD away mid-edit. The edit makes this
        // sticky: there is no sensible way to "time out" a half-typed name.
        cancelAutoHide()
        visibility = .sticky
        editingColumn = column
        editBuffer = config.name(forColumn: column) ?? ""
        textInput.onCharacter = { [weak self] text in self?.appendToEdit(text) }
        textInput.onBackspace = { [weak self] in self?.backspaceEdit() }
        textInput.onCommit = { [weak self] in self?.commitEditing() }
        textInput.onCancel = { [weak self] in self?.cancelEditing(rerender: true) }
        textInput.start()
        rerenderForEdit()
    }

    func commitEditing() {
        guard let column = editingColumn else { return }
        // Pad to the full width so column N's name lands at index N even when the
        // earlier columns are unnamed -- the list is positional.
        var names = config.columnNames
        if names.count < config.cols {
            names.append(contentsOf: Array(repeating: "", count: config.cols - names.count))
        }
        // Trimmed because parseNameList trims on read: an all-whitespace name would
        // come back as "" anyway, so store it as the blank it will become.
        names[column] = editBuffer.trimmingCharacters(in: .whitespaces)
        ColumnNameStore.save(names)
        endEditing()
        // Re-read so the merged value flows back through the normal path rather
        // than being poked into config here.
        config = ConfigReader.load()
        rerenderForEdit()
    }

    // rerender defaults off so hide() can tear down edit state without painting a
    // panel it is about to order out.
    func cancelEditing(rerender: Bool = false) {
        guard isEditing else { return }
        endEditing()
        if rerender { rerenderForEdit() }
    }

    func resetColumnNames() {
        cancelEditing()
        ColumnNameStore.reset()
        config = ConfigReader.load()
        if visibility != .hidden { rerenderForEdit() }
    }

    private func endEditing() {
        textInput.stop()
        editingColumn = nil
        editBuffer = ""
    }

    private func appendToEdit(_ text: String) {
        guard isEditing else { return }
        editBuffer += text
        rerenderForEdit()
    }

    private func backspaceEdit() {
        guard isEditing, !editBuffer.isEmpty else { return }
        editBuffer.removeLast()
        rerenderForEdit()
    }

    // Paired with updateCellFrames, not renderState alone: starting an edit on an
    // unset COLUMN_NAMES makes the header appear, which makes the panel taller and
    // moves every cell -- leaving the drag hit rects pointing at the old positions.
    private func rerenderForEdit() {
        guard let panel, let state = currentState else { return }
        renderState(state, panel: panel)
        updateCellFrames(state: state, panel: panel)
    }

    // Called before spacemap's own yabai space mutations, so the space_changed signal
    // they provoke doesn't re-open a HUD the user just dismissed by clicking a cell.
    private func suppressAutoShow(for seconds: TimeInterval = 1.0) {
        suppressAutoShowUntil = Date().addingTimeInterval(seconds)
    }

    // Menubar "Apply desktop colors" (#47). This lives here rather than on
    // AppDelegate because muting the HUD needs private state: suppression
    // alone is not enough, since handleSpaceChange() returns early when the HUD is
    // visible -- before the suppressAutoShowUntil guard -- so a walk with the HUD up
    // would run a full blocking yabai triple-query on every one of N space changes.
    func applyDesktopColors() {
        runDesktopWalk { DesktopColorizer.applyColumnColors(config: $0) }
    }

    private func runDesktopWalk(_ walk: (GridConfig) -> DesktopColorizer.Result) {
        // Fresh read: config is otherwise only reassigned in show()/handleSpaceChange(),
        // so a palette edited since the last HUD open wouldn't be picked up here.
        config = ConfigReader.load()
        let wasSticky = visibility == .sticky

        hide()
        // The walk provokes one space_changed per desktop; the 1.0s default is nowhere
        // near long enough to cover 24 of them.
        let spaceCount = max(config.rows * config.cols, 1)
        suppressAutoShow(for: Double(spaceCount) * 0.25 + 2.0)

        // Preserve what the drag handler had captured: show() only re-captures the
        // focused window when coming from .hidden, which is exactly where hide() left us,
        // so a naive restore would replace the user's window with whatever ended up
        // focused after the walk (see the note in show()).
        let windowAtOpen = dragHandler.focusedWindowIDAtOpen

        let result = walk(config)
        print(result.summary)

        // Leave the HUD as we found it -- the user asked to color desktops, not to close
        // their map. The focused desktop is restored by the walk itself.
        if wasSticky {
            // Assigned before show() rather than after: show() is async since #41, so a
            // restore written here would be overwritten when the query lands. The
            // pending value is applied inside the completion instead.
            pendingFocusedWindowRestore = windowAtOpen
            show(as: .sticky)
        }
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

    // Async since #41: shares one generation counter with show(), so whichever request
    // was issued last wins regardless of which kind it was. Never captures
    // focusedWindowIDAtOpen -- that belongs to a genuine open only.
    private func refreshState() {
        let fallbackSize = NSScreen.main?.frame.size ?? CGSize(width: 2560, height: 1440)
        let generation = YabaiClient.nextGeneration()

        YabaiClient.buildGridSnapshotAsync(
            config: config,
            fallbackScreenSize: fallbackSize,
            captureFocusedWindow: false,
            generation: generation
        ) { [weak self] snapshot in
            guard let self, let snapshot else { return }
            guard visibility != .hidden, let panel else { return }

            let state = snapshot.state
            currentState = state
            dragHandler.cachedWindows = state.windows
            renderState(state, panel: panel)
            updateCellFrames(state: state, panel: panel)
            if startDragHandlerOnNextRefresh {
                startDragHandlerOnNextRefresh = false
                dragHandler.start()
            }
        }
    }

    private func renderState(_ state: GridState, panel: NSPanel) {
        let hovered = hoveredCell
        let gridView = GridView(
            state: state,
            hoveredCell: hovered,
            onSelect: { [weak self] index in
                self?.suppressAutoShow()
                YabaiClient.focusSpace(index)
                self?.hide()
            },
            editingColumn: editingColumn,
            editBuffer: editBuffer,
            onEditColumn: { [weak self] col in
                guard let self else { return }
                // Clicking a different column while editing commits the current one,
                // so renaming several in a row doesn't silently discard each.
                if isEditing { commitEditing() }
                beginEditing(column: col)
            }
        )
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
        cancelEditing()
        panel?.orderOut(nil)
        dragHandler.stop()
        visibility = .hidden
        hoveredCell = nil
        currentState = nil
        startDragHandlerOnNextRefresh = false
        beginEditOnNextRender = nil
        pendingFocusedWindowRestore = nil
    }

    private func updateCellFrames(state: GridState, panel: NSPanel) {
        let cellWidth: CGFloat = 80
        let cellHeight: CGFloat = 50
        let gap: CGFloat = 6
        let padding: CGFloat = 12
        // Must match GridView's headerHeight and its showHeader condition: the
        // header adds real height to the panel, and totalHeight below is what
        // converts row indices into screen Y. If this doesn't grow with the panel,
        // every hit rect shifts and drags land on the wrong desktop while the grid
        // still looks perfectly correct.
        let headerHeight: CGFloat = 14
        // Must match GridView.showHeader exactly, editing included: starting an edit
        // with COLUMN_NAMES unset makes the header appear, and a panel that grew by
        // a header while this still read 0 would offset every hit rect by 20pt.
        let showsHeader = !state.config.columnNames.isEmpty || editingColumn != nil
        let headerSpace: CGFloat = showsHeader ? headerHeight + gap : 0
        // Expand hit rects by half the gap on each side so there are no dead zones
        // between cells — the cursor always lands in whichever cell it's closest to.
        let slotWidth = cellWidth + gap
        let slotHeight = cellHeight + gap

        var frames: [(spaceIndex: Int, frame: CGRect)] = []
        let origin = panel.frame.origin
        let totalHeight = CGFloat(state.config.rows) * (cellHeight + gap) - gap + padding * 2 + headerSpace

        // CGEvent.location uses top-left origin (Y increases downward).
        // NSPanel.frame uses bottom-left origin (Y increases upward).
        // Convert panel origin to CGEvent coords: cgY = screenHeight - appKitY - height
        // Must match the screen renderState() centers the panel on, or hit rects are
        // computed against a different origin than the panel actually sits at.
        guard let screen = NSScreen.main else { return }
        let screenHeight = screen.frame.height

        for row in 0..<state.config.rows {
            for col in 0..<state.config.cols {
                let spaceIndex = row * state.config.cols + col + 1
                let x = origin.x + padding + CGFloat(col) * (cellWidth + gap) - gap / 2
                // AppKit top of this slot (highest AppKit Y):
                let appKitSlotTop = origin.y + totalHeight - padding - headerSpace - CGFloat(row) * (cellHeight + gap) - gap / 2
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
