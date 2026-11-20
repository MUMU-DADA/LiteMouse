import Foundation

enum LaunchAgentManager {
    static let label = "local.litemouse.app"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        let fm = FileManager.default
        if !enabled {
            if fm.fileExists(atPath: plistURL.path) {
                try fm.removeItem(at: plistURL)
            }
            return
        }

        let dir = plistURL.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let executablePath = preferredExecutablePath()
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL, options: .atomic)
    }

    private static func preferredExecutablePath() -> String {
        let installed = "/Applications/LiteMouse.app/Contents/MacOS/LiteMouse"
        if FileManager.default.isExecutableFile(atPath: installed) {
            return installed
        }
        return Bundle.main.executablePath ?? installed
    }
}
