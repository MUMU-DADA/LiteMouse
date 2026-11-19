import Foundation

public enum ScrollMode: String, Codable, Equatable, Sendable {
    case linear
    case smooth
    case disabled
}

public enum BackForwardMode: String, Codable, Equatable, Sendable {
    case auto
    case swipe
    case cmdBracket
    case disabled
}

public enum BackForwardFallback: String, Codable, Equatable, Sendable {
    case passthrough
    case cmdBracket
    case swipe
}

public struct ScrollConfig: Codable, Equatable, Sendable {
    public var mode: ScrollMode
    public var verticalLines: Int
    public var horizontalLines: Int
    public var reverseVertical: Bool
    public var reverseHorizontal: Bool
    public var smoothPixelsPerLine: Double
    public var smoothDurationMs: Double

    public static let `default` = ScrollConfig(
        mode: .linear,
        verticalLines: 4,
        horizontalLines: 3,
        reverseVertical: false,
        reverseHorizontal: false,
        smoothPixelsPerLine: 18.0,
        smoothDurationMs: 130.0
    )

    public init(
        mode: ScrollMode = .linear,
        verticalLines: Int = 4,
        horizontalLines: Int = 3,
        reverseVertical: Bool = false,
        reverseHorizontal: Bool = false,
        smoothPixelsPerLine: Double = 18.0,
        smoothDurationMs: Double = 130.0
    ) {
        self.mode = mode
        self.verticalLines = max(1, min(30, verticalLines))
        self.horizontalLines = max(1, min(30, horizontalLines))
        self.reverseVertical = reverseVertical
        self.reverseHorizontal = reverseHorizontal
        self.smoothPixelsPerLine = max(4.0, min(120.0, smoothPixelsPerLine))
        self.smoothDurationMs = max(30.0, min(500.0, smoothDurationMs))
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ScrollConfig.default
        self.init(
            mode: try c.decodeIfPresent(ScrollMode.self, forKey: .mode) ?? d.mode,
            verticalLines: try c.decodeIfPresent(Int.self, forKey: .verticalLines) ?? d.verticalLines,
            horizontalLines: try c.decodeIfPresent(Int.self, forKey: .horizontalLines) ?? d.horizontalLines,
            reverseVertical: try c.decodeIfPresent(Bool.self, forKey: .reverseVertical) ?? d.reverseVertical,
            reverseHorizontal: try c.decodeIfPresent(Bool.self, forKey: .reverseHorizontal) ?? d.reverseHorizontal,
            smoothPixelsPerLine: try c.decodeIfPresent(Double.self, forKey: .smoothPixelsPerLine) ?? d.smoothPixelsPerLine,
            smoothDurationMs: try c.decodeIfPresent(Double.self, forKey: .smoothDurationMs) ?? d.smoothDurationMs
        )
    }
}

public struct BackForwardConfig: Codable, Equatable, Sendable {
    public var mode: BackForwardMode
    public var backButtonNumber: Int
    public var forwardButtonNumber: Int
    public var swipeBundleIds: [String]
    public var cmdBracketBundleIds: [String]
    public var fallback: BackForwardFallback

    public static let defaultSwipeBundleIds: [String] = [
        "com.apple.*",
        "org.mozilla.firefox*",
        "com.binarynights.ForkLift*",
        "com.operasoftware.Opera",
    ]

    public static let defaultCmdBracketBundleIds: [String] = [
        "md.obsidian",
        "notion.id",
        "com.tinyspeck.slackmacgap",
        "com.spotify.client",
    ]

    public static let `default` = BackForwardConfig(
        mode: .auto,
        backButtonNumber: 3,
        forwardButtonNumber: 4,
        swipeBundleIds: defaultSwipeBundleIds,
        cmdBracketBundleIds: defaultCmdBracketBundleIds,
        fallback: .passthrough
    )

    public init(
        mode: BackForwardMode = .auto,
        backButtonNumber: Int = 3,
        forwardButtonNumber: Int = 4,
        swipeBundleIds: [String] = defaultSwipeBundleIds,
        cmdBracketBundleIds: [String] = defaultCmdBracketBundleIds,
        fallback: BackForwardFallback = .passthrough
    ) {
        self.mode = mode
        self.backButtonNumber = backButtonNumber
        self.forwardButtonNumber = forwardButtonNumber
        self.swipeBundleIds = swipeBundleIds
        self.cmdBracketBundleIds = cmdBracketBundleIds
        self.fallback = fallback
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BackForwardConfig.default
        self.init(
            mode: try c.decodeIfPresent(BackForwardMode.self, forKey: .mode) ?? d.mode,
            backButtonNumber: try c.decodeIfPresent(Int.self, forKey: .backButtonNumber) ?? d.backButtonNumber,
            forwardButtonNumber: try c.decodeIfPresent(Int.self, forKey: .forwardButtonNumber) ?? d.forwardButtonNumber,
            swipeBundleIds: try c.decodeIfPresent([String].self, forKey: .swipeBundleIds) ?? d.swipeBundleIds,
            cmdBracketBundleIds: try c.decodeIfPresent([String].self, forKey: .cmdBracketBundleIds) ?? d.cmdBracketBundleIds,
            fallback: try c.decodeIfPresent(BackForwardFallback.self, forKey: .fallback) ?? d.fallback
        )
    }
}

public struct LiteMouseConfig: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var scroll: ScrollConfig
    public var backForward: BackForwardConfig

    public static let `default` = LiteMouseConfig(
        enabled: true,
        scroll: .default,
        backForward: .default
    )

    public init(
        enabled: Bool = true,
        scroll: ScrollConfig = .default,
        backForward: BackForwardConfig = .default
    ) {
        self.enabled = enabled
        self.scroll = scroll
        self.backForward = backForward
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LiteMouseConfig.default
        self.init(
            enabled: try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled,
            scroll: try c.decodeIfPresent(ScrollConfig.self, forKey: .scroll) ?? d.scroll,
            backForward: try c.decodeIfPresent(BackForwardConfig.self, forKey: .backForward) ?? d.backForward
        )
    }
}

public enum ConfigStore {
    public static var defaultDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("litemouse", isDirectory: true)
    }

    public static var defaultFileURL: URL {
        defaultDirectoryURL.appendingPathComponent("config.json", isDirectory: false)
    }

    public static func loadOrCreate(at url: URL = defaultFileURL) -> LiteMouseConfig {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode(LiteMouseConfig.self, from: data) {
                return decoded
            }
            return .default
        }
        let config = LiteMouseConfig.default
        try? save(config, to: url)
        return config
    }

    public static func save(_ config: LiteMouseConfig, to url: URL = defaultFileURL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(config)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }
}
