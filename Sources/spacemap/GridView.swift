import SwiftUI

struct GridView: View {
    let state: GridState
    let hoveredCell: Int?
    let onSelect: (Int) -> Void

    private let cellWidth: CGFloat = 80
    private let cellHeight: CGFloat = 50
    private let gap: CGFloat = 6
    private let padding: CGFloat = 12
    // Height of the column-name strip. Zero when COLUMN_NAMES is unset so the
    // panel measures exactly as it did before this feature existed.
    // NOTE: these constants are duplicated in CellView.cellSize and in
    // HUDWindowController.updateCellFrames -- change all three together or the
    // drag hit rects stop lining up with what's drawn.
    private let headerHeight: CGFloat = 14

    private var showHeader: Bool { !state.config.columnNames.isEmpty }

    var body: some View {
        VStack(spacing: gap) {
            if showHeader { header }
            ForEach(0..<state.config.rows, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<state.config.cols, id: \.self) { col in
                        let spaceIndex = row * state.config.cols + col + 1
                        CellView(
                            spaceIndex: spaceIndex,
                            isFocused: spaceIndex == state.focusedIndex,
                            isDropTarget: spaceIndex == hoveredCell,
                            windows: state.windows(forSpace: spaceIndex),
                            displayBounds: state.displayFrame(forSpace: spaceIndex),
                            cellStyle: state.config.cellStyle,
                            onSelect: onSelect
                        )
                    }
                }
            }
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.ultraThinMaterial)
                .overlay(columnBand)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    // The column-name strip above the grid (#23). Laid out on the same
    // cellWidth/gap stride as the cells so each label sits over its own column.
    // Names live here rather than inside cells because an 80x50 cell is already
    // carrying window rects and an index; a header costs one row of height once
    // instead of stealing space from all rows*cols cells.
    private var header: some View {
        HStack(spacing: gap) {
            ForEach(0..<state.config.cols, id: \.self) { col in
                Text(state.config.name(forColumn: col) ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundColor(headerColor(forColumn: col))
                    .frame(width: cellWidth)
            }
        }
        .frame(height: headerHeight)
    }

    // The focused column's label sits on the color band, so it has to stay legible
    // across the whole palette -- a fixed white vanishes on a light band like
    // F1C453. Pick black or white by the band's perceived luminance (Rec. 601
    // weights: green reads far brighter than blue at the same value). Unfocused
    // columns sit on .ultraThinMaterial and just use a dimmed white.
    private func headerColor(forColumn col: Int) -> Color {
        guard let focused = state.focusedIndex,
              (focused - 1) % state.config.cols == col,
              let rgb = state.config.color(forColumn: col) else {
            return .white.opacity(0.5)
        }
        let r = Double((rgb >> 16) & 0xFF) / 255
        let g = Double((rgb >> 8) & 0xFF) / 255
        let b = Double(rgb & 0xFF) / 255
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance > 0.6 ? .black.opacity(0.8) : .white.opacity(0.95)
    }

    // A colored strip down the focused desktop's column, filling the panel
    // background behind that column -- the cells' gaps and the panel padding
    // above and below included -- so the active column reads as one continuous
    // vertical band (#45). Drawn over .ultraThinMaterial but under the panel
    // border, and behind the cells, which keep their own dark fill.
    @ViewBuilder
    private var columnBand: some View {
        if let focused = state.focusedIndex,
           let color = state.config.color(forColumn: (focused - 1) % state.config.cols) {
            let col = (focused - 1) % state.config.cols
            // Cells are laid out left to right from the padding edge, so column
            // n starts one (cellWidth + gap) stride in. Widening by gap/2 on each
            // side centers the band in the gutters between neighboring columns.
            // Clamp to the panel so the first and last columns' bands don't spill
            // past the rounded edge; clipping to the panel shape then gives them a
            // rounded outer cap that follows the corner.
            let raw = padding + CGFloat(col) * (cellWidth + gap) - gap / 2
            let total = idealSize.width
            let x = max(0, raw)
            let w = min(cellWidth + gap + (raw < 0 ? raw : 0), total - x)
            Color(hex: color)
                .frame(width: w)
                .frame(maxWidth: .infinity, alignment: .leading)
                .offset(x: x)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    var idealSize: CGSize {
        let w = CGFloat(state.config.cols) * (cellWidth + gap) - gap + padding * 2
        var h = CGFloat(state.config.rows) * (cellHeight + gap) - gap + padding * 2
        if showHeader { h += headerHeight + gap }
        return CGSize(width: w, height: h)
    }
}
