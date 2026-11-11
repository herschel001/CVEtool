import AppKit
import CVEtoolCore

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private var recordingShortcut: ShortcutKind?

    private let launchSwitch = NSSwitch()
    private let capacityControl = NSSegmentedControl()
    private let usedLabel = NSTextField(labelWithString: "")
    private let screenLabel = NSTextField(labelWithString: "")
    private let accessLabel = NSTextField(labelWithString: "")
    private var shortcutButtons: [ShortcutKind: NSButton] = [:]
    private var shortcutMonitor: Any?

    private init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 460), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "设置"
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContent()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .capacityDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .historyDidChange, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    func show() {
        refresh()
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeContent() -> NSView {
        let root = NSView()
        launchSwitch.target = self
        launchSwitch.action = #selector(launchChanged)
        capacityControl.segmentCount = CapacityPolicy.choicesMB.count
        for (index, value) in CapacityPolicy.choicesMB.enumerated() {
            capacityControl.setLabel(value == 1024 ? "1 GB" : "\(value)", forSegment: index)
            capacityControl.setWidth(value == 1024 ? 52 : 42, forSegment: index)
        }
        capacityControl.target = self
        capacityControl.action = #selector(capacityChanged)
        var rows: [NSView] = []
        rows.append(section("通用"))
        rows.append(labeled("开机时启动", launchSwitch))
        rows.append(section("快捷键 · 点右侧按钮后按下新组合"))
        for kind in ShortcutKind.allCases {
            let button = NSButton(title: SettingsStore.shared.shortcut(for: kind).display, target: self, action: #selector(recordShortcut(_:)))
            button.identifier = NSUserInterfaceItemIdentifier(kind.rawValue)
            button.bezelStyle = .rounded
            button.toolTip = "点这里，然后按下新的快捷键"
            let name = NSTextField(labelWithString: kind.title)
            name.font = .systemFont(ofSize: 13)
            let row = NSStackView(views: [name, button])
            row.orientation = .horizontal
            row.distribution = .fill
            row.widthAnchor.constraint(equalToConstant: 460).isActive = true
            rows.append(row)
            objc_setAssociatedObject(button, &shortcutButtonKey, kind.rawValue, .OBJC_ASSOCIATION_RETAIN)
            shortcutButtons[kind] = button
        }
        rows.append(section("存储"))
        rows.append(labeled("最大占用", capacityControl))
        rows.append(usedLabel)
        let help = NSTextField(wrappingLabelWithString: "超过上限后，按时间从最早的条目开始删除，腾出足够空间再放入新的。单条大于上限时不写入。")
        help.font = .systemFont(ofSize: 12)
        help.textColor = .secondaryLabelColor
        rows.append(help)
        rows.append(section("权限 · 点「去授权」直接打开系统设置"))
        rows.append(permissionRow("屏幕录制", screenLabel, action: #selector(openScreenRecording)))
        rows.append(permissionRow("辅助功能", accessLabel, action: #selector(openAccessibility)))
        let hint = NSTextField(labelWithString: "辅助功能授予后，选中历史会自动粘贴到当前 App")
        hint.font = .systemFont(ofSize: 12)
        hint.textColor = .secondaryLabelColor
        rows.append(hint)

        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
        ])
        return root
    }

    private func section(_ title: String) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.distribution = .fill
        row.widthAnchor.constraint(equalToConstant: 420).isActive = true
        return row
    }

    @objc private func refresh() {
        launchSwitch.state = SettingsStore.shared.launchAtLogin ? .on : .off
        if let index = CapacityPolicy.choicesMB.firstIndex(of: SettingsStore.shared.capacityMB) {
            capacityControl.selectedSegment = index
        }
        let used = HistoryPanelController.shared.store?.usedBytes() ?? 0
        let mb = Double(used) / 1024 / 1024
        usedLabel.stringValue = String(format: "已用 %.1f MB，上限 %d MB", mb, SettingsStore.shared.capacityMB == 1024 ? 1024 : SettingsStore.shared.capacityMB)
        screenLabel.stringValue = PermissionService.screenRecordingGranted ? "已授权" : "未授权，打开后需退出重开"
        screenLabel.textColor = PermissionService.screenRecordingGranted ? .systemGreen : .systemOrange
        accessLabel.stringValue = PermissionService.accessibilityGranted ? "已授权" : "未授权"
        accessLabel.textColor = PermissionService.accessibilityGranted ? .systemGreen : .systemOrange
        for kind in ShortcutKind.allCases {
            shortcutButtons[kind]?.title = SettingsStore.shared.shortcut(for: kind).display
        }
    }

    @objc private func launchChanged() {
        SettingsStore.shared.launchAtLogin = launchSwitch.state == .on
    }

    @objc private func capacityChanged() {
        let index = capacityControl.selectedSegment
        guard CapacityPolicy.choicesMB.indices.contains(index) else { return }
        let previous = SettingsStore.shared.capacityMB
        let next = CapacityPolicy.choicesMB[index]
        SettingsStore.shared.capacityMB = next
        if next < previous {
            HistoryPanelController.shared.store?.shrink(to: SettingsStore.shared.capacityBytes)
            NotificationCenter.default.post(name: .historyDidChange, object: nil)
        }
        refresh()
    }

    @objc private func openScreenRecording() {
        PermissionService.promptScreenRecording()
    }

    @objc private func openAccessibility() {
        PermissionService.requestAccessibility()
        PermissionService.openPrivacy("Accessibility")
    }

    private func permissionRow(_ title: String, _ status: NSTextField, action: Selector) -> NSView {
        let name = NSTextField(labelWithString: title)
        let button = NSButton(title: "去授权", target: self, action: action)
        button.bezelStyle = .rounded
        let row = NSStackView(views: [name, status, button])
        row.orientation = .horizontal
        row.spacing = 8
        return row
    }

    @objc private func recordShortcut(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let kind = ShortcutKind(rawValue: raw) else { return }
        recordingShortcut = kind
        sender.title = "请按键"
        window?.makeFirstResponder(nil)
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.recordingShortcut == kind else { return event }
            self.finishRecording(kind, event: event)
            return nil
        }
    }

    private func finishRecording(_ kind: ShortcutKind, event: NSEvent) {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        recordingShortcut = nil
        if event.keyCode == 53 {
            refresh()
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.control) || flags.contains(.option) else {
            Toast.show("需要带 ⌘、⌥ 或 ⌃")
            refresh()
            return
        }
        let characters = event.charactersIgnoringModifiers ?? ""
        let shortcut = Shortcut(keyCode: UInt32(event.keyCode), modifiers: Shortcut.carbonModifiers(from: flags), characters: characters.isEmpty ? "?" : characters)
        if SettingsStore.isReservedBySystem(shortcut) {
            Toast.show("这个快捷键不能用")
            refresh()
            return
        }
        SettingsStore.shared.setShortcut(shortcut, for: kind)
        HotkeyCenter.shared.register(id: kind.hotkeyID, shortcut: shortcut) { AppDelegate.shared?.perform(kind) }
        refresh()
    }
}

private var shortcutButtonKey: UInt8 = 0
