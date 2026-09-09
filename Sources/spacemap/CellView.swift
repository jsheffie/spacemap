import SwiftUI
import AppKit

struct CellView: View {
    let spaceIndex: Int
    let isFocused: Bool
    let isDropTarget: Bool
    let windows: [YabaiWindow]
    let displayBounds: CGRect
    let cellStyle: CellStyle
    let onSelect: (Int) -> Void

    private let cellSize = CGSize(width: 80, height: 50)

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isDropTarget ? Color.green.opacity(0.35) : isFocused ? Color(hex: 0x4a9eff).opacity(0.55) : Color.black.opacity(0.25))

            ForEach(windows, id: \.id) { window in
                switch cellStyle {
                case .rects:  windowRect(window)
                case .icons:  windowIcon(window)
                case .hybrid: windowRect(window)
                }
            }

            if cellStyle == .icons || cellStyle == .hybrid {
                iconStrip()
            }

            Text("\(spaceIndex)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(isFocused ? Color(hex: 0x4a9eff) : .white.opacity(0.4))
                .padding(3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isDropTarget ? Color.green : isFocused ? Color(hex: 0x4a9eff) : Color.white.opacity(0.15),
                    lineWidth: isDropTarget ? 2.5 : isFocused ? 2.5 : 0.5
                )
        )
        .frame(width: cellSize.width, height: cellSize.height)
        .onTapGesture { onSelect(spaceIndex) }
    }

    @ViewBuilder
    private func windowRect(_ window: YabaiWindow) -> some View {
        let scaleX = cellSize.width / displayBounds.width
        let scaleY = cellSize.height / displayBounds.height
        let x = (window.cgFrame.minX - displayBounds.minX) * scaleX
        let y = (window.cgFrame.minY - displayBounds.minY) * scaleY
        let w = max(window.cgFrame.width * scaleX, 2)
        let h = max(window.cgFrame.height * scaleY, 2)

        RoundedRectangle(cornerRadius: 1)
            .fill(appColor(window.app).opacity(0.6))
            .frame(width: w, height: h)
            .offset(x: x, y: y)
    }

    @ViewBuilder
    private func windowIcon(_ window: YabaiWindow) -> some View {
        if !window.isHidden && !window.isMinimized {
            let scaleX = cellSize.width / displayBounds.width
            let scaleY = cellSize.height / displayBounds.height
            let x = (window.cgFrame.minX - displayBounds.minX) * scaleX
            let y = (window.cgFrame.minY - displayBounds.minY) * scaleY
            let w = max(window.cgFrame.width * scaleX, 14)
            let h = max(window.cgFrame.height * scaleY, 14)
            let iconSize = min(w, h)

            if let icon = appIcon(for: window.app) {
                Image(nsImage: icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: iconSize, height: iconSize)
                    .offset(x: x, y: y)
            }
        }
    }

    @ViewBuilder
    private func iconStrip() -> some View {
        let icons = uniqueIconWindows()
        HStack(spacing: 2) {
            ForEach(icons, id: \.id) { window in
                if let icon = appIcon(for: window.app) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 3)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .padding(.bottom, 3)
    }

    private func uniqueIconWindows() -> [YabaiWindow] {
        var seen = Set<String>()
        return windows.filter { seen.insert($0.app).inserted }
    }

    private func appIcon(for appName: String) -> NSImage? {
        NSWorkspace.shared.runningApplications
            .first { $0.localizedName == appName }
            .flatMap { $0.bundleURL }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    private func appColor(_ name: String) -> Color {
        // FNV-1a over UTF-8. Deliberately not `name.hashValue`: Swift seeds String
        // hashing per process, so that produced a new palette on every launch (#31).
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in name.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.7, brightness: 0.9)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
