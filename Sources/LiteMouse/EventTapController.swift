import AppKit
import CoreGraphics
import Foundation
import LiteMouseCore
import os

final class EventTapController {
    private struct Snapshot {
        var config: LiteMouseConfig
        var frontmostBundleId: String?
        var pidBundleCache: [pid_t: String] = [:]
    }

    private var lock = os_unfair_lock_s()
    private var snapshot: Snapshot

    private let animator = SmoothScrollAnimator()
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var swallowedButtons: Set<Int> = []
    private var active = false

    private static let fieldAcceleratedDeltaAxis1 = CGEventField(rawValue: 176)!
    private static let fieldAcceleratedDeltaAxis2 = CGEventField(rawValue: 175)!
    private static let fieldRawDeltaAxis1 = CGEventField(rawValue: 178)!
    private static let fieldRawDeltaAxis2 = CGEventField(rawValue: 177)!

    var onStatusChanged: ((Bool) -> Void)?

    var isTapActive: Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return active
    }

    init(config: LiteMouseConfig) {
        let initialApp = NSWorkspace.shared.frontmostApplication
        var snap = Snapshot(config: config, frontmostBundleId: initialApp?.bundleIdentifier)
        if let app = initialApp, let bid = app.bundleIdentifier {
            snap.pidBundleCache[app.processIdentifier] = bid
        }
        self.snapshot = snap
    }

    func updateFrontmostApp(_ app: NSRunningApplication?) {
        os_unfair_lock_lock(&lock)
        snapshot.frontmostBundleId = app?.bundleIdentifier
        if let app, let bid = app.bundleIdentifier {
            if snapshot.pidBundleCache.count > 64 {
                snapshot.pidBundleCache.removeAll(keepingCapacity: true)
            }
            snapshot.pidBundleCache[app.processIdentifier] = bid
        }
        os_unfair_lock_unlock(&lock)
    }

    func removeTerminatedPid(_ pid: pid_t) {
        os_unfair_lock_lock(&lock)
        snapshot.pidBundleCache.removeValue(forKey: pid)
        os_unfair_lock_unlock(&lock)
    }

    func updateConfig(_ config: LiteMouseConfig) {
        let needsTap = config.enabled && (config.scroll.mode != .disabled || config.backForward.mode != .disabled)
        os_unfair_lock_lock(&lock)
        let wasSmooth = snapshot.config.scroll.mode == .smooth
        snapshot.config = config
        os_unfair_lock_unlock(&lock)

        if wasSmooth && (!needsTap || config.scroll.mode != .smooth) {
            animator.cancel()
        }

        if needsTap {
            startIfNeeded()
        } else {
            stop()
        }
    }

    func startIfNeeded() {
        if tapThread != nil {
            return
        }
        guard AXIsProcessTrusted() else {
            setActive(false)
            return
        }

        let startedSemaphore = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            guard let self else {
                startedSemaphore.signal()
                return
            }
            self.runTapLoop(readySemaphore: startedSemaphore)
        }
        thread.name = "LiteMouseEventTap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        _ = startedSemaphore.wait(timeout: .now() + 2.0)
    }

    func stop() {
        animator.cancel()
        os_unfair_lock_lock(&lock)
        let rl = tapRunLoop
        let port = machPort
        let src = runLoopSource
        os_unfair_lock_unlock(&lock)

        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let rl, let src {
            CFRunLoopRemoveSource(rl, src, .commonModes)
        }
        if let rl {
            CFRunLoopStop(rl)
        }

        os_unfair_lock_lock(&lock)
        tapRunLoop = nil
        machPort = nil
        runLoopSource = nil
        tapThread = nil
        active = false
        os_unfair_lock_unlock(&lock)
        onStatusChanged?(false)
    }

    private func setActive(_ value: Bool) {
        os_unfair_lock_lock(&lock)
        active = value
        os_unfair_lock_unlock(&lock)
        DispatchQueue.main.async { [weak self] in
            self?.onStatusChanged?(value)
        }
    }

    private func resolveBundleId(targetPid: pid_t, frontmostBundleId: String?) -> String? {
        guard targetPid > 0 else {
            return frontmostBundleId
        }
        os_unfair_lock_lock(&lock)
        let cached = snapshot.pidBundleCache[targetPid]
        os_unfair_lock_unlock(&lock)
        if let cached {
            return cached
        }
        if let bid = NSRunningApplication(processIdentifier: targetPid)?.bundleIdentifier {
            os_unfair_lock_lock(&lock)
            if snapshot.pidBundleCache.count > 64 {
                snapshot.pidBundleCache.removeAll(keepingCapacity: true)
            }
            snapshot.pidBundleCache[targetPid] = bid
            os_unfair_lock_unlock(&lock)
            return bid
        }
        return frontmostBundleId
    }

    private func runTapLoop(readySemaphore: DispatchSemaphore) {
        // Strictly narrow event mask: NEVER intercept mouseMoved, left/right clicks, drags, or keyboard.
        let mask: CGEventMask =
            (1 << CGEventType.scrollWheel.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else {
                    return Unmanaged.passUnretained(event)
                }
                let controller = Unmanaged<EventTapController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleEvent(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            os_unfair_lock_lock(&lock)
            tapThread = nil
            os_unfair_lock_unlock(&lock)
            setActive(false)
            readySemaphore.signal()
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        let rl = CFRunLoopGetCurrent()

        os_unfair_lock_lock(&lock)
        machPort = port
        runLoopSource = source
        tapRunLoop = rl
        os_unfair_lock_unlock(&lock)

        CFRunLoopAddSource(rl, source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        setActive(true)
        readySemaphore.signal()

        CFRunLoopRun()

        CGEvent.tapEnable(tap: port, enable: false)
        CFMachPortInvalidate(port)
        CFRunLoopRemoveSource(rl, source, .commonModes)
        swallowedButtons.removeAll()
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            os_unfair_lock_lock(&lock)
            let port = machPort
            os_unfair_lock_unlock(&lock)
            if let port {
                CGEvent.tapEnable(tap: port, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        // Skip our own synthesized events in O(1)
        if event.getIntegerValueField(.eventSourceUserData) == EventSynthesizer.magicUserData {
            return Unmanaged.passUnretained(event)
        }

        os_unfair_lock_lock(&lock)
        let cfg = snapshot.config
        let frontmost = snapshot.frontmostBundleId
        os_unfair_lock_unlock(&lock)

        guard cfg.enabled else {
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .scrollWheel:
            return handleScrollWheel(event: event, config: cfg.scroll)
        case .otherMouseDown, .otherMouseUp:
            let targetPid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
            let bundleId = resolveBundleId(targetPid: targetPid, frontmostBundleId: frontmost)
            return handleOtherMouse(type: type, event: event, config: cfg.backForward, targetBundleId: bundleId)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleScrollWheel(event: CGEvent, config: ScrollConfig) -> Unmanaged<CGEvent>? {
        guard config.mode != .disabled else {
            return Unmanaged.passUnretained(event)
        }

        // Only intercept discrete physical mouse wheel ticks; leave trackpad/Magic Mouse continuous events untouched.
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            return Unmanaged.passUnretained(event)
        }

        // Drop residual synthetic momentum events emitted by macOS for discrete wheels.
        if event.getIntegerValueField(.scrollWheelEventMomentumPhase) != 0 {
            return nil
        }

        var rawV = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1))
        var rawH = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2))
        if rawV == 0 {
            rawV = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        }
        if rawH == 0 {
            rawH = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)
        }
        guard rawV != 0 || rawH != 0 else {
            return Unmanaged.passUnretained(event)
        }

        switch config.mode {
        case .disabled:
            return Unmanaged.passUnretained(event)
        case .linear:
            guard let step = ScrollCalculator.computeLinearStep(
                rawVertical: rawV,
                rawHorizontal: rawH,
                config: config
            ) else {
                return Unmanaged.passUnretained(event)
            }
            // Setting isContinuous=0 followed by deltaAxis1/2 keeps fixedPt and pointDelta coherently scaled by macOS.
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 0)
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: Int64(step.verticalLines))
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(step.horizontalLines))
            event.setIntegerValueField(Self.fieldRawDeltaAxis1, value: Int64(step.verticalLines))
            event.setIntegerValueField(Self.fieldRawDeltaAxis2, value: Int64(step.horizontalLines))
            event.setIntegerValueField(Self.fieldAcceleratedDeltaAxis1, value: Int64(step.verticalLines))
            event.setIntegerValueField(Self.fieldAcceleratedDeltaAxis2, value: Int64(step.horizontalLines))
            return Unmanaged.passUnretained(event)

        case .smooth:
            guard let impulse = ScrollCalculator.computeSmoothImpulsePixels(
                rawVertical: rawV,
                rawHorizontal: rawH,
                config: config
            ) else {
                return Unmanaged.passUnretained(event)
            }
            animator.enqueue(
                dx: impulse.dx,
                dy: impulse.dy,
                durationMs: config.smoothDurationMs,
                flags: event.flags
            )
            return nil
        }
    }

    private func handleOtherMouse(
        type: CGEventType,
        event: CGEvent,
        config: BackForwardConfig,
        targetBundleId: String?
    ) -> Unmanaged<CGEvent>? {
        let buttonNumber = Int(event.getIntegerValueField(.mouseEventButtonNumber))

        if type == .otherMouseUp {
            if swallowedButtons.remove(buttonNumber) != nil {
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        let action = BackForwardRouter.resolveAction(
            buttonNumber: buttonNumber,
            frontmostBundleId: targetBundleId,
            config: config
        )

        switch action {
        case .passthrough:
            return Unmanaged.passUnretained(event)
        case .navigationSwipe(let dir):
            swallowedButtons.insert(buttonNumber)
            EventSynthesizer.postNavigationSwipe(dir)
            return nil
        case .cmdBracket(let dir):
            swallowedButtons.insert(buttonNumber)
            EventSynthesizer.postCommandBracket(dir)
            return nil
        }
    }
}
