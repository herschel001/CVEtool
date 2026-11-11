import CoreGraphics
import Foundation

public struct WindowCandidate: Equatable, Sendable {
    public var owner: String
    public var layer: Int
    public var alpha: Double
    public var bounds: CGRect
    public var ownerPID: Int32

    public init(owner: String, layer: Int, alpha: Double, bounds: CGRect, ownerPID: Int32) {
        self.owner = owner
        self.layer = layer
        self.alpha = alpha
        self.bounds = bounds
        self.ownerPID = ownerPID
    }
}

public enum WindowPicker {
    public static func hit(candidates: [WindowCandidate], cgPoint: CGPoint, ownPID: Int32) -> CGRect? {
        for item in candidates {
            if item.ownerPID == ownPID || item.layer != 0 || item.alpha <= 0.05 { continue }
            let owner = item.owner.lowercased()
            if owner == "dock" || owner == "window server" || owner == "control center" || owner == "systemuiserver" || owner == "notification center" {
                continue
            }
            if item.bounds.width < 80 || item.bounds.height < 48 { continue }
            if item.bounds.contains(cgPoint) { return item.bounds }
        }
        return nil
    }
}

public enum ScreenGeometry {
    /// ScreenCaptureKit display space has a top-left origin and uses points, not pixels.
    public static func captureRect(fromAppKitSelection selection: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: selection.minX,
            y: primaryHeight - selection.maxY,
            width: selection.width,
            height: selection.height
        )
    }

    /// CGWindowList bounds use a top-left origin on the primary display.
    /// AppKit screen frames use a bottom-left origin on that same display.
    public static func appKitRect(fromCGWindowBounds bounds: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: bounds.origin.x,
            y: primaryHeight - bounds.origin.y - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    public static func toolbarFrame(selection: CGRect, toolbarSize: CGSize, screen: CGRect, gap: CGFloat = 12) -> CGRect {
        var origin = CGPoint(
            x: selection.maxX - toolbarSize.width,
            y: selection.minY - gap - toolbarSize.height
        )
        if origin.y < screen.minY + 8 {
            origin.y = selection.maxY + gap
        }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - toolbarSize.width - 8)
        if origin.y + toolbarSize.height > screen.maxY - 8 {
            origin.y = screen.maxY - toolbarSize.height - 8
        }
        return CGRect(origin: origin, size: toolbarSize)
    }

    public static func fullscreenToolbarFrame(toolbarSize: CGSize, screen: CGRect, bottomInset: CGFloat = 28) -> CGRect {
        CGRect(
            x: screen.midX - toolbarSize.width / 2,
            y: screen.minY + bottomInset,
            width: toolbarSize.width,
            height: toolbarSize.height
        )
    }
}
