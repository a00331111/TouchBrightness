import Cocoa
import ServiceManagement
import CommonCrypto

// ─── .tbinfo 持久化 ──────────────────────────────────────────────────────────
// 每次亮度变化时写入 ~/.tbinfo，init_touchbar.swift 通过 LaunchDaemon
// 定期读取该文件来维持 Touch Bar 亮度不被系统重置。

private func writeTbinfo(_ value: Float) {
    let path = NSHomeDirectory() + "/.tbinfo"
    try? "\(value)".write(toFile: path, atomically: true, encoding: .utf8)
}

// ─── MD5 工具 ────────────────────────────────────────────────────────────────

private func md5(_ data: Data) -> String {
    var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
    data.withUnsafeBytes { buf in
        _ = CC_MD5(buf.baseAddress, CC_LONG(buf.count), &digest)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}

private func md5(ofFile path: String) -> String? {
    guard let data = FileManager.default.contents(atPath: path) else { return nil }
    return md5(data)
}

// ─── Brightness Controller ───────────────────────────────────────────────────

final class BrightnessController {

    static let touchBarDisplayID: UInt32 = 3

    private let bsc: NSObject
    private let setProp3: @convention(c) (NSObject, Selector, AnyObject, NSString, UInt32) -> Bool
    private let setPropSel3: Selector
    private let copyPropSel: Selector
    private let setProp: @convention(c) (NSObject, Selector, AnyObject, NSString) -> Bool
    private let setPropSel: Selector

    init?() {
        guard dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW) != nil else {
            fputs("Error: Failed to load CoreBrightness framework\n", stderr)
            return nil
        }
        guard let cls = NSClassFromString("BrightnessSystemClient") as? NSObject.Type else {
            fputs("Error: BrightnessSystemClient class not found\n", stderr)
            return nil
        }
        let client = cls.init()
        let sel3 = NSSelectorFromString("setProperty:withKey:andDisplay:")
        guard client.responds(to: sel3) else { return nil }
        let copySel = NSSelectorFromString("copyPropertyForKey:andDisplay:")
        guard client.responds(to: copySel) else { return nil }
        let setSel = NSSelectorFromString("setProperty:forKey:")
        guard client.responds(to: setSel) else { return nil }

        self.bsc = client
        self.setPropSel3 = sel3
        self.setProp3 = unsafeBitCast(client.method(for: sel3),
            to: (@convention(c) (NSObject, Selector, AnyObject, NSString, UInt32) -> Bool).self)
        self.copyPropSel = copySel
        self.setPropSel = setSel
        self.setProp = unsafeBitCast(client.method(for: setSel),
            to: (@convention(c) (NSObject, Selector, AnyObject, NSString) -> Bool).self)
    }

    func startObserving(_ callback: @escaping (Float) -> Void) {
        let notifSel = NSSelectorFromString("registerNotificationBlock:forProperties:")
        guard bsc.responds(to: notifSel) else { return }
        let notifImp = bsc.method(for: notifSel)
        typealias NotifyBlock = @convention(block) (AnyObject?, AnyObject?) -> Void
        typealias RegFunc = @convention(c) (NSObject, Selector, AnyObject, NSArray) -> Void
        let regFn = unsafeBitCast(notifImp, to: RegFunc.self)

        let block: NotifyBlock = { dict, key in
            guard let keyStr = key as? String, keyStr == "DisplayBrightness" else { return }
            guard let dict = dict else { return }
            let sel = NSSelectorFromString("valueForKey:")
            guard dict.responds(to: sel) else { return }
            guard let rawEntry = dict.perform(sel, with: "Brightness" as NSString) else { return }
            let entry = rawEntry.takeUnretainedValue()
            var val: Float?
            if let n = entry as? NSNumber { val = n.floatValue }
            else if let s = entry as? String { val = Float(s) }
            if let v = val { DispatchQueue.main.async { callback(v) } }
        }
        let wrappedBlock = unsafeBitCast(block, to: AnyObject.self)
        regFn(bsc, notifSel, wrappedBlock, ["DisplayBrightness"] as NSArray)
    }

    private func copyDisplayProperty(key: String, displayID: UInt32) -> AnyObject? {
        typealias CopyFn = @convention(c) (NSObject, Selector, NSString, UInt32) -> UnsafeMutableRawPointer?
        let fn = unsafeBitCast(bsc.method(for: copyPropSel), to: CopyFn.self)
        guard let ptr = fn(bsc, copyPropSel, key as NSString, displayID) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
    }

    private func readBrightnessFloat() -> Float {
        guard let result = copyDisplayProperty(key: "DisplayBrightness",
                                               displayID: BrightnessController.touchBarDisplayID) else { return 1.0 }
        let sel = NSSelectorFromString("valueForKey:")
        guard result.responds(to: sel) else { return 1.0 }
        guard let rawEntry = result.perform(sel, with: "Brightness" as NSString) else { return 1.0 }
        let entry = rawEntry.takeUnretainedValue()
        if let n = entry as? NSNumber { return n.floatValue }
        if let s = entry as? String, let v = Float(s) { return v }
        return 1.0
    }

    func getBrightness() -> Float { readBrightnessFloat() }

    func setBrightness(_ value: Float) {
        let clamped = min(max(value, 0.0), 1.0)
        _ = setProp3(bsc, setPropSel3, clamped as NSNumber,
                     "DisplayBrightness" as NSString, BrightnessController.touchBarDisplayID)
    }

    func isAutoBrightnessEnabled() -> Bool {
        guard let result = copyDisplayProperty(key: "DisplayBrightnessAuto",
                                               displayID: BrightnessController.touchBarDisplayID) else { return false }
        if let n = result as? NSNumber { return n.boolValue }
        let sel = NSSelectorFromString("valueForKey:")
        guard result.responds(to: sel) else { return false }
        guard let rawEntry = result.perform(sel, with: "DisplayBrightnessAuto" as NSString) else { return false }
        let entry = rawEntry.takeUnretainedValue()
        if let n = entry as? NSNumber { return n.boolValue }
        return false
    }

    func setAutoBrightness(_ enabled: Bool) {
        let num = enabled ? 1 : 0
        _ = setProp3(bsc, setPropSel3, num as NSNumber,
                     "DisplayBrightnessAuto" as NSString, BrightnessController.touchBarDisplayID)
        _ = setProp(bsc, setPropSel, num as NSNumber, "DisplayBrightnessAuto" as NSString)
    }
}

// ─── Script Downloader (with MD5 verification) ─────────────────────────────

private enum ScriptDownloader {

    static let repo = "a00331111/TouchBrightness"
    static var scriptsDir: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("TouchBrightness", isDirectory: true)
    }

    /// 下载脚本并校验 MD5 完整性。
    /// 1. 从 GitHub 下载 checksums.md5
    /// 2. 比较本地文件 MD5 与远端值
    /// 3. 不一致则重新下载，下载后再验证一次
    static func downloadIfNeeded() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: scriptsDir.path) {
            try fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        }

        let base = "https://raw.githubusercontent.com/\(repo)/main/Sources"
        let checksumsURL = "\(base)/checksums.md5"
        let shPath = scriptsDir.appendingPathComponent("init_touchbar.sh")
        let swiftPath = scriptsDir.appendingPathComponent("init_touchbar.swift")

        // 下载 checksums
        guard let checksumsData = downloadSync(url: checksumsURL),
              let checksumsText = String(data: checksumsData, encoding: .utf8) else {
            // checksums 下载失败，回退：如果脚本不存在就下载，不校验
            if !fm.fileExists(atPath: shPath.path) || !fm.fileExists(atPath: swiftPath.path) {
                try download(url: "\(base)/init_touchbar.sh", to: shPath)
                try download(url: "\(base)/init_touchbar.swift", to: swiftPath)
            }
            return
        }

        // 解析 checksums: "md5hash  filename\n"
        var expected: [String: String] = [:]
        for line in checksumsText.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ", maxSplits: 1)
            if parts.count == 2 {
                expected[String(parts[1])] = String(parts[0])
            }
        }

        // 检查本地文件是否需要更新
        let files = [("init_touchbar.sh", shPath), ("init_touchbar.swift", swiftPath)]
        var needsDownload = false

        for (name, localPath) in files {
            guard let expectedMD5 = expected[name] else {
                needsDownload = true; break
            }
            if let localMD5 = md5(ofFile: localPath.path), localMD5 == expectedMD5 {
                continue // 一致，跳过
            }
            needsDownload = true
            break
        }

        if !needsDownload { return }

        // 重新下载
        fputs("ScriptDownloader: checksum mismatch or missing, re-downloading...\n", stderr)
        try download(url: "\(base)/init_touchbar.sh", to: shPath)
        try download(url: "\(base)/init_touchbar.swift", to: swiftPath)

        // 下载后校验
        for (name, localPath) in files {
            if let expectedMD5 = expected[name], let localMD5 = md5(ofFile: localPath.path) {
                if localMD5 != expectedMD5 {
                    throw NSError(domain: "ScriptDL", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "MD5 verification failed for \(name): expected \(expectedMD5), got \(localMD5)"])
                }
            }
        }
    }

    private static func download(url: String, to dest: URL) throws {
        guard let data = downloadSync(url: url) else {
            throw NSError(domain: "ScriptDL", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to download \(url)"])
        }
        try data.write(to: dest)
    }

    private static func downloadSync(url: String) -> Data? {
        let sem = DispatchSemaphore(value: 0)
        var result: Data?
        URLSession.shared.dataTask(with: URL(string: url)!) { data, _, _ in
            result = data; sem.signal()
        }.resume()
        sem.wait()
        return result
    }
}

// ─── Touch Bar Manager ───────────────────────────────────────────────────────

private let tbMainID = NSTouchBarItem.Identifier("com.touchbarbrightness.main")

final class TouchBarManager: NSObject, NSTouchBarDelegate {

    let brightnessController: BrightnessController
    private weak var tbSlider: NSSlider?

    init(controller: BrightnessController) {
        self.brightnessController = controller
        super.init()
    }

    func makeTouchBarView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 30))

        let icon = NSImageView(frame: NSRect(x: 0, y: 5, width: 20, height: 20))
        icon.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)
        icon.contentTintColor = .white
        container.addSubview(icon)

        let pctLabel = NSTextField(labelWithString: pct(brightnessController.getBrightness()))
        pctLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        pctLabel.textColor = .white
        pctLabel.alignment = .right
        pctLabel.frame = NSRect(x: 350, y: 5, width: 40, height: 20)
        pctLabel.identifier = NSUserInterfaceItemIdentifier("pctLabel")
        container.addSubview(pctLabel)

        let sl = NSSlider(value: Double(brightnessController.getBrightness()),
                          minValue: 0.0, maxValue: 1.0,
                          target: self, action: #selector(touchBarSliderChanged(_:)))
        sl.frame = NSRect(x: 28, y: 5, width: 314, height: 20)
        sl.isContinuous = true
        sl.controlSize = .regular
        container.addSubview(sl)
        self.tbSlider = sl

        return container
    }

    func touchBar(_ touchBar: NSTouchBar,
                  makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        guard identifier == tbMainID else { return nil }
        let item = NSCustomTouchBarItem(identifier: identifier)
        item.view = makeTouchBarView()
        return item
    }

    func updateSliderValue(_ value: Float) {
        tbSlider?.doubleValue = Double(value)
        if let container = tbSlider?.superview {
            for sub in container.subviews where sub.identifier?.rawValue == "pctLabel" {
                (sub as? NSTextField)?.stringValue = pct(value)
            }
        }
    }

    @objc private func touchBarSliderChanged(_ sender: NSSlider) {
        let v = Float(sender.doubleValue)
        brightnessController.setBrightness(v)
        writeTbinfo(v)
        if let container = sender.superview {
            for sub in container.subviews where sub.identifier?.rawValue == "pctLabel" {
                (sub as? NSTextField)?.stringValue = pct(v)
            }
        }
        NotificationCenter.default.post(name: .touchBarBrightnessChanged, object: nil,
                                        userInfo: ["value": v])
    }

    private func pct(_ v: Float) -> String { "\(Int(round(v * 100)))%" }
}

extension Notification.Name {
    static let touchBarBrightnessChanged = Notification.Name("touchBarBrightnessChanged")
}

// ─── Panel with Touch Bar ────────────────────────────────────────────────────

private final class BrightnessPanel: NSPanel {

    var touchBarManager: TouchBarManager?

    override var canBecomeKey: Bool { true }

    override func makeTouchBar() -> NSTouchBar? {
        guard let manager = touchBarManager else { return nil }
        let tb = NSTouchBar()
        tb.delegate = manager
        tb.defaultItemIdentifiers = [tbMainID]
        return tb
    }

    /// 强制重建 Touch Bar（开机自启时 OS 可能尚未就绪，需延迟重试）
    func rebuildTouchBar() {
        self.touchBar = nil
        self.touchBar = makeTouchBar()
    }
}

// ─── Popover View Controller ─────────────────────────────────────────────────

final class BrightnessViewController: NSViewController {

    let controller: BrightnessController
    private var slider: NSSlider!
    private var valueLabel: NSTextField!

    init(controller: BrightnessController) {
        self.controller = controller
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let W: CGFloat = 260, H: CGFloat = 200
        let container = NSView(frame: NSRect(x: 0, y: 0, width: W, height: H))

        let title = NSTextField(labelWithString: NSLocalizedString("popover.title", comment: ""))
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .secondaryLabelColor
        title.alignment = .center
        title.frame = NSRect(x: 16, y: H - 28, width: W - 32, height: 18)
        container.addSubview(title)

        let sliderY: CGFloat = H - 64

        let minImg = NSImageView(frame: NSRect(x: 16, y: sliderY, width: 16, height: 16))
        minImg.image = NSImage(systemSymbolName: "sun.min.fill", accessibilityDescription: nil)
        minImg.contentTintColor = .tertiaryLabelColor
        container.addSubview(minImg)

        slider = NSSlider(value: Double(controller.getBrightness()),
                          minValue: 0.0, maxValue: 1.0,
                          target: self, action: #selector(sliderChanged(_:)))
        slider.frame = NSRect(x: 36, y: sliderY - 2, width: W - 36 - 72, height: 20)
        slider.isContinuous = true
        container.addSubview(slider)

        let maxImg = NSImageView(frame: NSRect(x: W - 72 + 4, y: sliderY, width: 16, height: 16))
        maxImg.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: nil)
        maxImg.contentTintColor = .labelColor
        container.addSubview(maxImg)

        valueLabel = NSTextField(labelWithString: pct(slider.floatValue))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: W - 50, y: sliderY - 1, width: 36, height: 16)
        container.addSubview(valueLabel)

        let sep = NSBox(frame: NSRect(x: 16, y: H - 90, width: W - 32, height: 1))
        sep.boxType = .separator
        container.addSubview(sep)

        let autoY: CGFloat = H - 112
        let autoLabel = NSTextField(labelWithString: NSLocalizedString("popover.auto", comment: ""))
        autoLabel.font = .systemFont(ofSize: 13, weight: .regular)
        autoLabel.textColor = .labelColor
        autoLabel.frame = NSRect(x: 16, y: autoY, width: 120, height: 18)
        container.addSubview(autoLabel)

        if #available(macOS 12.0, *) {
            let sw = NSSwitch()
            sw.state = controller.isAutoBrightnessEnabled() ? .on : .off
            sw.target = self
            sw.action = #selector(autoToggled(_:))
            sw.frame = NSRect(x: W - 58, y: autoY - 3, width: 40, height: 22)
            container.addSubview(sw)
        }

        let launchY: CGFloat = H - 142
        let launchLabel = NSTextField(labelWithString: NSLocalizedString("popover.launch", comment: ""))
        launchLabel.font = .systemFont(ofSize: 13, weight: .regular)
        launchLabel.textColor = .labelColor
        launchLabel.frame = NSRect(x: 16, y: launchY, width: 120, height: 18)
        container.addSubview(launchLabel)

        if #available(macOS 13.0, *) {
            let launchSw = NSSwitch()
            launchSw.state = SMAppService.mainApp.status == .enabled ? .on : .off
            launchSw.target = self
            launchSw.action = #selector(launchToggled(_:))
            launchSw.frame = NSRect(x: W - 58, y: launchY - 3, width: 40, height: 22)
            container.addSubview(launchSw)
        }

        let btnY: CGFloat = 12
        let minBtn = NSButton(title: NSLocalizedString("btn.min", comment: ""),
                              target: self, action: #selector(setMin))
        minBtn.bezelStyle = .inline
        minBtn.font = .systemFont(ofSize: 11, weight: .medium)
        minBtn.frame = NSRect(x: 16, y: btnY, width: 50, height: 22)
        container.addSubview(minBtn)

        let maxBtn = NSButton(title: NSLocalizedString("btn.max", comment: ""),
                              target: self, action: #selector(setMax))
        maxBtn.bezelStyle = .inline
        maxBtn.font = .systemFont(ofSize: 11, weight: .medium)
        maxBtn.frame = NSRect(x: 72, y: btnY, width: 50, height: 22)
        container.addSubview(maxBtn)

        let quitBtn = NSButton(title: NSLocalizedString("btn.quit", comment: ""),
                               target: NSApp, action: #selector(NSApp.terminate(_:)))
        quitBtn.bezelStyle = .inline
        quitBtn.font = .systemFont(ofSize: 11, weight: .medium)
        quitBtn.contentTintColor = .systemRed
        quitBtn.frame = NSRect(x: W - 66, y: btnY, width: 50, height: 22)
        container.addSubview(quitBtn)

        self.view = container

        NotificationCenter.default.addObserver(
            self, selector: #selector(externalChanged(_:)),
            name: .touchBarBrightnessChanged, object: nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshValues()
    }

    func refreshValues() {
        guard isViewLoaded, slider != nil else { return }
        guard Thread.isMainThread else {
            DispatchQueue.main.async { self.refreshValues() }; return
        }
        let v = controller.getBrightness()
        slider.floatValue = v
        valueLabel.stringValue = pct(v)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let v = sender.floatValue
        controller.setBrightness(v)
        writeTbinfo(v)
        valueLabel.stringValue = pct(v)
        NotificationCenter.default.post(name: .touchBarBrightnessChanged, object: nil,
                                        userInfo: ["value": v])
    }

    @objc private func autoToggled(_ sender: Any?) {
        if #available(macOS 12.0, *), let sw = sender as? NSSwitch {
            controller.setAutoBrightness(sw.state == .on)
        }
    }

    @objc private func launchToggled(_ sender: Any?) {
        if #available(macOS 13.0, *), let sw = sender as? NSSwitch {
            do {
                if sw.state == .on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                fputs("Failed to toggle launch at login: \(error)\n", stderr)
                sw.state = sw.state == .on ? .off : .on
            }
        }
    }

    @objc private func setMax() {
        slider.floatValue = 1.0; controller.setBrightness(1.0)
        writeTbinfo(1.0)
        valueLabel.stringValue = pct(1.0)
    }

    @objc private func setMin() {
        slider.floatValue = 0.0; controller.setBrightness(0.0)
        writeTbinfo(0.0)
        valueLabel.stringValue = pct(0.0)
    }

    @objc private func externalChanged(_ note: Notification) {
        guard let v = note.userInfo?["value"] as? Float else { return }
        slider.floatValue = v; valueLabel.stringValue = pct(v)
    }

    private func pct(_ v: Float) -> String { "\(Int(round(v * 100)))%" }
}

// ─── AppDelegate ─────────────────────────────────────────────────────────────

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var panel: BrightnessPanel!
    private var brightnessCtrl: BrightnessController!
    private var touchBarManager: TouchBarManager!
    private var popoverVC: BrightnessViewController!
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isDismissing = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let ctrl = BrightnessController() else {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("alert.no_tb.title", comment: "")
            alert.informativeText = NSLocalizedString("alert.no_tb.msg", comment: "")
            alert.alertStyle = .critical
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        self.brightnessCtrl = ctrl

        // 检查 LaunchDaemon plist 是否已安装（存在即代表已配置）
        // 注意：不能用 launchctl list 检测，因为 LaunchDaemon 在 system domain，
        // 普通用户无权查询，永远返回 "Could not find service"。
        let daemonPlist = "/Library/LaunchDaemons/com.touchbarbrightness.init.plist"

        if !FileManager.default.fileExists(atPath: daemonPlist) {
            // LaunchDaemon 不存在 → 需要设置开机自启
            var scriptReady = false
            do { try ScriptDownloader.downloadIfNeeded(); scriptReady = true }
            catch { fputs("Warning: failed to download init scripts: \(error)\n", stderr) }

            if scriptReady {
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("init.title", comment: "")
                alert.informativeText = NSLocalizedString("init.msg", comment: "")
                alert.alertStyle = .informational
                alert.addButton(withTitle: NSLocalizedString("init.yes", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("init.no", comment: ""))

                if alert.runModal() == .alertFirstButtonReturn {
                    // 1. 立即执行一次初始化
                    let shPath = ScriptDownloader.scriptsDir.appendingPathComponent("init_touchbar.sh").path
                    let ascript = "do shell script \"bash '\(shPath)'\" with administrator privileges"
                    var error: NSDictionary?
                    NSAppleScript(source: ascript)?.executeAndReturnError(&error)
                    if error == nil {
                        // 2. 安装 LaunchDaemon，开机自动初始化
                        setupLaunchDaemon()
                    }
                }
            }
        } else {
            // LaunchDaemon 已存在 → 确保 wrapper 脚本是最新的（修复旧版本的 shell 转义 bug）
            refreshDaemonWrapper()
        }

        self.touchBarManager = TouchBarManager(controller: ctrl)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "sun.max.fill",
                                 accessibilityDescription: NSLocalizedString("statusbar.a11y", comment: "")) {
                img.isTemplate = true; button.image = img
            } else {
                button.title = "☀️"
            }
            button.action = #selector(togglePanel(_:))
            button.target = self
        }

        popoverVC = BrightnessViewController(controller: ctrl)

        // Panel with built-in Touch Bar — no private API needed
        panel = BrightnessPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 200),
                        styleMask: [.titled, .fullSizeContentView],
                        backing: .buffered, defer: true)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.contentViewController = popoverVC
        panel.isMovableByWindowBackground = false
        panel.touchBarManager = touchBarManager

        // Dismiss when clicking outside the app
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            guard let self = self, self.panel.isVisible else { return }
            self.dismissPanel()
        }

        // Dismiss on Escape key only
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) {
            [weak self] event in
            guard let self = self, self.panel.isVisible else { return event }
            if event.keyCode == 53 { self.dismissPanel() }
            return event
        }

        ctrl.startObserving { [weak self] newValue in
            self?.popoverVC?.refreshValues()
            self?.touchBarManager?.updateSliderValue(newValue)
        }

        // Sync: popover slider change → update Touch Bar slider
        NotificationCenter.default.addObserver(
            forName: .touchBarBrightnessChanged, object: nil, queue: .main
        ) { [weak self] note in
            guard let v = note.userInfo?["value"] as? Float else { return }
            self?.touchBarManager?.updateSliderValue(v)
        }
    }

    @objc private func togglePanel(_ sender: AnyObject?) {
        if panel.isVisible {
            dismissPanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem.button, let win = button.window else { return }
        popoverVC.refreshValues()

        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = win.convertToScreen(buttonFrame)
        let panelHeight: CGFloat = 200
        panel.setFrameOrigin(NSPoint(x: screenFrame.midX - 130,
                                     y: screenFrame.minY - panelHeight - 4))
        panel.orderFrontRegardless()
        panel.makeKey()
        // Touch Bar appears automatically via makeTouchBar() when panel becomes key

        // 开机自启场景：Touch Bar 硬件可能尚未就绪，延迟 1 秒后强制重建
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self, self.panel.isVisible else { return }
            self.panel.rebuildTouchBar()
        }
    }

    private func dismissPanel() {
        guard !isDismissing else { return }
        isDismissing = true
        if panel.isKeyWindow { panel.resignKey() }
        panel.orderOut(nil)
        // Touch Bar disappears automatically when panel resigns key / is ordered out
        isDismissing = false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let m = localMonitor { NSEvent.removeMonitor(m) }
        NotificationCenter.default.removeObserver(self)
    }

    // ─── LaunchDaemon: 开机自动初始化 Touch Bar ──────────────────────────────
    // CoreBrightness 的 Touch Bar 子系统在每次重启后需要重新初始化。
    // 安装 LaunchDaemon，每次开机自动运行 init_touchbar.swift。

    private func setupLaunchDaemon() {
        let scriptsDir = ScriptDownloader.scriptsDir
        let swiftScript = scriptsDir.appendingPathComponent("init_touchbar.swift")

        // 创建 shell 包装脚本（LaunchDaemon 通过 bash 执行）
        let wrapperDir = scriptsDir.appendingPathComponent("daemon")
        let wrapperPath = wrapperDir.appendingPathComponent("run_init.sh")

        do {
            let fm = FileManager.default
            if !fm.fileExists(atPath: wrapperDir.path) {
                try fm.createDirectory(at: wrapperDir, withIntermediateDirectories: true)
            }

            let wrapper = "#!/bin/bash\n# TouchBrightness daemon wrapper — 开机自动初始化 Touch Bar\n# 由 TouchBrightness.app 自动生成，请勿手动修改\n\nREAL_USER=$(stat -f%Su /dev/console)\nUSER_HOME=$(eval echo ~$REAL_USER)\nexec swift \"\(swiftScript.path)\" \"$USER_HOME\"\n"
            try wrapper.write(toFile: wrapperPath.path, atomically: true, encoding: .utf8)

            // 设置可执行权限
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath.path)
        } catch {
            fputs("Warning: failed to create daemon wrapper: \(error)\n", stderr)
            return
        }

        // 写入 LaunchDaemon plist（先写临时文件，再用 sudo 拷贝）
        let plistPath = "/Library/LaunchDaemons/com.touchbarbrightness.init.plist"
        let tmpPlist = NSTemporaryDirectory() + "com.touchbarbrightness.init.plist"
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.touchbarbrightness.init</string>
            <key>ProgramArguments</key>
            <array>
                <string>/bin/bash</string>
                <string>\(wrapperPath.path)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
            <key>StartInterval</key>
            <integer>300</integer>
            <key>StandardOutPath</key>
            <string>/tmp/touchbarbrightness_init.log</string>
            <key>StandardErrorPath</key>
            <string>/tmp/touchbarbrightness_init.log</string>
        </dict>
        </plist>
        """

        do {
            try plist.write(toFile: tmpPlist, atomically: true, encoding: .utf8)
        } catch {
            fputs("Warning: failed to write temp plist: \(error)\n", stderr)
            return
        }

        // 通过 AppleScript 以 root 权限拷贝 plist 并加载 LaunchDaemon
        let setupScript = "do shell script \"cp '\(tmpPlist)' '\(plistPath)' && launchctl unload '\(plistPath)' 2>/dev/null; launchctl load '\(plistPath)'\" with administrator privileges"
        var error: NSDictionary?
        NSAppleScript(source: setupScript)?.executeAndReturnError(&error)
        if let error = error {
            fputs("Warning: failed to install LaunchDaemon: \(error)\n", stderr)
        } else {
            fputs("LaunchDaemon installed: Touch Bar will initialize on every boot.\n", stderr)
        }
        // 清理临时文件
        try? FileManager.default.removeItem(atPath: tmpPlist)
    }

    /// 仅重新生成 wrapper 脚本（不重新安装 plist），用于修复旧版本的 shell 转义 bug
    private func refreshDaemonWrapper() {
        let scriptsDir = ScriptDownloader.scriptsDir
        let swiftScript = scriptsDir.appendingPathComponent("init_touchbar.swift")
        let wrapperPath = scriptsDir.appendingPathComponent("daemon/run_init.sh")

        let wrapper = "#!/bin/bash\n# TouchBrightness daemon wrapper — 开机自动初始化 Touch Bar\n# 由 TouchBrightness.app 自动生成，请勿手动修改\n\nREAL_USER=$(stat -f%Su /dev/console)\nUSER_HOME=$(eval echo ~$REAL_USER)\nexec swift \"\(swiftScript.path)\" \"$USER_HOME\"\n"
        do {
            try wrapper.write(toFile: wrapperPath.path, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapperPath.path)
        } catch {
            fputs("Warning: failed to refresh daemon wrapper: \(error)\n", stderr)
        }
    }
}

// ─── Main ────────────────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
