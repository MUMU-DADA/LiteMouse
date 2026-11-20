import AppKit
import Foundation
import LiteMouseCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var config: LiteMouseConfig = ConfigStore.loadOrCreate()
    private var tapController: EventTapController!
    private var dirWatcher: DispatchSourceFileSystemObject?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?
    private var activateObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        tapController = EventTapController(config: config)
        tapController.onStatusChanged = { [weak self] _ in
            self?.updateStatusIcon()
        }

        setupStatusItem()
        observeWorkspaceApps()
        startConfigWatchers()
        applyConfig()
        startPermissionRetryIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        permissionTimer = nil
        reloadWorkItem?.cancel()
        stopConfigWatchers()
        let nc = NSWorkspace.shared.notificationCenter
        if let activateObserver { nc.removeObserver(activateObserver) }
        if let terminateObserver { nc.removeObserver(terminateObserver) }
        tapController.stop()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateStatusIcon()
    }

    private func updateStatusIcon() {
        guard let button = statusItem?.button else { return }
        let trusted = AXIsProcessTrusted()
        let active = config.enabled && trusted && tapController.isTapActive
        let symbolName: String
        if !trusted {
            symbolName = "exclamationmark.triangle"
        } else if active {
            symbolName = "computermouse.fill"
        } else {
            symbolName = "computermouse"
        }
        let img = NSImage(systemSymbolName: symbolName, accessibilityDescription: "LiteMouse")
        img?.isTemplate = true
        button.image = img
        button.appearsDisabled = !active && trusted
    }

    private func observeWorkspaceApps() {
        let nc = NSWorkspace.shared.notificationCenter
        activateObserver = nc.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.tapController.updateFrontmostApp(app)
        }
        terminateObserver = nc.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                self?.tapController.removeTerminatedPid(app.processIdentifier)
            }
        }
    }

    private func applyConfig() {
        tapController.updateConfig(config)
        updateStatusIcon()
    }

    private func saveAndApply() {
        try? ConfigStore.save(config)
        applyConfig()
    }

    private func startPermissionRetryIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        permissionTimer?.invalidate()
        // Only polls while waiting for initial Accessibility grant; stops immediately once granted.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            if AXIsProcessTrusted() {
                timer.invalidate()
                self.permissionTimer = nil
                self.applyConfig()
            }
        }
    }

    private func startConfigWatchers() {
        stopConfigWatchers()
        let dirURL = ConfigStore.defaultDirectoryURL
        let fileURL = ConfigStore.defaultFileURL
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)

        let dirFD = open(dirURL.path, O_EVTONLY)
        if dirFD >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: dirFD,
                eventMask: [.write, .rename, .delete, .extend],
                queue: .main
            )
            src.setEventHandler { [weak self] in
                self?.scheduleConfigReload(rearmFileWatcher: true)
            }
            src.setCancelHandler {
                close(dirFD)
            }
            dirWatcher = src
            src.resume()
        }

        armFileWatcher(for: fileURL)
    }

    private func armFileWatcher(for fileURL: URL) {
        fileWatcher?.cancel()
        fileWatcher = nil

        let fd = open(fileURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            let flags = src.data
            let replaced = flags.contains(.delete) || flags.contains(.rename)
            self?.scheduleConfigReload(rearmFileWatcher: replaced)
        }
        src.setCancelHandler {
            close(fd)
        }
        fileWatcher = src
        src.resume()
    }

    private func stopConfigWatchers() {
        dirWatcher?.cancel()
        dirWatcher = nil
        fileWatcher?.cancel()
        fileWatcher = nil
    }

    private func scheduleConfigReload(rearmFileWatcher: Bool) {
        reloadWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if rearmFileWatcher {
                self.armFileWatcher(for: ConfigStore.defaultFileURL)
            }
            let loaded = ConfigStore.loadOrCreate()
            if loaded != self.config {
                self.config = loaded
                self.applyConfig()
            }
        }
        reloadWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: item)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let trusted = AXIsProcessTrusted()
        let hz = Int(SmoothScrollAnimator.currentMainDisplayRefreshHz().rounded())

        if !trusted {
            let warn = NSMenuItem(title: "⚠️ 需要「辅助功能」权限（点击前往授权）", action: #selector(requestAccessibility), keyEquivalent: "")
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        } else {
            let modeText: String
            switch config.scroll.mode {
            case .linear: modeText = "线性滚动 (\(config.scroll.verticalLines) 行)"
            case .smooth: modeText = "平滑滚动 (\(hz)Hz)"
            case .disabled: modeText = "滚轮未接管"
            }
            let statusTitle = config.enabled ? "运行中 · \(modeText)" : "已暂停（已释放全部钩子）"
            let statusLine = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
            statusLine.isEnabled = false
            menu.addItem(statusLine)
            menu.addItem(.separator())
        }

        let enableItem = NSMenuItem(title: "启用 LiteMouse", action: #selector(toggleEnabled), keyEquivalent: "")
        enableItem.target = self
        enableItem.state = config.enabled ? .on : .off
        menu.addItem(enableItem)

        menu.addItem(.separator())

        let scrollHeader = NSMenuItem(title: "滚轮模式", action: nil, keyEquivalent: "")
        scrollHeader.isEnabled = false
        menu.addItem(scrollHeader)

        let linearItem = NSMenuItem(title: "线性定步进（固定 \(config.scroll.verticalLines) 行，无加速）", action: #selector(selectLinearScroll), keyEquivalent: "")
        linearItem.target = self
        linearItem.state = config.scroll.mode == .linear ? .on : .off
        menu.addItem(linearItem)

        let smoothItem = NSMenuItem(title: "平滑滚动（\(hz)Hz 帧同步）", action: #selector(selectSmoothScroll), keyEquivalent: "")
        smoothItem.target = self
        smoothItem.state = config.scroll.mode == .smooth ? .on : .off
        menu.addItem(smoothItem)

        let offScrollItem = NSMenuItem(title: "关闭滚轮接管", action: #selector(selectDisabledScroll), keyEquivalent: "")
        offScrollItem.target = self
        offScrollItem.state = config.scroll.mode == .disabled ? .on : .off
        menu.addItem(offScrollItem)

        // Submenu: vertical scroll lines
        let linesParent = NSMenuItem(title: "每格滚动行数（当前 \(config.scroll.verticalLines) 行）", action: nil, keyEquivalent: "")
        let linesMenu = NSMenu()
        for count in [1, 2, 3, 4, 5, 6, 8] {
            let item = NSMenuItem(title: "\(count) 行", action: #selector(selectScrollLines(_:)), keyEquivalent: "")
            item.target = self
            item.tag = count
            item.state = (config.scroll.verticalLines == count) ? .on : .off
            linesMenu.addItem(item)
        }
        linesParent.submenu = linesMenu
        menu.addItem(linesParent)

        let revItem = NSMenuItem(title: "反转鼠标滚轮方向（不影响触控板）", action: #selector(toggleReverseScroll), keyEquivalent: "")
        revItem.target = self
        revItem.state = config.scroll.reverseVertical ? .on : .off
        menu.addItem(revItem)

        menu.addItem(.separator())

        // Submenu: side buttons mode
        let bfLabel: String
        switch config.backForward.mode {
        case .auto: bfLabel = "自动（原生手势优先）"
        case .swipe: bfLabel = "始终发送原生手势"
        case .cmdBracket: bfLabel = "始终发送 ⌘[ / ⌘]"
        case .disabled: bfLabel = "已关闭"
        }
        let bfParent = NSMenuItem(title: "侧键前进 / 后退：\(bfLabel)", action: nil, keyEquivalent: "")
        let bfMenu = NSMenu()
        let bfChoices: [(String, BackForwardMode, Int)] = [
            ("自动推荐（原生手势 + 常见应用 ⌘[/⌘]）", .auto, 0),
            ("始终发送原生导航手势", .swipe, 1),
            ("始终发送 ⌘[ / ⌘]", .cmdBracket, 2),
            ("关闭侧键接管", .disabled, 3),
        ]
        for (title, mode, tag) in bfChoices {
            let item = NSMenuItem(title: title, action: #selector(selectBackForwardMode(_:)), keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = (config.backForward.mode == mode) ? .on : .off
            bfMenu.addItem(item)
        }
        bfParent.submenu = bfMenu
        menu.addItem(bfParent)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(title: "开机自动启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = LaunchAgentManager.isEnabled ? .on : .off
        menu.addItem(launchItem)

        let openCfg = NSMenuItem(title: "打开配置文件…", action: #selector(openConfigFile), keyEquivalent: "")
        openCfg.target = self
        menu.addItem(openCfg)

        let reloadCfg = NSMenuItem(title: "重载配置", action: #selector(manualReloadConfig), keyEquivalent: "r")
        reloadCfg.target = self
        menu.addItem(reloadCfg)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "退出 LiteMouse", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPermissionRetryIfNeeded()
    }

    @objc private func toggleEnabled() {
        config.enabled.toggle()
        saveAndApply()
    }

    @objc private func selectLinearScroll() {
        config.scroll.mode = .linear
        saveAndApply()
    }

    @objc private func selectSmoothScroll() {
        config.scroll.mode = .smooth
        saveAndApply()
    }

    @objc private func selectDisabledScroll() {
        config.scroll.mode = .disabled
        saveAndApply()
    }

    @objc private func selectScrollLines(_ sender: NSMenuItem) {
        config.scroll.verticalLines = sender.tag
        saveAndApply()
    }

    @objc private func toggleReverseScroll() {
        config.scroll.reverseVertical.toggle()
        saveAndApply()
    }

    @objc private func selectBackForwardMode(_ sender: NSMenuItem) {
        switch sender.tag {
        case 0: config.backForward.mode = .auto
        case 1: config.backForward.mode = .swipe
        case 2: config.backForward.mode = .cmdBracket
        default: config.backForward.mode = .disabled
        }
        saveAndApply()
    }

    @objc private func toggleLaunchAtLogin() {
        try? LaunchAgentManager.setEnabled(!LaunchAgentManager.isEnabled)
    }

    @objc private func openConfigFile() {
        _ = ConfigStore.loadOrCreate()
        NSWorkspace.shared.open(ConfigStore.defaultFileURL)
    }

    @objc private func manualReloadConfig() {
        config = ConfigStore.loadOrCreate()
        applyConfig()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
