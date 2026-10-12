import CoreGraphics

/// Ignore floating/split keyboards; only a keyboard spanning the bottom occludes sheets.
enum ShellGeometry {
    static func keyboardOcclusion(bounds: CGRect, keyboard: CGRect) -> CGFloat {
        let overlap = bounds.intersection(keyboard)
        guard !overlap.isNull, bounds.width > 0,
              overlap.maxY >= bounds.maxY - 1,
              overlap.width >= bounds.width * 0.9 else { return 0 }
        return overlap.height
    }
}
