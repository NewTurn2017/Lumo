import CoreGraphics

enum CaptureCoordinates {
    /// Converts a rect in AppKit view-local coordinates (bottom-left origin, Y up)
    /// into the target display's CoreGraphics-local coordinates (top-left origin, Y down).
    /// Both input and output are in points.
    static func displayLocalRect(viewRect: CGRect, screenHeight: CGFloat) -> CGRect {
        CGRect(
            x: viewRect.origin.x,
            y: screenHeight - viewRect.origin.y - viewRect.height,
            width: viewRect.width,
            height: viewRect.height
        )
    }
}
