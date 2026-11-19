import Foundation
import Testing
@testable import LiteMouseCore

@Suite("LiteMouseCore Tests")
struct LiteMouseCoreTests {
    @Test("Default config matches expected baseline")
    func defaultConfig() {
        let cfg = LiteMouseConfig.default
        #expect(cfg.enabled == true)
        #expect(cfg.scroll.mode == .linear)
        #expect(cfg.scroll.verticalLines == 4)
        #expect(cfg.scroll.reverseVertical == false)
        #expect(cfg.backForward.mode == .auto)
        #expect(cfg.backForward.backButtonNumber == 3)
        #expect(cfg.backForward.forwardButtonNumber == 4)
    }

    @Test("Partial JSON decodes with sensible defaults")
    func partialJSONDecode() throws {
        let json = """
        {
          "scroll": {
            "mode": "smooth",
            "verticalLines": 5
          }
        }
        """
        let decoded = try JSONDecoder().decode(LiteMouseConfig.self, from: Data(json.utf8))
        #expect(decoded.enabled == true)
        #expect(decoded.scroll.mode == .smooth)
        #expect(decoded.scroll.verticalLines == 5)
        #expect(decoded.scroll.reverseVertical == false)
        #expect(decoded.backForward.mode == .auto)
    }

    @Test("Linear scroll strips macOS acceleration and respects reverse flag")
    func linearScrollCalculation() {
        var cfg = ScrollConfig.default
        cfg.verticalLines = 4
        cfg.reverseVertical = false

        let up = ScrollCalculator.computeLinearStep(rawVertical: 1, rawHorizontal: 0, config: cfg)
        #expect(up == LinearScrollOutput(verticalLines: 4, horizontalLines: 0))

        // Fast spin accelerated by macOS HID (rawVertical = -7) still yields exact -4 lines
        let fastDown = ScrollCalculator.computeLinearStep(rawVertical: -7, rawHorizontal: 0, config: cfg)
        #expect(fastDown == LinearScrollOutput(verticalLines: -4, horizontalLines: 0))

        cfg.reverseVertical = true
        let rev = ScrollCalculator.computeLinearStep(rawVertical: 3, rawHorizontal: 0, config: cfg)
        #expect(rev == LinearScrollOutput(verticalLines: -4, horizontalLines: 0))

        cfg.mode = .disabled
        #expect(ScrollCalculator.computeLinearStep(rawVertical: 1, rawHorizontal: 0, config: cfg) == nil)
    }

    @Test("Smooth scroll integrator conserves total distance at 240Hz")
    func smoothScrollConservation() {
        var integrator = SmoothScrollIntegrator()
        integrator.addImpulse(dx: 0, dy: -72.0)

        var totalY: Int32 = 0
        var frames = 0
        var hitFinal = false
        let dt = 1.0 / 240.0

        while integrator.isActive && frames < 300 {
            if let f = integrator.step(dtSeconds: dt, durationMs: 130.0) {
                totalY += f.dy
                if f.isFinal { hitFinal = true }
            }
            frames += 1
        }

        #expect(hitFinal)
        #expect(totalY == -72)
        #expect(!integrator.isActive)
    }

    @Test("Smooth scroll cancels opposite tail on direction reversal")
    func smoothScrollReversal() {
        var integrator = SmoothScrollIntegrator()
        integrator.addImpulse(dx: 0, dy: 100.0)
        _ = integrator.step(dtSeconds: 1.0 / 240.0, durationMs: 130.0)
        #expect(integrator.remainingY > 0)

        integrator.addImpulse(dx: 0, dy: -50.0)
        #expect(integrator.remainingY == -50.0)
    }

    @Test("Back/Forward routing handles swipe, cmdBracket, and passthrough")
    func backForwardRouting() {
        let cfg = BackForwardConfig.default

        #expect(BackForwardRouter.resolveAction(buttonNumber: 3, frontmostBundleId: "com.apple.finder", config: cfg) == .navigationSwipe(.back))
        #expect(BackForwardRouter.resolveAction(buttonNumber: 4, frontmostBundleId: "org.mozilla.firefox", config: cfg) == .navigationSwipe(.forward))
        #expect(BackForwardRouter.resolveAction(buttonNumber: 3, frontmostBundleId: "md.obsidian", config: cfg) == .cmdBracket(.back))
        #expect(BackForwardRouter.resolveAction(buttonNumber: 4, frontmostBundleId: "com.microsoft.VSCode", config: cfg) == .passthrough)
        #expect(BackForwardRouter.resolveAction(buttonNumber: 2, frontmostBundleId: "com.apple.finder", config: cfg) == .passthrough)
    }
}
