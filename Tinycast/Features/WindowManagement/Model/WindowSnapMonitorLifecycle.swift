import Foundation

struct WindowSnapMonitorLifecycle {
    enum Action: Equatable {
        case start
        case stop
    }

    private enum Phase {
        case idle
        case running
        case stopping
    }

    private var phase = Phase.idle
    private(set) var isEnabled = false

    var acceptsEvents: Bool { phase == .running && isEnabled }

    mutating func setEnabled(_ enabled: Bool) -> Action? {
        isEnabled = enabled
        switch (phase, enabled) {
        case (.idle, true):
            phase = .running
            return .start
        case (.running, false):
            phase = .stopping
            return .stop
        default:
            return nil
        }
    }

    mutating func restart() -> Action? {
        guard phase == .running, isEnabled else { return nil }
        phase = .stopping
        return .stop
    }

    mutating func didEnd() -> Action? {
        let wasStopping = phase == .stopping
        phase = .idle
        guard wasStopping, isEnabled else { return nil }
        phase = .running
        return .start
    }
}
