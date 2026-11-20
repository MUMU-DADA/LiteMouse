import CoreGraphics
import Foundation
import LiteMouseCore

final class SmoothScrollAnimator {
    private let queue = DispatchQueue(label: "local.litemouse.smoothscroll", qos: .userInteractive)
    private var integrator = SmoothScrollIntegrator()
    private var timer: DispatchSourceTimer?
    private var lastTickNs: UInt64 = 0
    private var durationMs: Double = 130.0
    private var currentFlags: CGEventFlags = []
    private(set) var cachedRefreshHz: Double = 120.0

    func enqueue(dx: Double, dy: Double, durationMs: Double, flags: CGEventFlags) {
        queue.async { [weak self] in
            guard let self else { return }
            self.durationMs = durationMs
            self.currentFlags = flags
            self.integrator.addImpulse(dx: dx, dy: dy)
            if self.timer == nil {
                self.startTimerLocked()
            }
        }
    }

    func cancel() {
        queue.async { [weak self] in
            guard let self else { return }
            self.stopTimerLocked()
            self.integrator.reset()
        }
    }

    static func currentMainDisplayRefreshHz() -> Double {
        let display = CGMainDisplayID()
        if let mode = CGDisplayCopyDisplayMode(display) {
            let rate = mode.refreshRate
            if rate >= 30.0 && rate <= 480.0 {
                return rate
            }
        }
        return 120.0
    }

    private func startTimerLocked() {
        let hz = Self.currentMainDisplayRefreshHz()
        cachedRefreshHz = hz
        let intervalNs = UInt64((1_000_000_000.0 / hz).rounded())
        lastTickNs = DispatchTime.now().uptimeNanoseconds

        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(
            deadline: .now(),
            repeating: .nanoseconds(Int(intervalNs)),
            leeway: .microseconds(250)
        )
        t.setEventHandler { [weak self] in
            self?.tickLocked()
        }
        timer = t
        t.resume()
    }

    private func tickLocked() {
        let now = DispatchTime.now().uptimeNanoseconds
        let dt = Double(now &- lastTickNs) / 1_000_000_000.0
        lastTickNs = now

        let effectiveDt = dt > 0.0001 ? dt : (1.0 / cachedRefreshHz)
        guard let frame = integrator.step(dtSeconds: effectiveDt, durationMs: durationMs) else {
            if !integrator.isActive {
                stopTimerLocked()
            }
            return
        }

        if frame.dx != 0 || frame.dy != 0 {
            EventSynthesizer.postSmoothScroll(
                dx: frame.dx,
                dy: frame.dy,
                modifierFlags: currentFlags
            )
        }

        if frame.isFinal {
            stopTimerLocked()
        }
    }

    private func stopTimerLocked() {
        timer?.cancel()
        timer = nil
    }
}
