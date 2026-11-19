import Foundation

public struct LinearScrollOutput: Equatable, Sendable {
    public let verticalLines: Int
    public let horizontalLines: Int

    public init(verticalLines: Int, horizontalLines: Int) {
        self.verticalLines = verticalLines
        self.horizontalLines = horizontalLines
    }
}

public enum ScrollCalculator {
    /// Computes pure unaccelerated linear scroll lines per discrete wheel detent.
    /// Uses signum only so macOS's pre-tap HID scroll acceleration is completely removed.
    public static func computeLinearStep(
        rawVertical: Double,
        rawHorizontal: Double,
        config: ScrollConfig
    ) -> LinearScrollOutput? {
        guard config.mode == .linear else { return nil }
        guard rawVertical != 0 || rawHorizontal != 0 else { return nil }

        let vSign: Int
        if rawVertical > 0 {
            vSign = config.reverseVertical ? -1 : 1
        } else if rawVertical < 0 {
            vSign = config.reverseVertical ? 1 : -1
        } else {
            vSign = 0
        }

        let hSign: Int
        if rawHorizontal > 0 {
            hSign = config.reverseHorizontal ? -1 : 1
        } else if rawHorizontal < 0 {
            hSign = config.reverseHorizontal ? 1 : -1
        } else {
            hSign = 0
        }

        let vLines = vSign * config.verticalLines
        let hLines = hSign * config.horizontalLines
        return LinearScrollOutput(verticalLines: vLines, horizontalLines: hLines)
    }

    public static func computeSmoothImpulsePixels(
        rawVertical: Double,
        rawHorizontal: Double,
        config: ScrollConfig
    ) -> (dx: Double, dy: Double)? {
        guard config.mode == .smooth else { return nil }
        guard rawVertical != 0 || rawHorizontal != 0 else { return nil }

        let vSign: Double = rawVertical == 0 ? 0 : ((rawVertical > 0 ? 1.0 : -1.0) * (config.reverseVertical ? -1.0 : 1.0))
        let hSign: Double = rawHorizontal == 0 ? 0 : ((rawHorizontal > 0 ? 1.0 : -1.0) * (config.reverseHorizontal ? -1.0 : 1.0))

        let dy = vSign * Double(config.verticalLines) * config.smoothPixelsPerLine
        let dx = hSign * Double(config.horizontalLines) * config.smoothPixelsPerLine
        return (dx, dy)
    }
}

public struct SmoothScrollFrame: Equatable, Sendable {
    public let dx: Int32
    public let dy: Int32
    public let isFinal: Bool

    public init(dx: Int32, dy: Int32, isFinal: Bool) {
        self.dx = dx
        self.dy = dy
        self.isFinal = isFinal
    }
}

/// Pure, allocation-free exponential decay integrator with sub-pixel remainder accumulation.
/// Conserves total pixel travel accurately across arbitrary refresh rates (60Hz / 120Hz / 240Hz).
public struct SmoothScrollIntegrator: Sendable {
    public private(set) var remainingX: Double = 0
    public private(set) var remainingY: Double = 0
    private var fracX: Double = 0
    private var fracY: Double = 0

    public var isActive: Bool {
        abs(remainingX) > 0.05 || abs(remainingY) > 0.05 || abs(fracX) >= 0.5 || abs(fracY) >= 0.5
    }

    public init() {}

    public mutating func addImpulse(dx: Double, dy: Double) {
        // Immediate direction reversal feels crisp: cancel opposite-direction tail.
        if dx != 0 && remainingX != 0 && ((dx > 0) != (remainingX > 0)) {
            remainingX = 0
            fracX = 0
        }
        if dy != 0 && remainingY != 0 && ((dy > 0) != (remainingY > 0)) {
            remainingY = 0
            fracY = 0
        }
        remainingX += dx
        remainingY += dy
    }

    public mutating func reset() {
        remainingX = 0
        remainingY = 0
        fracX = 0
        fracY = 0
    }

    public mutating func step(dtSeconds: Double, durationMs: Double) -> SmoothScrollFrame? {
        guard isActive else { return nil }

        let dt = max(0.0005, min(0.05, dtSeconds))
        // Time constant tau chosen so ~95% of travel completes in durationMs (3 * tau = duration)
        let tau = max(0.01, (durationMs / 1000.0) / 3.0)
        let factor = 1.0 - exp(-dt / tau)

        var stepX = remainingX * factor
        var stepY = remainingY * factor

        if abs(remainingX) < 0.35 {
            stepX = remainingX
            remainingX = 0
        } else {
            remainingX -= stepX
        }

        if abs(remainingY) < 0.35 {
            stepY = remainingY
            remainingY = 0
        } else {
            remainingY -= stepY
        }

        fracX += stepX
        fracY += stepY

        let outX = Int32(fracX.rounded(.towardZero))
        let outY = Int32(fracY.rounded(.towardZero))
        fracX -= Double(outX)
        fracY -= Double(outY)

        let finished = abs(remainingX) <= 0.05 && abs(remainingY) <= 0.05
        if finished {
            let finalX = outX + Int32(fracX.rounded())
            let finalY = outY + Int32(fracY.rounded())
            remainingX = 0
            remainingY = 0
            fracX = 0
            fracY = 0
            return SmoothScrollFrame(dx: finalX, dy: finalY, isFinal: true)
        }

        if outX == 0 && outY == 0 {
            return nil
        }

        return SmoothScrollFrame(dx: outX, dy: outY, isFinal: false)
    }
}
