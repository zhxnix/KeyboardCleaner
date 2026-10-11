//
//  KeyboardCleaner —— 键盘清洁锁
//
//  菜单栏小工具：锁定期间在会话层拦截（吞掉）所有键盘、触控板、鼠标、
//  滚轮、手势事件，方便擦拭键盘和触控板；按组合键（默认 ⌥⌘ + Esc）解锁。
//
//  原理：CGEventTap (kCGEventTapOptionDefault) 需要在
//  系统设置 → 隐私与安全性 → 辅助功能 中授权本应用。
//

import Cocoa
import Carbon.HIToolbox
import ApplicationServices
import SwiftUI

// MARK: - 按键名称与解锁组合键

enum KeyNames {
    // 解锁键的可配置名称 → 虚拟键码（HIToolbox Virtual KeyCodes）
    static let named: [String: CGKeyCode] = [
        "esc": 53, "escape": 53,
        "space": 49, "return": 36, "enter": 36, "tab": 48,
        "delete": 51, "backspace": 51,
        "`": 50, "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42,
        ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5,
        "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12,
        "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "o": 31, "u": 32, "i": 34, "p": 35,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29,
    ]
    static let fKeys: [CGKeyCode] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    static func code(for key: String) -> CGKeyCode? {
        let k = key.trimmingCharacters(in: .whitespaces).lowercased()
        if let c = named[k] { return c }
        if k.count >= 2, k.first == "f", let n = Int(k.dropFirst()), (1...12).contains(n) {
            return fKeys[n - 1]
        }
        return nil
    }

    static func name(for code: CGKeyCode) -> String {
        switch code {
        case 53: return "⎋ Esc"
        case 49: return "Space 空格"
        case 36: return "↩ Return"
        case 48: return "⇥ Tab"
        case 51: return "⌫ Delete"
        default: break
        }
        if let idx = fKeys.firstIndex(of: code) { return "F\(idx + 1)" }
        if let letter = named.first(where: { $0.value == code })?.key { return letter.uppercased() }
        return "键码 \(code)"
    }
}

struct UnlockCombo {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    static let standard = UnlockCombo(keyCode: 53, flags: [.maskCommand, .maskAlternate]) // ⌥⌘ + Esc

    /// keyDown 事件是否命中解锁组合（所需修饰键全部按住 + 指定键按下）
    func matches(_ event: CGEvent) -> Bool {
        CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode
            && flags.isSubset(of: event.flags)
    }

    var displayText: String {
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("⌃ Control") }
        if flags.contains(.maskAlternate) { parts.append("⌥ Option") }
        if flags.contains(.maskShift) { parts.append("⇧ Shift") }
        if flags.contains(.maskCommand) { parts.append("⌘ Command") }
        if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
        parts.append(KeyNames.name(for: keyCode))
        return parts.joined(separator: " + ")
    }

    static func parseFlags(_ s: String) -> CGEventFlags? {
        var f = CGEventFlags()
        let tokens = s.lowercased().split(whereSeparator: { ",+ ".contains($0) })
        guard !tokens.isEmpty else { return nil }
        for t in tokens {
            switch t {
            case "cmd", "command", "⌘": f.insert(.maskCommand)
            case "alt", "opt", "option", "⌥": f.insert(.maskAlternate)
            case "ctrl", "control", "⌃": f.insert(.maskControl)
            case "shift", "⇧": f.insert(.maskShift)
            case "fn": f.insert(.maskSecondaryFn)
            default: return nil
            }
        }
        return f
    }

    /// 优先级：命令行 --key/--mods > UserDefaults(unlockKey/unlockMods) > 默认 ⌥⌘Esc
    static func resolve() -> UnlockCombo {
        var keyString: String?
        var modsString: String?
        let args = Array(CommandLine.arguments.dropFirst())
        var i = 0
        while i < args.count {
            if args[i] == "--key", i + 1 < args.count { keyString = args[i + 1]; i += 2; continue }
            if args[i] == "--mods", i + 1 < args.count { modsString = args[i + 1]; i += 2; continue }
            i += 1
        }
        let defaults = UserDefaults.standard
        if keyString == nil { keyString = defaults.string(forKey: "unlockKey") }
        if modsString == nil { modsString = defaults.string(forKey: "unlockMods") }

        var keyCode = standard.keyCode
        var flags = standard.flags
        if let ks = keyString {
            guard let c = KeyNames.code(for: ks) else {
                FileHandle.standardError.write("无法识别的解锁键 \"\(ks)\"，可用: a-z 0-9 esc return space tab delete f1-f12\n".data(using: .utf8)!)
                exit(2)
            }
            keyCode = c
        }
        if let ms = modsString {
            guard let f = parseFlags(ms) else {
                FileHandle.standardError.write("无法识别的修饰键 \"\(ms)\"，可用: cmd alt ctrl shift fn（逗号分隔）\n".data(using: .utf8)!)
                exit(2)
            }
            flags = f
        }
        return UnlockCombo(keyCode: keyCode, flags: flags)
    }
}

// MARK: - 输入拦截器（CGEventTap）

let debugEnabled = ProcessInfo.processInfo.environment["KC_DEBUG"] == "1"
func debugLog(_ message: String) {
    if debugEnabled { FileHandle.standardError.write("[KC] \(message)\n".data(using: .utf8)!) }
}

final class InputBlocker {
    static let shared = InputBlocker()

    let combo: UnlockCombo
    var onStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?

    private let mutex = NSLock()
    private var tap: CFMachPort?
    private var runLoop: CFRunLoop?
    private var locked = false

    var isLocked: Bool {
        mutex.lock(); defer { mutex.unlock() }
        return locked
    }

    private init() {
        combo = UnlockCombo.resolve()
    }

    /// 需要拦截的事件：鼠标按下/抬起/移动/拖拽、键盘按下/抬起/修饰键、
    /// 系统键（亮度/音量/媒体）、滚轮、数位板、其他鼠标键、各类手势
    private static let eventMask: CGEventMask = {
        let bits: [UInt64] = [1, 2, 3, 4, 5, 6, 7,
                              10, 11, 12,
                              14,
                              22,
                              23, 24,
                              25, 26, 27,
                              29, 30, 31, 33, 34]
        return CGEventMask(bits.reduce(UInt64(0)) { $0 | (1 << $1) })
    }()

    func isTrusted(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    func beginLocking() {
        mutex.lock(); let existing = tap; mutex.unlock()
        if let existing {
            CGEvent.tapEnable(tap: existing, enable: true)
            setLocked(true)
            return
        }
        Thread.detachNewThread {
            let callback: CGEventTapCallBack = { _, type, event, info in
                guard let info else { return nil }
                let blocker = Unmanaged<InputBlocker>.fromOpaque(info).takeUnretainedValue()
                return blocker.handleTapEvent(type, event)
            }
            guard let newTap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                                place: .headInsertEventTap,
                                                options: .defaultTap,
                                                eventsOfInterest: Self.eventMask,
                                                callback: callback,
                                                userInfo: Unmanaged.passUnretained(self).toOpaque()),
                  let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
                DispatchQueue.main.async {
                    self.onError?("无法创建事件拦截，请检查「辅助功能」权限是否已授予本应用。")
                }
                return
            }
            let rl = CFRunLoopGetCurrent()
            CFRunLoopAddSource(rl, source, .defaultMode)
            self.mutex.lock()
            self.tap = newTap
            self.runLoop = rl
            self.mutex.unlock()
            debugLog("tap 已创建并进入运行循环")
            DispatchQueue.main.async { self.setLocked(true) }
            CFRunLoopRun()
        }
    }

    func endLocking() {
        mutex.lock(); let t = tap; mutex.unlock()
        if let t {
            CGEvent.tapEnable(tap: t, enable: false)
        }
        setLocked(false)
    }

    func unlock() { endLocking() }

    private func setLocked(_ value: Bool) {
        mutex.lock(); locked = value; mutex.unlock()
        debugLog("锁定状态 -> \(value)")
        onStateChange?(value)
    }

    /// tap 回调（后台线程）：吞掉一切事件；命中解锁组合则触发解锁；
    /// 系统超时禁用了 tap 时自动重新启用，避免“锁死”在启用状态失效。
    private func handleTapEvent(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            mutex.lock(); let t = tap; let l = locked; mutex.unlock()
            if let t, l { CGEvent.tapEnable(tap: t, enable: true) }
            return nil
        }
        if type == .keyDown, combo.matches(event) {
            DispatchQueue.main.async { self.unlock() }
        }
        return nil // ← 吞掉
    }
}

// MARK: - 全屏遮罩

final class OverlayController {
    private var panels: [NSPanel] = []

    func show(comboText: String) {
        hide()
        debugLog("显示遮罩，屏幕数=\(NSScreen.screens.count)")
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame,
                                styleMask: [.borderless],
                                backing: .buffered,
                                defer: false)
            panel.level = .screenSaver
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            // 遮罩自身永远不响应鼠标：即使拦截失效也不会挡住系统操作
            panel.ignoresMouseEvents = true
            let host = NSHostingView(rootView: OverlayView(comboText: comboText))
            host.frame = screen.frame
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            panel.orderFrontRegardless()
            panels.append(panel)
        }
    }

    func hide() {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
    }
}

struct OverlayView: View {
    let comboText: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.62).ignoresSafeArea()
            VStack(spacing: 20) {
                Text("🧽")
                    .font(.system(size: 84))
                Text("键盘与触控板已锁定")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundColor(.white)
                Text("放心擦拭吧 ✨ Safe to clean")
                    .font(.system(size: 19))
                    .foregroundColor(.white.opacity(0.82))
                HStack(spacing: 8) {
                    Image(systemName: "lock.open.fill")
                    Text("解锁 Unlock：\(comboText)")
                }
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(Capsule().fill(Color.white.opacity(0.16)))
                .overlay(Capsule().stroke(Color.white.opacity(0.35)))
                .padding(.top, 10)
            }
            .multilineTextAlignment(.center)
            .padding(40)
        }
    }
}

// MARK: - 启动提示气泡（菜单栏应用没有窗口，用它给用户可见反馈）

final class LaunchBubble {
    private var panel: NSPanel?

    func show() {
        dismiss()
        guard let screen = NSScreen.main else { return }
        let size = NSSize(width: 360, height: 112)
        let origin = NSPoint(x: screen.frame.maxX - size.width - 14,
                             y: screen.frame.maxY - size.height - 12)
        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        let host = NSHostingView(rootView: BubbleView(onLock: { [weak self] in
            self?.dismiss()
            AppDelegate.current?.requestLock()
        }))
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        debugLog("启动气泡已显示")

        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    func dismiss(animated: Bool = false) {
        guard let panel else { return }
        self.panel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
        } else {
            panel.orderOut(nil)
        }
    }
}

struct BubbleView: View {
    let onLock: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("🧽").font(.system(size: 26))
                VStack(alignment: .leading, spacing: 2) {
                    Text("键盘清洁锁已在菜单栏运行 · Menu bar ready")
                        .font(.system(size: 13, weight: .semibold))
                    Text("点右上角 🎹 图标锁定键盘 · Click the 🎹 icon to lock")
                        .font(.system(size: 11))
                        .opacity(0.65)
                }
            }
            Button(action: onLock) {
                Text("🔒 立即锁定 Lock now")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .buttonStyle(.borderedProminent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.08)))
    }
}

// MARK: - 命令行参数

enum CLI {
    static var lockNow: Bool { CommandLine.arguments.contains("--lock") }
    static var unlockInSeconds: TimeInterval? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--unlock-in"),
              i + 1 < args.count,
              let n = Double(args[i + 1]), n > 0 else { return nil }
        return n
    }
}

// MARK: - 应用主体（菜单栏）

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let overlay = OverlayController()
    private let bubble = LaunchBubble()
    private var lockItem: NSMenuItem?
    private var unlockItem: NSMenuItem?
    private var autoUnlockTimer: Timer?

    private static weak var instance: AppDelegate?
    static var current: AppDelegate? { instance }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.instance = self
        InputBlocker.shared.onStateChange = { [weak self] locked in self?.applyState(locked) }
        InputBlocker.shared.onError = { [weak self] message in self?.showError(message) }
        buildStatusBar()
        bubble.show() // 启动反馈：告诉用户它住在菜单栏

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            if InputBlocker.shared.isLocked {
                self?.overlay.show(comboText: InputBlocker.shared.combo.displayText)
            }
        }

        if CLI.lockNow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.requestLock()
            }
        }
    }

    /// 双击 .app（或 open 已在运行的实例）时再次弹出提示气泡
    func applicationShouldHandleReopen(_ application: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        bubble.show()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        InputBlocker.shared.endLocking() // 退出兜底：绝不带着拦截退出
    }

    // MARK: 菜单栏

    private func buildStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.toolTip = "键盘清洁锁"
        let menu = NSMenu()

        let li = NSMenuItem(title: "🔒 锁定键盘 Lock Keyboard",
                            action: #selector(requestLock), keyEquivalent: "")
        li.target = self
        let ui = NSMenuItem(title: "🔓 解锁 Unlock（\(InputBlocker.shared.combo.displayText)）",
                            action: #selector(requestUnlock), keyEquivalent: "")
        ui.target = self
        let quit = NSMenuItem(title: "退出 Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared

        menu.items = [li, ui, .separator(), quit]
        item.menu = menu
        statusItem = item
        lockItem = li
        unlockItem = ui
        refreshMenu(InputBlocker.shared.isLocked)
    }

    private func refreshMenu(_ locked: Bool) {
        statusItem?.button?.image = NSImage(
            systemSymbolName: locked ? "lock.fill" : "keyboard",
            accessibilityDescription: locked ? "键盘已锁定" : "键盘清洁锁"
        )
        lockItem?.isHidden = locked
        unlockItem?.isHidden = !locked
    }

    // MARK: 锁定 / 解锁

    @objc func requestLock() {
        debugLog("requestLock，安全输入=\(IsSecureEventInputEnabled())，已授权=\(InputBlocker.shared.isTrusted(prompt: false))")
        if InputBlocker.shared.isLocked { return }
        if IsSecureEventInputEnabled() {
            showError("暂时无法锁定：当前有密码框处于“安全输入”状态（焦点在密码框里）。\n请先点一下桌面或其他区域，再重新锁定。")
            return
        }
        if !InputBlocker.shared.isTrusted(prompt: true) {
            showPermissionAlert()
            return
        }
        InputBlocker.shared.beginLocking()
    }

    @objc private func requestUnlock() {
        InputBlocker.shared.endLocking()
    }

    private func applyState(_ locked: Bool) {
        if locked {
            overlay.show(comboText: InputBlocker.shared.combo.displayText)
            scheduleAutoUnlock()
        } else {
            overlay.hide()
            autoUnlockTimer?.invalidate()
            autoUnlockTimer = nil
        }
        refreshMenu(locked)
    }

    /// --unlock-in N：锁定 N 秒后自动解锁（保险用法，可选）
    private func scheduleAutoUnlock() {
        autoUnlockTimer?.invalidate()
        guard let seconds = CLI.unlockInSeconds else { return }
        autoUnlockTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            InputBlocker.shared.endLocking()
        }
    }

    // MARK: 提示

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "键盘清洁锁 KeyboardCleaner"
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "需要「辅助功能」权限 Accessibility permission required"
        alert.informativeText = """
        打开 系统设置 → 隐私与安全性 → 辅助功能，勾选「Keyboard Cleaner」后重试。\n
        System Settings → Privacy & Security → Accessibility, enable "Keyboard Cleaner" and retry.
        """
        alert.addButton(withTitle: "打开系统设置 Open Settings")
        alert.addButton(withTitle: "稍后 Later")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - 自检模式（--check，不进入 GUI）

func runSelfTest() -> Never {
    let trusted = InputBlocker.shared.isTrusted(prompt: false)
    print("辅助功能权限: \(trusted ? "✅ 已授权" : "❌ 未授权")")
    print("安全输入状态: \(IsSecureEventInputEnabled() ? "开启（密码框聚焦中）" : "关闭")")
    if !trusted {
        print("→ 请打开 系统设置 → 隐私与安全性 → 辅助功能，添加并勾选 Keyboard Cleaner 后重试")
        exit(1)
    }
    var tapOK = false
    let semaphore = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        let callback: CGEventTapCallBack = { _, _, _, _ in nil }
        // 只订阅几乎不会发生的“数位板悬停”事件来验证能否创建拦截型 tap，
        // 不会吞掉任何真实输入
        if let probe = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                        place: .headInsertEventTap,
                                        options: .defaultTap,
                                        eventsOfInterest: CGEventMask(1 << 24), // kCGEventTabletProximity，几乎不会发生
                                        callback: callback,
                                        userInfo: nil) {
            CFMachPortInvalidate(probe)
            tapOK = true
        }
        semaphore.signal()
    }
    semaphore.wait()
    print("事件拦截能力: \(tapOK ? "✅ 正常" : "❌ 创建失败")")
    exit(tapOK ? 0 : 1)
}

let usage = """
键盘清洁锁 — 擦键盘时锁住所有输入

用法:
  KeyboardCleaner                  正常启动（菜单栏图标）
  KeyboardCleaner --lock           启动后立即锁定
  KeyboardCleaner --lock --unlock-in 300   锁定 300 秒后自动解锁（保险用法）
  KeyboardCleaner --check          自检：权限与拦截能力
  KeyboardCleaner --key q --mods ctrl,shift   自定义解锁组合键（默认 ⌥⌘+Esc）

也可用 defaults 持久化自定义组合键（改完重启 app 生效）:
  defaults write local.zhao.keyboardcleaner unlockKey q
  defaults write local.zhao.keyboardcleaner unlockMods "ctrl,shift"
"""

// MARK: - 入口

if CommandLine.arguments.contains("--check") { runSelfTest() }

if CommandLine.arguments.contains("--help") || CommandLine.arguments.contains("-h") {
    print(usage)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory) // 菜单栏应用，不占 Dock
app.run()
