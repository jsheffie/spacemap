import Foundation
import CoreGraphics

public struct YabaiSpace: Decodable {
    public let id: Int
    public let index: Int
    public let display: Int
    public let hasFocus: Bool

    enum CodingKeys: String, CodingKey {
        case id, index, display
        case hasFocus = "has-focus"
    }
}

public struct YabaiWindow: Decodable {
    public let id: Int
    public let pid: Int
    public let app: String
    public let space: Int
    public let frame: WindowFrame
    public let isHidden: Bool
    public let isMinimized: Bool

    public struct WindowFrame: Decodable {
        public let x: CGFloat
        public let y: CGFloat
        public let w: CGFloat
        public let h: CGFloat
    }

    enum CodingKeys: String, CodingKey {
        case id, pid, app, space, frame
        case isHidden = "is-hidden"
        case isMinimized = "is-minimized"
    }

    public var cgFrame: CGRect {
        CGRect(x: frame.x, y: frame.y, width: frame.w, height: frame.h)
    }
}
