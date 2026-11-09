import AppKit

@MainActor
final class WindowSnapManager {
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
            type: CGEventType, event: CGEvent, windowNumber: Int,
            generation: UInt64, snapshot: WindowServerHit?, movementProven: Bool
        ) -> Self {
            return Self(
                typeRaw: type.rawValue, point: event.location, timestamp: event.timestamp,
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

    /// Sampling state is callback-confined; press generations are locked for delayed commits.
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
        private let pressLock = NSLock()
        private var latestPressGeneration: [Int: UInt64] = [:]

        nonisolated init() {
            let pair = AsyncStream<TapEvent>.makeStream(
                bufferingPolicy: .bufferingNewest(256))
            stream = pair.stream
            continuation = pair.continuation
        }

        nonisolated func captureAndYield(type: CGEventType, event: CGEvent) {
            if type == .leftMouseDown {
                generation &+= 1
                let reportedNumber = Int(
                    event.getIntegerValueField(
                        .mouseEventWindowUnderMousePointerThatCanHandleThisEvent))
                lastSnapshot = TapEvent.windowSnapshot(
                    reportedNumber: reportedNumber, at: event.location)
                windowNumber = lastSnapshot?.windowNumber ?? 0
                pressLock.lock()
                latestPressGeneration[windowNumber] = generation
                pressLock.unlock()
                sampledDrag = false
                lastSnapshotTimestamp = event.timestamp
                gestureSource = lastSnapshot?.frame
                movementProven = false
                resizeProven = false
            }

            let shouldSample =
                type == .leftMouseDown || type == .leftMouseUp
                || (type == .leftMouseDragged
                    && (!sampledDrag || (!movementProven && !resizeProven)
                        || event.timestamp < lastSnapshotTimestamp
                        || event.timestamp - lastSnapshotTimestamp >= 50_000_000))
            if shouldSample, windowNumber > 0, type != .leftMouseDown {
                lastSnapshot = TapEvent.windowSnapshot(
                    reportedNumber: windowNumber, at: event.location)
                lastSnapshotTimestamp = event.timestamp
                if type == .leftMouseDragged {
                    sampledDrag = true
                    classifyMovement(lastSnapshot?.frame)
                }
            }
            continuation.yield(
                .capture(
                    type: type, event: event, windowNumber: windowNumber,
                    generation: generation, snapshot: lastSnapshot,
                    movementProven: movementProven))
            if type == .leftMouseUp { windowNumber = 0 }
        }

        private nonisolated func classifyMovement(_ frame: CGRect?) {
            guard let source = gestureSource, let frame else { return }
            if frame.size != source.size {
                resizeProven = true
            } else if hypot(frame.minX - source.minX, frame.minY - source.minY) > 2 {
                movementProven = true
            }
        }

        nonisolated func finish() { continuation.finish() }

        nonisolated func hasNewerPress(windowNumber: Int, than generation: UInt64) -> Bool {
            pressLock.lock()
            let latest = latestPressGeneration[windowNumber]
            pressLock.unlock()
            return latest.map { $0 != generation } ?? false
        }
    }

    /// Tap state stays on its thread; the lock guards every cross-thread handle used by stop().
    private final class TapRunner: @unchecked Sendable {
        private let bridge: TapBridge
        private let lock = NSLock()
        private var thread: Thread?
        private var runLoop: CFRunLoop?
        private var port: CFMachPort?
        private var stopped = false

        init(bridge: TapBridge) {
            self.bridge = bridge
        }

        func start() {
            let thread = Thread { [weak self] in self?.run() }
            thread.name = "Tinycast window snap events"
            self.thread = thread
            thread.start()
        }

        func stop() {
            lock.lock()
            stopped = true
            let runLoop = runLoop
            let port = port
            lock.unlock()
            if let port { CFMachPortInvalidate(port) }
            if let runLoop {
                CFRunLoopStop(runLoop)
                CFRunLoopWakeUp(runLoop)
            }
        }

        private func run() {
            let mask: CGEventMask =
                (1 << CGEventType.leftMouseDown.rawValue)
                | (1 << CGEventType.leftMouseDragged.rawValue)
                | (1 << CGEventType.leftMouseUp.rawValue)
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .tailAppendEventTap, options: .listenOnly,
                eventsOfInterest: mask, callback: windowSnapEventTapCallback,
                userInfo: Unmanaged.passUnretained(bridge).toOpaque())
            let source = port.flatMap {
                CFMachPortCreateRunLoopSource(kCFAllocatorDefault, $0, 0)
            }
            let runLoop = CFRunLoopGetCurrent()

            lock.lock()
            let stopped = stopped
            if !stopped, source != nil {
                self.port = port
                self.runLoop = runLoop
            }
            lock.unlock()

            guard !stopped, let port, let source else {
                if let port { CFMachPortInvalidate(port) }
                bridge.finish()
                return
            }
            CFRunLoopAddSource(runLoop, source, .commonModes)
            CGEvent.tapEnable(tap: port, enable: true)
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFMachPortInvalidate(port)
            bridge.finish()
        }
    }

    private let settings: AppSettings
    private let mover: WindowMover
    private var preview: WindowSnapPreviewController?
    private var interaction = WindowSnapInteraction<WindowMover.CapturedWindow>()
    private var interactionGeneration: UInt64?
    private var tapRunner: TapRunner?
    private var tapBridge: TapBridge?
    private var tapTask: Task<Void, Never>?
    private var activationToken: NotificationToken?
    private var dropTask: Task<Void, Never>?
    private var monitorLifecycle = WindowSnapMonitorLifecycle()

    init(settings: AppSettings, mover: WindowMover) {
        self.settings = settings
        self.mover = mover
    }

    func applyEnabled() {
        guard settings.windowManagementEnabled, settings.windowSnapEnabled else {
            activationToken = nil
            setMonitoringEnabled(false)
            return
        }
        observeActivation()
        setMonitoringEnabled(Permissions.ensureAccessibility())
    }

    func stop() {
        activationToken = nil
        setMonitoringEnabled(false)
    }

    private func observeActivation() {
        guard activationToken == nil else { return }
        let token = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPermission() }
        }
        activationToken = NotificationToken(token, center: .default)
    }

    private func refreshPermission() {
        guard settings.windowManagementEnabled, settings.windowSnapEnabled else {
            stop()
            return
        }
        setMonitoringEnabled(Permissions.isAccessibilityTrusted())
    }

    private func setMonitoringEnabled(_ enabled: Bool) {
        guard let action = monitorLifecycle.setEnabled(enabled) else { return }
        perform(action)
    }

    private func perform(_ action: WindowSnapMonitorLifecycle.Action) {
        switch action {
        case .start: startMonitoring()
        case .stop: stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard tapRunner == nil else { return }
        let bridge = TapBridge()
        let runner = TapRunner(bridge: bridge)
        tapRunner = runner
        tapBridge = bridge
        runner.start()
        tapTask = Task { @MainActor [weak self, stream = bridge.stream] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                await self?.handle(event, bridge: bridge)
            }
            self?.monitorDidEnd(bridge: bridge)
        }
    }

    private func stopMonitoring() {
        dropTask?.cancel()
        dropTask = nil
        tapRunner?.stop()
        interaction.reset()
        interactionGeneration = nil
        preview?.hide()
    }

    private func monitorDidEnd(bridge: TapBridge) {
        guard tapBridge === bridge else { return }
        tapRunner = nil
        tapBridge = nil
        tapTask = nil
        dropTask?.cancel()
        dropTask = nil
        interaction.reset()
        interactionGeneration = nil
        preview?.hide()
        if monitorLifecycle.didEnd() == .start { startMonitoring() }
    }

    private func tapWasDisabled() {
        guard let action = monitorLifecycle.restart() else { return }
        perform(action)
    }

    private func handle(_ event: TapEvent, bridge: TapBridge) async {
        guard !Task.isCancelled, tapBridge === bridge, monitorLifecycle.acceptsEvents else { return }
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
                movementProven: event.movementProven, windowNumber: event.windowNumber,
                generation: event.generation, screens: screens, bridge: bridge)
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
        movementProven: Bool, windowNumber: Int, generation: UInt64,
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
                !bridge.hasNewerPress(windowNumber: windowNumber, than: generation)
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
    bridge.captureAndYield(type: type, event: event)
    return Unmanaged.passUnretained(event)
}
