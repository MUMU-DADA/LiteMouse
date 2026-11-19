import Foundation

public enum NavigationDirection: Equatable, Sendable {
    case back
    case forward
}

public enum BackForwardAction: Equatable, Sendable {
    case passthrough
    case navigationSwipe(NavigationDirection)
    case cmdBracket(NavigationDirection)
}

public enum BackForwardRouter {
    public static func matchPattern(_ pattern: String, bundleIdentifier: String) -> Bool {
        if pattern.hasSuffix("*") {
            let prefix = pattern.dropLast()
            return bundleIdentifier.hasPrefix(prefix)
        }
        return bundleIdentifier == pattern
    }

    public static func direction(forButton buttonNumber: Int, config: BackForwardConfig) -> NavigationDirection? {
        if buttonNumber == config.backButtonNumber {
            return .back
        }
        if buttonNumber == config.forwardButtonNumber {
            return .forward
        }
        return nil
    }

    public static func resolveAction(
        buttonNumber: Int,
        frontmostBundleId: String?,
        config: BackForwardConfig
    ) -> BackForwardAction {
        guard config.mode != .disabled,
              let dir = direction(forButton: buttonNumber, config: config) else {
            return .passthrough
        }

        switch config.mode {
        case .disabled:
            return .passthrough
        case .swipe:
            return .navigationSwipe(dir)
        case .cmdBracket:
            return .cmdBracket(dir)
        case .auto:
            if let bid = frontmostBundleId {
                if config.swipeBundleIds.contains(where: { matchPattern($0, bundleIdentifier: bid) }) {
                    return .navigationSwipe(dir)
                }
                if config.cmdBracketBundleIds.contains(where: { matchPattern($0, bundleIdentifier: bid) }) {
                    return .cmdBracket(dir)
                }
            }
            switch config.fallback {
            case .passthrough:
                return .passthrough
            case .cmdBracket:
                return .cmdBracket(dir)
            case .swipe:
                return .navigationSwipe(dir)
            }
        }
    }
}
