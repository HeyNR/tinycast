import Foundation

struct WindowSnapMonitorLifecycle {
    enum Action: Equatable {
        case start
        case stop
        case retry
    }

    private enum Phase {
        case idle
        case running
        case stopping
        case waitingToRetry
    }

    private static let maximumRetryCount = 3

    private var phase = Phase.idle
    private var retryCount = 0
    private(set) var isEnabled = false

    var acceptsEvents: Bool { phase == .running && isEnabled }

    mutating func setEnabled(_ enabled: Bool) -> Action? {
        isEnabled = enabled
        if !enabled { retryCount = 0 }
        switch (phase, enabled) {
        case (.idle, true):
            phase = .running
            return .start
        case (.running, false):
            phase = .stopping
            return .stop
        case (.waitingToRetry, false):
            phase = .idle
            return nil
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
        switch phase {
        case .stopping:
            phase = .idle
            guard isEnabled else { return nil }
            phase = .running
            return .start
        case .running:
            phase = .idle
            guard isEnabled, retryCount < Self.maximumRetryCount else { return nil }
            retryCount += 1
            phase = .waitingToRetry
            return .retry
        case .idle, .waitingToRetry:
            return nil
        }
    }

    mutating func retryReady() -> Action? {
        guard phase == .waitingToRetry, isEnabled else { return nil }
        phase = .running
        return .start
    }

    mutating func didReceiveEvent() {
        guard phase == .running else { return }
        retryCount = 0
    }
}
