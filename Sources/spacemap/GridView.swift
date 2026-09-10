import SwiftUI

struct GridView: View {
    let state: GridState
    let hoveredCell: Int?
    let onSelect: (Int) -> Void

    private let cellWidth: CGFloat = 80
    private let cellHeight: CGFloat = 50
    private let gap: CGFloat = 6
    private let padding: CGFloat = 12

    var body: some View {
        VStack(spacing: gap) {
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
        let h = CGFloat(state.config.rows) * (cellHeight + gap) - gap + padding * 2
        return CGSize(width: w, height: h)
    }
}
