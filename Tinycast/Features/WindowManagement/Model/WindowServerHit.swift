import CoreGraphics
import Foundation

struct WindowServerHit: Equatable, Sendable {
    let windowNumber: Int
    let ownerPID: Int32
    let frame: CGRect

    static func resolve(
        reportedWindowNumber: Int, at point: CGPoint,
        exact: (Int) -> Self?, frontToBack: () -> [Self]
    ) -> Self? {
        if reportedWindowNumber > 0, let hit = exact(reportedWindowNumber) { return hit }
        return frontToBack().first {
            $0.frame.width > 0 && $0.frame.height > 0 && $0.frame.contains(point)
        }
    }
}
