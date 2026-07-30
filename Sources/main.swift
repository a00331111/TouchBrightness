import Cocoa

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
        let W: CGFloat = 260, H: CGFloat = 150
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

        let sep = NSBox(frame: NSRect(x: 16, y: H - 82, width: W - 32, height: 1))
        sep.boxType = .separator
        container.addSubview(sep)

        let autoY: CGFloat = H - 104
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
        valueLabel.stringValue = pct(v)
        NotificationCenter.default.post(name: .touchBarBrightnessChanged, object: nil,
                                        userInfo: ["value": v])
    }

    @objc private func autoToggled(_ sender: Any?) {
        if #available(macOS 12.0, *), let sw = sender as? NSSwitch {
            controller.setAutoBrightness(sw.state == .on)
        }
    }

    @objc private func setMax() {
        slider.floatValue = 1.0; controller.setBrightness(1.0)
        valueLabel.stringValue = pct(1.0)
    }

    @objc private func setMin() {
        slider.floatValue = 0.0; controller.setBrightness(0.0)
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
        panel = BrightnessPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 150),
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
        let panelHeight: CGFloat = 150
        panel.setFrameOrigin(NSPoint(x: screenFrame.midX - 130,
                                     y: screenFrame.minY - panelHeight - 4))
        panel.orderFrontRegardless()
        panel.makeKey()
        // Touch Bar appears automatically via makeTouchBar() when panel becomes key
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
}

// ─── Main ────────────────────────────────────────────────────────────────────

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
