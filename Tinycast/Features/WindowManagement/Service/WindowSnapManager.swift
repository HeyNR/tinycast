import AppKit

@MainActor
final class WindowSnapManager: HealthCheckable {
    fileprivate struct TapEvent: Sendable {
        let typeRaw: UInt32
        let point: CGPoint
        let timestamp: UInt64
        let generation: UInt64
        let windowNumber: Int
        let ownerPID: pid_t?
        let sourceFrame: CGRect?
        let movementProven: Bool

        fileprivate nonisolated static func capture(
            typeRaw: UInt32, point: CGPoint, timestamp: UInt64, windowNumber: Int,
            generation: UInt64, snapshot: WindowServerHit?, movementProven: Bool
        ) -> Self {
            return Self(
                typeRaw: typeRaw, point: point, timestamp: timestamp,
                generation: generation, windowNumber: windowNumber,
                ownerPID: snapshot?.ownerPID, sourceFrame: snapshot?.frame,
                movementProven: movementProven)
        }

        fileprivate nonisolated static func windowSnapshot(
            reportedNumber: Int, at point: CGPoint
        ) -> WindowServerHit? {
            WindowServerHit.resolve(
                reportedWindowNumber: reportedNumber, at: point,
                exact: { number in
                    guard
                        let rows = CGWindowListCopyWindowInfo(
                            [.optionOnScreenAboveWindow, .optionIncludingWindow],
                            CGWindowID(number)) as? [[String: Any]]
                    else { return nil }
                    return rows.compactMap(windowHit).first { $0.windowNumber == number }
                },
                frontToBack: {
                    guard
                        let rows = CGWindowListCopyWindowInfo(
                            .optionOnScreenOnly, CGWindowID(kCGNullWindowID))
                            as? [[String: Any]]
                    else { return [] }
                    return rows.compactMap(windowHit)
                })
        }

        private nonisolated static func windowHit(_ row: [String: Any]) -> WindowServerHit? {
            guard
                let number = row[kCGWindowNumber as String] as? Int,
                let owner = row[kCGWindowOwnerPID as String] as? NSNumber,
                let boundsValue = row[kCGWindowBounds as String]
            else { return nil }
            guard let bounds = boundsValue as? NSDictionary else { return nil }
            var frame = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(bounds as CFDictionary, &frame) else {
                return nil
            }
            return WindowServerHit(
                windowNumber: number, ownerPID: owner.int32Value, frame: frame)
        }
    }

    fileprivate final class TapBridge: @unchecked Sendable {
        let stream: AsyncStream<TapEvent>
        private let continuation: AsyncStream<TapEvent>.Continuation
        private var windowNumber = 0
        private var lastSnapshot: WindowServerHit?
        private var lastSnapshotTimestamp: UInt64 = 0
        private var sampledDrag = false
        private var generation: UInt64 = 0
        private var gestureSource: CGRect?
        private var movementProven = false
        private var resizeProven = false

        init() {
            let pair = AsyncStream<TapEvent>.makeStream(
                bufferingPolicy: .bufferingNewest(256))
            stream = pair.stream
            continuation = pair.continuation
        }

        func captureAndYield(
            typeRaw: UInt32, point: CGPoint, timestamp: UInt64, reportedWindowNumber: Int
        ) {
            guard let type = CGEventType(rawValue: typeRaw) else { return }
            if type == .leftMouseDown {
                generation &+= 1
                lastSnapshot = TapEvent.windowSnapshot(
                    reportedNumber: reportedWindowNumber, at: point)
                windowNumber = lastSnapshot?.windowNumber ?? 0
                sampledDrag = false
                lastSnapshotTimestamp = timestamp
                gestureSource = lastSnapshot?.frame
                movementProven = false
                resizeProven = false
            }

            let shouldSample =
                type == .leftMouseDown || type == .leftMouseUp
                || (type == .leftMouseDragged
                    && (!sampledDrag || (!movementProven && !resizeProven)
                        || timestamp < lastSnapshotTimestamp
                        || timestamp - lastSnapshotTimestamp >= 50_000_000))
            if shouldSample, windowNumber > 0, type != .leftMouseDown {
                lastSnapshot = TapEvent.windowSnapshot(
                    reportedNumber: windowNumber, at: point)
                lastSnapshotTimestamp = timestamp
                if type == .leftMouseDragged {
                    sampledDrag = true
                    classifyMovement(lastSnapshot?.frame)
                }
            }
            continuation.yield(
                .capture(
                    typeRaw: typeRaw, point: point, timestamp: timestamp,
                    windowNumber: windowNumber,
                    generation: generation, snapshot: lastSnapshot,
                    movementProven: movementProven))
            if type == .leftMouseUp { windowNumber = 0 }
        }

        private func classifyMovement(_ frame: CGRect?) {
            guard let source = gestureSource, let frame else { return }
            if frame.size != source.size {
                resizeProven = true
            } else if hypot(frame.minX - source.minX, frame.minY - source.minY) > 2 {
                movementProven = true
            }
        }

        func finish() { continuation.finish() }

        func hasNewerPress(than generation: UInt64) -> Bool { self.generation != generation }
    }

    private let settings: AppSettings
    private let mover: WindowMover
    private var preview: WindowSnapPreviewController?
    private var interaction = WindowSnapInteraction<WindowMover.CapturedWindow>()
    private var interactionGeneration: UInt64?
    private var tapPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapBridge: TapBridge?
    private var tapTask: Task<Void, Never>?
    private var dropTask: Task<Void, Never>?

    weak var healthTicker: HealthTicker?

    init(settings: AppSettings, mover: WindowMover) {
        self.settings = settings
        self.mover = mover
    }

    func applyEnabled() {
        guard settings.windowManagementEnabled, settings.windowSnapEnabled else {
            healthTicker?.unsubscribe(self)
            tearDownTap()
            return
        }
        healthTicker?.subscribe(self)
        guard Permissions.ensureAccessibility() else {
            tearDownTap()
            return
        }
        installTapIfNeeded()
    }

    func stop() {
        healthTicker?.unsubscribe(self)
        tearDownTap()
    }

    func healthCheck() {
        guard settings.windowManagementEnabled, settings.windowSnapEnabled else {
            stop()
            return
        }
        guard Permissions.isAccessibilityTrusted() else {
            tearDownTap()
            return
        }
        guard let tapPort else {
            installTapIfNeeded()
            return
        }
        guard CFMachPortIsValid(tapPort) else {
            tearDownTap()
            installTapIfNeeded()
            return
        }
        if !CGEvent.tapIsEnabled(tap: tapPort) { tapWasDisabled() }
    }

    private func installTapIfNeeded() {
        guard tapPort == nil else { return }
        let bridge = TapBridge()
        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: windowSnapEventTapCallback,
                userInfo: Unmanaged.passUnretained(bridge).toOpaque())
        else { return }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        tapPort = port
        runLoopSource = source
        tapBridge = bridge
        tapTask = Task { @MainActor [weak self, stream = bridge.stream] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                await self?.handle(event, bridge: bridge)
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
    }

    private func tearDownTap() {
        dropTask?.cancel()
        dropTask = nil
        tapTask?.cancel()
        tapTask = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let tapPort {
            CGEvent.tapEnable(tap: tapPort, enable: false)
            CFMachPortInvalidate(tapPort)
            self.tapPort = nil
        }
        tapBridge?.finish()
        tapBridge = nil
        resetInteraction()
    }

    private func resetInteraction() {
        interaction.reset()
        interactionGeneration = nil
        preview?.hide()
    }

    private func tapWasDisabled() {
        resetInteraction()
        if let tapPort { CGEvent.tapEnable(tap: tapPort, enable: true) }
    }

    private func handle(_ event: TapEvent, bridge: TapBridge) async {
        guard !Task.isCancelled, tapBridge === bridge else { return }
        guard let type = CGEventType(rawValue: event.typeRaw) else { return }
        let nativeScreens = NSScreen.screens
        let geometry = AXGeometry(screens: nativeScreens)
        let screens = AXScreens.converted(nativeScreens, geometry: geometry)

        switch type {
        case .leftMouseDown:
            let window = await capturedWindow(event)
            guard !Task.isCancelled, tapBridge === bridge else { return }
            interaction.mouseDown(
                at: event.point, window: window, frame: event.sourceFrame)
            interactionGeneration = event.generation
        case .leftMouseDragged:
            guard validateInteraction(event) else { return }
            drag(
                to: event.point,
                at: Date(timeIntervalSinceReferenceDate: TimeInterval(event.timestamp) / 1_000_000_000),
                frame: event.sourceFrame, screens: screens, geometry: geometry)
        case .leftMouseUp:
            guard validateInteraction(event) else { return }
            interactionGeneration = nil
            drop(
                at: event.point, releasedAt: event.timestamp, frame: event.sourceFrame,
                movementProven: event.movementProven, generation: event.generation,
                screens: screens, bridge: bridge)
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            tapWasDisabled()
        default:
            break
        }
    }

    private func validateInteraction(_ event: TapEvent) -> Bool {
        guard interactionGeneration == event.generation else {
            interaction.reset()
            interactionGeneration = nil
            preview?.hide()
            return false
        }
        return true
    }

    private func drag(
        to point: CGPoint, at now: Date, frame: CGRect?,
        screens: [WindowPlacementEngine.Screen], geometry: AXGeometry
    ) {
        let target = interaction.mouseDragged(
            to: point, at: now, screens: screens,
            frameOf: { _ in frame })
        show(target, screens: screens, geometry: geometry)
    }

    private func drop(
        at point: CGPoint, releasedAt timestamp: UInt64, frame: CGRect?,
        movementProven: Bool, generation: UInt64,
        screens: [WindowPlacementEngine.Screen], bridge: TapBridge
    ) {
        preview?.hide()
        guard
            let drop = interaction.mouseUp(
                at: point, screens: screens, movementWasProven: movementProven,
                frameOf: { _ in frame })
        else { return }
        let gap = CGFloat(settings.windowGap)
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now >= timestamp ? now - timestamp : 0
        let remaining = elapsed < 50_000_000 ? 50_000_000 - elapsed : 0
        dropTask?.cancel()
        dropTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .nanoseconds(Int64(remaining)))
            } catch {
                return
            }
            guard !Task.isCancelled, let self,
                !bridge.hasNewerPress(than: generation)
            else { return }
            mover.perform(
                drop.target.command, window: drop.window, sourceFrame: drop.sourceFrame,
                destinationScreenID: drop.target.screenID, gap: gap)
            dropTask = nil
        }
    }

    private func capturedWindow(_ event: TapEvent) async -> WindowMover.CapturedWindow? {
        if event.ownerPID == ProcessInfo.processInfo.processIdentifier {
            guard let own = NSApp.windows.first(where: { $0.windowNumber == event.windowNumber }),
                WindowTarget.placeable(own) === own,
                !own.styleMask.contains(.fullScreen), own.styleMask.contains(.resizable)
            else { return nil }
            return .own(own)
        }
        guard let ownerPID = event.ownerPID,
            let hit = await AXWindowAccess.window(
                at: event.point, in: ownerPID, matching: CGWindowID(event.windowNumber))
        else { return nil }
        return .external(hit)
    }

    private func show(
        _ target: WindowSnapInteraction<WindowMover.CapturedWindow>.Target?,
        screens: [WindowPlacementEngine.Screen], geometry: AXGeometry
    ) {
        guard let target, let screen = screens.first(where: { $0.id == target.screenID }),
            let placement = WindowPlacementEngine.placement(
                for: WindowPlacementEngine.Input(
                    command: target.command,
                    windowFrame: CGRect(
                        x: screen.frame.midX, y: screen.frame.midY, width: 1, height: 1),
                    screens: screens, gap: CGFloat(settings.windowGap),
                    destinationScreenID: target.screenID))
        else {
            preview?.hide()
            return
        }
        let preview = preview ?? WindowSnapPreviewController()
        self.preview = preview
        preview.show(frame: geometry.flip(placement.frame))
    }
}

private func windowSnapEventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let bridge = Unmanaged<WindowSnapManager.TapBridge>.fromOpaque(userInfo).takeUnretainedValue()
    let point = event.location
    let timestamp = event.timestamp
    let windowNumber = Int(
        event.getIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent))
    MainActor.assumeIsolated {
        bridge.captureAndYield(
            typeRaw: type.rawValue, point: point, timestamp: timestamp,
            reportedWindowNumber: windowNumber)
    }
    return Unmanaged.passUnretained(event)
}
