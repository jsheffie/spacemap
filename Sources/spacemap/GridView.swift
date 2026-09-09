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
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
    }

    var idealSize: CGSize {
        let w = CGFloat(state.config.cols) * (cellWidth + gap) - gap + padding * 2
        let h = CGFloat(state.config.rows) * (cellHeight + gap) - gap + padding * 2
        return CGSize(width: w, height: h)
    }
}
