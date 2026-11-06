import CoreGraphics
import Foundation

struct WindowSnapInteraction<Window> {
    struct Target: Equatable {
        let command: WindowCommand.ID
        let screenID: Int
    }

    struct Drop {
        let window: Window
        let sourceFrame: CGRect
        let target: Target
    }

    private enum Phase {
        case idle
        case pressed(CGPoint, Window, CGRect)
        case tracking(Window, CGRect, Date)
        case armed(Window, CGRect)
    }

    private var phase = Phase.idle
    private let dragThreshold: CGFloat = 8
    private let pollInterval: TimeInterval = 0.05
    private let edgeDepth: CGFloat = 24
    private let cornerExtent: CGFloat = 140

    mutating func mouseDown(at point: CGPoint, window: Window?, frame: CGRect?) {
        guard let window, let frame else {
            phase = .idle
            return
        }
        phase = .pressed(point, window, frame)
    }

    mutating func mouseDragged(
        to point: CGPoint, at now: Date, screens: [WindowPlacementEngine.Screen],
        frameOf: (Window) -> CGRect?
    ) -> Target? {
        switch phase {
        case .idle:
            return nil
        case .pressed(let start, let window, let source):
            guard distance(from: start, to: point) >= dragThreshold else { return nil }
            return confirmMovement(
                of: window, from: source, at: now, point: point, screens: screens,
                frameOf: frameOf)
        case .tracking(let window, let source, let lastPoll):
            guard target(at: point, screens: screens) != nil,
                now.timeIntervalSince(lastPoll) >= pollInterval
            else { return nil }
            return confirmMovement(
                of: window, from: source, at: now, point: point, screens: screens,
                frameOf: frameOf)
        case .armed:
            return target(at: point, screens: screens)
        }
    }

    mutating func mouseUp(
        at point: CGPoint, screens: [WindowPlacementEngine.Screen],
        movementWasProven: Bool = false,
        frameOf: (Window) -> CGRect?
    ) -> Drop? {
        defer { phase = .idle }
        guard let target = target(at: point, screens: screens) else { return nil }

        let candidate: (window: Window, source: CGRect)?
        switch phase {
        case .idle:
            candidate = nil
        case .pressed(let start, let window, let source):
            candidate = distance(from: start, to: point) >= dragThreshold ? (window, source) : nil
        case .tracking(let window, let source, _), .armed(let window, let source):
            candidate = (window, source)
        }
        guard let candidate, let current = frameOf(candidate.window) else { return nil }
        if case .armed = phase {
            return Drop(window: candidate.window, sourceFrame: candidate.source, target: target)
        }
        if movementWasProven {
            return Drop(window: candidate.window, sourceFrame: candidate.source, target: target)
        }
        guard sameSize(current, candidate.source), moved(current, from: candidate.source) else {
            return nil
        }
        return Drop(window: candidate.window, sourceFrame: candidate.source, target: target)
    }

    mutating func reset() { phase = .idle }

    func target(at point: CGPoint, screens: [WindowPlacementEngine.Screen]) -> Target? {
        guard
            let screen = screens.first(where: { containsHalfOpen(point, in: $0.frame) })
                ?? screens.first(where: { containsOuterEdge(point, in: $0.frame) })
        else { return nil }
        let frame = screen.frame
        let left = point.x <= frame.minX + edgeDepth
        let right = point.x >= frame.maxX - edgeDepth
        let top = point.y <= frame.minY + edgeDepth
        let bottom = point.y >= frame.maxY - edgeDepth

        let command: WindowCommand.ID?
        if top, point.x <= frame.minX + cornerExtent {
            command = .topLeftQuarter
        } else if top, point.x >= frame.maxX - cornerExtent {
            command = .topRightQuarter
        } else if bottom, point.x <= frame.minX + cornerExtent {
            command = .bottomLeftQuarter
        } else if bottom, point.x >= frame.maxX - cornerExtent {
            command = .bottomRightQuarter
        } else if left {
            command = .leftHalf
        } else if right {
            command = .rightHalf
        } else if top {
            command = .maximize
        } else if bottom {
            let third = (point.x - frame.minX) / frame.width
            command = third < 1 / 3 ? .firstThird : (third < 2 / 3 ? .centerThird : .lastThird)
        } else {
            command = nil
        }
        return command.map { Target(command: $0, screenID: screen.id) }
    }

    private mutating func confirmMovement(
        of window: Window, from source: CGRect, at now: Date, point: CGPoint,
        screens: [WindowPlacementEngine.Screen], frameOf: (Window) -> CGRect?
    ) -> Target? {
        guard let current = frameOf(window), sameSize(current, source) else {
            phase = .idle
            return nil
        }
        guard moved(current, from: source) else {
            phase = .tracking(window, source, now)
            return nil
        }
        phase = .armed(window, source)
        return target(at: point, screens: screens)
    }

    private func containsHalfOpen(_ point: CGPoint, in frame: CGRect) -> Bool {
        point.x >= frame.minX && point.x < frame.maxX
            && point.y >= frame.minY && point.y < frame.maxY
    }

    private func containsOuterEdge(_ point: CGPoint, in frame: CGRect) -> Bool {
        point.x >= frame.minX && point.x <= frame.maxX
            && point.y >= frame.minY && point.y <= frame.maxY
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        hypot(end.x - start.x, end.y - start.y)
    }

    private func sameSize(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        lhs.size == rhs.size
    }

    private func moved(_ current: CGRect, from source: CGRect) -> Bool {
        distance(from: current.origin, to: source.origin) > 2
    }
}
