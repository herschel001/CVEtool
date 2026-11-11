import AppKit
import CVEtoolCore

final class HistoryPanelController {
    static let shared = HistoryPanelController()

    private let panel = KeyableHistoryPanel(
        contentRect: NSRect(x: 0, y: 0, width: 860, height: 108),
        styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
        backing: .buffered,
        defer: false
    )
    private var catchers: [NSWindow] = []
    private let bar = HistoryBarView()
    private var preview: NSPanel?
    private var previousApp: NSRunningApplication?
    private var visible = false

    var isVisible: Bool { visible }
    var store: HistoryStore?

    private init() {
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = bar
        bar.onSelect = { [weak self] item in self?.select(item) }
        bar.onUsage = { SettingsWindowController.shared.show() }
        bar.onHoverImage = { [weak self] item, rect in self?.showPreview(item, near: rect) }
        bar.onEndHover = { [weak self] in self?.preview?.orderOut(nil) }
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .historyDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .capacityDidChange, object: nil)
    }

    func toggle() {
        visible ? hide() : show()
    }

    func show() {
        guard let store else { return }
        if CaptureController.shared.isActive { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let screen = screenUnderMouse()
        layout(on: screen)
        installCatchers(except: screen)
        bar.reload(store: store, capacityMB: SettingsStore.shared.capacityMB)
        panel.orderFrontRegardless()
        visible = true
        if let query = ProcessInfo.processInfo.environment["CVETOOL_SEARCH"], !query.isEmpty {
            focusSearch(query)
        }
    }

    func focusSearch(_ text: String? = nil) {
        panel.makeKey()
        panel.makeFirstResponder(bar.searchField)
        if let text {
            bar.searchField.stringValue = text
            bar.reloadCurrent()
        }
    }

    var panelFrame: NSRect { panel.frame }

    func hide() {
        visible = false
        preview?.orderOut(nil)
        panel.orderOut(nil)
        catchers.forEach { $0.orderOut(nil) }
        catchers.removeAll()
        bar.searchField.stringValue = ""
        NSApp.deactivate()
    }

    @objc private func reload() {
        guard visible, let store else { return }
        bar.reload(store: store, capacityMB: SettingsStore.shared.capacityMB)
    }

    private func select(_ item: HistoryItem) {
        guard let store else { return }
        let app = previousApp
        hide()
        PasteService.paste(item, store: store, to: app)
    }

    private func showPreview(_ item: HistoryItem, near rect: NSRect) {
        guard let store, let data = store.imageData(for: item), let image = NSImage(data: data) else { return }
        let panel = preview ?? NSPanel(contentRect: NSRect(x: 0, y: 0, width: 260, height: 180), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.isOpaque = false
        let view = NSImageView(frame: NSRect(x: 8, y: 28, width: 244, height: 144))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(labelWithString: Self.caption(item))
        label.frame = NSRect(x: 8, y: 6, width: 244, height: 18)
        label.font = .systemFont(ofSize: 11)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 180))
        content.addSubview(view)
        content.addSubview(label)
        panel.contentView = content
        let screenRect = self.panel.convertToScreen(rect)
        panel.setFrameOrigin(NSPoint(x: screenRect.minX, y: screenRect.maxY + 8))
        panel.orderFrontRegardless()
        preview = panel
    }

    private func layout(on screen: NSScreen) {
        let frame = screen.visibleFrame
        let width = max(640, frame.width - 32)
        let height: CGFloat = 108
        panel.setFrame(NSRect(x: frame.midX - width / 2, y: frame.minY + 12, width: width, height: height), display: true)
    }

    private func installCatchers(except screen: NSScreen) {
        catchers.forEach { $0.orderOut(nil) }
        catchers.removeAll()
        for candidate in NSScreen.screens {
            let catcher = ClickCatcher(owner: self)
            catcher.setFrame(candidate.frame, display: false)
            catcher.level = NSWindow.Level(rawValue: panel.level.rawValue - 1)
            catcher.orderFrontRegardless()
            catchers.append(catcher)
        }
        _ = screen
    }

    fileprivate func caughtClickOutside() {
        hide()
    }

    private func screenUnderMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private static func caption(_ item: HistoryItem) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        let kind = item.isScreenshot ? "截图" : item.kind.title
        return "\(formatter.string(from: item.createdAt)) · \(kind)"
    }
}

private extension ItemKind {
    var title: String {
        switch self {
        case .text: return "文本"
        case .image: return "图片"
        case .link: return "链接"
        case .color: return "颜色"
        case .screenshot: return "截图"
        }
    }
}

private final class ClickableSearchField: NSSearchField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

private final class KeyableHistoryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class ClickCatcher: NSWindow {
    weak var owner: HistoryPanelController?
    init(owner: HistoryPanelController) {
        self.owner = owner
        super.init(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hasShadow = false
    }
    override var canBecomeKey: Bool { false }
    override func mouseDown(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        if let frame = owner?.panelFrame, frame.insetBy(dx: -8, dy: -8).contains(point) { return }
        owner?.caughtClickOutside()
    }
}

final class HistoryBarView: NSView, NSSearchFieldDelegate {
    var onSelect: ((HistoryItem) -> Void)?
    var onUsage: (() -> Void)?
    var onHoverImage: ((HistoryItem, NSRect) -> Void)?
    var onEndHover: (() -> Void)?
    fileprivate let searchField = ClickableSearchField()
    private var filter: HistoryFilter = .all
    private var store: HistoryStore?
    private var capacityMB = 200
    private let filterColumn = NSStackView()
    private let scroller = NSScrollView()
    private let row = NSStackView()
    private let usageButton = NSButton()
    private let emptyLabel = NSTextField(labelWithString: "还没有历史")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.97).cgColor
        layer?.cornerRadius = 14
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor

        filterColumn.orientation = .vertical
        filterColumn.spacing = 2
        filterColumn.translatesAutoresizingMaskIntoConstraints = false
        addSubview(filterColumn)
        rebuildFilters()

        row.orientation = .horizontal
        row.spacing = 8
        row.alignment = .centerY
        row.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
        let document = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(row)
        scroller.documentView = document
        scroller.hasVerticalScroller = false
        scroller.hasHorizontalScroller = false
        scroller.autohidesScrollers = true
        scroller.scrollerStyle = .overlay
        scroller.drawsBackground = false
        scroller.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroller)

        usageButton.isBordered = false
        usageButton.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        usageButton.target = self
        usageButton.action = #selector(usageClicked)
        usageButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(usageButton)

        searchField.placeholderString = "搜索历史"
        searchField.delegate = self
        searchField.isEditable = true
        searchField.isSelectable = true
        searchField.refusesFirstResponder = false
        searchField.focusRingType = .default
        searchField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(searchField)

        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            filterColumn.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            filterColumn.centerYAnchor.constraint(equalTo: centerYAnchor),
            filterColumn.widthAnchor.constraint(equalToConstant: 92),
            scroller.leadingAnchor.constraint(equalTo: filterColumn.trailingAnchor, constant: 8),
            scroller.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            scroller.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            usageButton.leadingAnchor.constraint(equalTo: scroller.trailingAnchor, constant: 8),
            usageButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            usageButton.widthAnchor.constraint(equalToConstant: 92),
            searchField.leadingAnchor.constraint(equalTo: usageButton.trailingAnchor, constant: 8),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            searchField.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(equalToConstant: 148),
            searchField.heightAnchor.constraint(equalToConstant: 26),
            emptyLabel.centerXAnchor.constraint(equalTo: scroller.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scroller.centerYAnchor),
            row.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            row.topAnchor.constraint(equalTo: document.topAnchor),
            row.bottomAnchor.constraint(equalTo: document.bottomAnchor),
            row.heightAnchor.constraint(equalToConstant: 72),
        ])
    }

    required init?(coder: NSCoder) { nil }

    func reload(store: HistoryStore, capacityMB: Int) {
        self.store = store
        self.capacityMB = capacityMB
        let used = store.usedBytes()
        usageButton.title = Self.usageTitle(bytes: used, capacityMB: capacityMB)
        let items = store.filtered(filter, query: searchField.stringValue)
        row.arrangedSubviews.forEach {
            row.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        emptyLabel.isHidden = !items.isEmpty
        let contentWidth = row.fittingSize.width
        scroller.hasHorizontalScroller = items.count > 1 && contentWidth > scroller.bounds.width + 8
        emptyLabel.stringValue = store.snapshot().isEmpty ? "还没有历史" : "没有匹配的内容"
        for item in items {
            let card = HistoryCard(item: item, image: item.imageFilename.flatMap { _ in store.imageData(for: item) }.flatMap(NSImage.init(data:)))
            card.onClick = { [weak self] in self?.onSelect?(item) }
            card.onHover = { [weak self, weak card] inside in
                guard let self, let card else { return }
                if inside, item.imageFilename != nil {
                    self.onHoverImage?(item, card.convert(card.bounds, to: nil))
                } else {
                    self.onEndHover?()
                }
            }
            row.addArrangedSubview(card)
        }
        let width = row.fittingSize.width
        scroller.documentView?.frame.size = NSSize(width: max(width, scroller.contentSize.width), height: 72)
    }

    func controlTextDidChange(_ obj: Notification) { reloadCurrent() }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if searchField.frame.insetBy(dx: -6, dy: -8).contains(point) {
            window?.makeKey()
            window?.makeFirstResponder(searchField)
            return
        }
        super.mouseDown(with: event)
    }

    func reloadCurrent() {
        guard let store else { return }
        reload(store: store, capacityMB: capacityMB)
    }

    @objc private func usageClicked() { onUsage?() }

    private func rebuildFilters() {
        filterColumn.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let titles = HistoryFilter.allCases
        for index in stride(from: 0, to: titles.count, by: 2) {
            let line = NSStackView()
            line.orientation = .horizontal
            line.spacing = 4
            line.addArrangedSubview(filterButton(titles[index]))
            if index + 1 < titles.count { line.addArrangedSubview(filterButton(titles[index + 1])) }
            filterColumn.addArrangedSubview(line)
        }
    }

    private func filterButton(_ filter: HistoryFilter) -> NSButton {
        let button = NSButton(title: filter.title, target: self, action: #selector(filterClicked(_:)))
        button.identifier = NSUserInterfaceItemIdentifier(filter.rawValue)
        button.isBordered = false
        button.font = .systemFont(ofSize: 11, weight: filter == self.filter ? .semibold : .regular)
        button.contentTintColor = filter == self.filter ? .labelColor : .secondaryLabelColor
        button.setButtonType(.momentaryChange)
        return button
    }

    @objc private func filterClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let next = HistoryFilter(rawValue: raw) else { return }
        filter = next
        rebuildFilters()
        reloadCurrent()
    }

    private static func usageTitle(bytes: Int64, capacityMB: Int) -> String {
        let used = Int((Double(bytes) / 1024 / 1024).rounded())
        let cap = capacityMB == 1024 ? "1GB" : "\(capacityMB)MB"
        return "\(used)/\(cap)"
    }
}

final class HistoryCard: NSView {
    let item: HistoryItem
    var onClick: (() -> Void)?
    var onHover: ((Bool) -> Void)?
    private let image: NSImage?

    init(item: HistoryItem, image: NSImage?) {
        self.item = item
        self.image = image
        let width: CGFloat = image == nil && item.kind != .color ? 168 : (item.kind == .color ? 72 : 96)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 64))
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.cgColor
        widthAnchor.constraint(equalToConstant: width).isActive = true
        heightAnchor.constraint(equalToConstant: 64).isActive = true
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        if let image {
            image.draw(in: bounds.insetBy(dx: 4, dy: 4))
            return
        }
        if item.kind == .color, let text = item.text {
            let swatch = NSColor(fromHex: text) ?? .systemGreen
            swatch.setFill()
            NSBezierPath(rect: NSRect(x: 0, y: 16, width: bounds.width, height: bounds.height - 16)).fill()
            let hex = NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.secondaryLabelColor])
            hex.draw(at: NSPoint(x: 6, y: 2))
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let text = NSAttributedString(string: item.text ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: item.kind == .link ? NSColor.controlAccentColor : NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        text.draw(in: bounds.insetBy(dx: 8, dy: 8))
    }

    override func mouseDown(with event: NSEvent) { onClick?() }
    override func mouseEntered(with event: NSEvent) { onHover?(true) }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
}

private extension NSColor {
    convenience init?(fromHex raw: String) {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255
        let g = CGFloat((value >> 8) & 0xFF) / 255
        let b = CGFloat(value & 0xFF) / 255
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
