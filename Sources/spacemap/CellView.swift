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

            // Window thumbnails live in their own sized+clipped container. The outer
            // ZStack's .frame is applied after .overlay below, so its children are
            // unconstrained -- clipping out there would clip to the wrong bounds and
            // do nothing. yabai can report frames sized for a display resolution
            // that no longer applies (#43), so this is the backstop for float
            // rounding after scaledRect() has already trimmed the geometry.
            ZStack(alignment: .topLeading) {
                ForEach(windows, id: \.id) { window in
                    switch cellStyle {
                    case .rects:  windowRect(window)
                    case .icons:  windowIcon(window)
                    case .hybrid: windowRect(window)
                    }
                }
            }
            .frame(width: cellSize.width, height: cellSize.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 4))

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

    // The portion of a window actually on this display, scaled into cell coords.
    // Intersecting *before* scaling is what fixes #43: after a resolution change
    // yabai still reports pre-change frames for windows on non-visible spaces (a
    // 3440x1415 frame on a 1728x1117 display), and dividing that by the current
    // display size overflows the cell. Clipping to the display models "what part of
    // this window is really here" and handles genuinely offscreen windows the same way.
    private struct ScaledRect {
        let rect: CGRect
        // True when the raw frame wasn't fully on the display -- stale geometry or a
        // legitimately offscreen window. Both mean the rect shown is partial.
        let isClipped: Bool
    }

    private func scaledRect(_ window: YabaiWindow, minSize: CGFloat) -> ScaledRect? {
        let visible = window.cgFrame.intersection(displayBounds)
        guard !visible.isNull, !visible.isEmpty else { return nil }

        let scaleX = cellSize.width / displayBounds.width
        let scaleY = cellSize.height / displayBounds.height
        let w = max(visible.width * scaleX, minSize)
        let h = max(visible.height * scaleY, minSize)
        // Pull the origin back in if the minimum-size floor pushed the rect past the
        // cell edge. A window sitting a few px from the display's right edge scales
        // to a sub-pixel sliver, and inflating it to minSize would otherwise overhang.
        let x = min((visible.minX - displayBounds.minX) * scaleX, cellSize.width - w)
        let y = min((visible.minY - displayBounds.minY) * scaleY, cellSize.height - h)
        let rect = CGRect(x: max(x, 0), y: max(y, 0), width: w, height: h)
        return ScaledRect(rect: rect, isClipped: !displayBounds.contains(window.cgFrame))
    }

    // Marks geometry we can't fully trust, so a clipped rect doesn't read as
    // "one window fills this desktop". A full dashed perimeter was tried first and
    // was far too loud: on a machine that has changed resolution most windows retain
    // dimensions that no longer fit (64% here), and a stale rect scales to fill its
    // cell, so the dashes traced almost every cell border and dominated the map.
    // A single corner tick states the same fact and stays out of the way.
    @ViewBuilder
    private func staleMarker(_ scaled: ScaledRect) -> some View {
        if scaled.isClipped {
            Path { path in
                let inset: CGFloat = 1.5
                let len: CGFloat = 4
                let x = scaled.rect.width - inset
                path.move(to: CGPoint(x: x - len, y: inset))
                path.addLine(to: CGPoint(x: x, y: inset))
                path.addLine(to: CGPoint(x: x, y: inset + len))
            }
            .stroke(Color.white.opacity(0.5), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func windowRect(_ window: YabaiWindow) -> some View {
        if let scaled = scaledRect(window, minSize: 2) {
            RoundedRectangle(cornerRadius: 1)
                .fill(appColor(window.app).opacity(0.6))
                .overlay(staleMarker(scaled))
                .frame(width: scaled.rect.width, height: scaled.rect.height)
                .offset(x: scaled.rect.minX, y: scaled.rect.minY)
        }
    }

    @ViewBuilder
    private func windowIcon(_ window: YabaiWindow) -> some View {
        if !window.isHidden && !window.isMinimized,
           let scaled = scaledRect(window, minSize: 14),
           let icon = appIcon(for: window.app) {
            let iconSize = min(scaled.rect.width, scaled.rect.height)
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
                .overlay(staleMarker(scaled))
                .offset(x: scaled.rect.minX, y: scaled.rect.minY)
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
