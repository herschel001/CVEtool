import AppKit
import CVEtoolCore

final class CaptureToolbar: NSView {
    enum Action {
        case tool(AnnotationStroke.Kind)
        case undo, redo, copy, save, pin, discard
    }

    static let accent = NSColor(srgbRed: 7 / 255, green: 193 / 255, blue: 96 / 255, alpha: 1)
    static let palette: [(String, NSColor)] = [
        ("红", NSColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1)),
        ("蓝", NSColor(srgbRed: 0, green: 0.48, blue: 1, alpha: 1)),
        ("黑", .black),
        ("黄", NSColor(srgbRed: 1, green: 0.84, blue: 0.04, alpha: 1)),
        ("白", .white),
    ]

    private static let tools: [(String, String, AnnotationStroke.Kind)] = [
        ("rectangle", "矩形", .rect),
        ("circle", "椭圆", .ellipse),
        ("arrow.up.right", "箭头", .arrow),
        ("highlighter", "高亮", .highlight),
        ("square.grid.3x3.fill", "马赛克", .mosaic),
        ("t.square", "文字", .text),
    ]

    private let onAction: (Action) -> Void
    private let onColorChange: (NSColor) -> Void
    private let onMosaicChange: (CGFloat) -> Void
    private var toolButtons: [CaptureToolbarButton] = []
    private var colorButtons: [CaptureColorButton] = []
    private let optionsRow = NSStackView()
    private let colorRow = NSStackView()
    private let mosaicRow = NSStackView()
    private let mosaicSlider = NSSlider()
    private var undoButton: CaptureToolbarButton!
    private var redoButton: CaptureToolbarButton!

    init(onAction: @escaping (Action) -> Void, onColorChange: @escaping (NSColor) -> Void, onMosaicChange: @escaping (CGFloat) -> Void) {
        self.onAction = onAction
        self.onColorChange = onColorChange
        self.onMosaicChange = onMosaicChange
        super.init(frame: .zero)
        appearance = NSAppearance(named: .aqua)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.cornerRadius = 8
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.black.withAlphaComponent(0.12).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -3)

        let mainRow = NSStackView()
        mainRow.orientation = .horizontal
        mainRow.alignment = .centerY
        mainRow.spacing = 4
        mainRow.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        for (index, entry) in Self.tools.enumerated() {
            let button = makeButton(entry.0, title: entry.1, action: #selector(toolClicked(_:)))
            button.tag = index
            toolButtons.append(button)
            mainRow.addArrangedSubview(button)
        }
        mainRow.addArrangedSubview(separator())
        undoButton = makeButton("arrow.uturn.backward", title: "撤销", action: #selector(undoClicked))
        redoButton = makeButton("arrow.uturn.forward", title: "重做", action: #selector(redoClicked))
        mainRow.addArrangedSubview(undoButton)
        mainRow.addArrangedSubview(redoButton)
        mainRow.addArrangedSubview(makeButton("square.and.arrow.down", title: "保存", action: #selector(saveClicked)))
        mainRow.addArrangedSubview(makeButton("pin", title: "钉住", action: #selector(pinClicked)))
        mainRow.addArrangedSubview(separator())
        mainRow.addArrangedSubview(makeButton("xmark", title: "取消截图", action: #selector(discardClicked), tint: NSColor(srgbRed: 250 / 255, green: 81 / 255, blue: 81 / 255, alpha: 1)))
        mainRow.addArrangedSubview(makeButton("checkmark", title: "完成并复制", action: #selector(copyClicked), tint: Self.accent))

        buildOptions()
        let column = NSStackView(views: [mainRow, optionsRow])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 0
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        update(tool: nil, canUndo: false, canRedo: false, color: Self.palette[1].1, mosaicBlock: 18)
    }

    required init?(coder: NSCoder) { nil }

    func update(tool: AnnotationStroke.Kind?, canUndo: Bool, canRedo: Bool, color: NSColor, mosaicBlock: CGFloat) {
        for (index, button) in toolButtons.enumerated() {
            button.isSelectedTool = Self.tools[index].2 == tool
        }
        undoButton.isEnabled = canUndo
        redoButton.isEnabled = canRedo
        optionsRow.isHidden = tool == nil
        colorRow.isHidden = tool == .mosaic
        mosaicRow.isHidden = tool != .mosaic
        for (index, button) in colorButtons.enumerated() {
            button.isSelectedColor = Self.palette[index].1 == color
        }
        mosaicSlider.doubleValue = Double(mosaicBlock)
    }

    private func makeButton(_ symbol: String, title: String, action: Selector, tint: NSColor? = nil) -> CaptureToolbarButton {
        let button = CaptureToolbarButton()
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.actionColor = tint
        button.target = self
        button.action = action
        button.toolTip = title
        button.setAccessibilityLabel(title)
        button.setButtonType(.momentaryPushIn)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 40),
            button.heightAnchor.constraint(equalToConstant: 40),
        ])
        return button
    }

    private func buildOptions() {
        optionsRow.orientation = .horizontal
        optionsRow.alignment = .centerY
        optionsRow.spacing = 12
        optionsRow.edgeInsets = NSEdgeInsets(top: 2, left: 10, bottom: 8, right: 10)
        optionsRow.heightAnchor.constraint(equalToConstant: 34).isActive = true
        colorRow.orientation = .horizontal
        colorRow.spacing = 5
        for (index, entry) in Self.palette.enumerated() {
            let button = CaptureColorButton(color: entry.1)
            button.tag = index
            button.target = self
            button.action = #selector(colorClicked(_:))
            button.toolTip = entry.0
            button.setAccessibilityLabel("颜色：\(entry.0)")
            colorButtons.append(button)
            colorRow.addArrangedSubview(button)
        }
        mosaicSlider.minValue = 8
        mosaicSlider.maxValue = 72
        mosaicSlider.isContinuous = true
        mosaicSlider.controlSize = .small
        mosaicSlider.target = self
        mosaicSlider.action = #selector(mosaicChanged(_:))
        mosaicSlider.toolTip = "马赛克画笔大小"
        mosaicSlider.setAccessibilityLabel("马赛克画笔大小")
        mosaicSlider.translatesAutoresizingMaskIntoConstraints = false
        mosaicSlider.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let label = NSTextField(labelWithString: "大小")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        mosaicRow.orientation = .horizontal
        mosaicRow.alignment = .centerY
        mosaicRow.spacing = 8
        mosaicRow.addArrangedSubview(label)
        mosaicRow.addArrangedSubview(mosaicSlider)
        optionsRow.addArrangedSubview(colorRow)
        optionsRow.addArrangedSubview(mosaicRow)
    }

    private func separator() -> NSView {
        let view = NSBox()
        view.boxType = .separator
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: 1),
            view.heightAnchor.constraint(equalToConstant: 40),
        ])
        return view
    }

    @objc private func toolClicked(_ sender: NSButton) { onAction(.tool(Self.tools[sender.tag].2)) }
    @objc private func colorClicked(_ sender: NSButton) { onColorChange(Self.palette[sender.tag].1) }
    @objc private func mosaicChanged(_ sender: NSSlider) { onMosaicChange(CGFloat(sender.doubleValue)) }
    @objc private func undoClicked() { onAction(.undo) }
    @objc private func redoClicked() { onAction(.redo) }
    @objc private func copyClicked() { onAction(.copy) }
    @objc private func saveClicked() { onAction(.save) }
    @objc private func pinClicked() { onAction(.pin) }
    @objc private func discardClicked() { onAction(.discard) }
}

private final class CaptureToolbarButton: NSButton {
    var isSelectedTool = false { didSet { needsDisplay = true } }
    var actionColor: NSColor?
    private var isHovered = false

    override var acceptsFirstResponder: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        if isSelectedTool {
            CaptureToolbar.accent.withAlphaComponent(0.12).setFill()
        } else {
            NSColor.black.withAlphaComponent(isEnabled && (isHovered || isHighlighted) ? 0.06 : 0).setFill()
        }
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 4, yRadius: 4).fill()
        contentTintColor = actionColor ?? (isSelectedTool ? CaptureToolbar.accent : NSColor(calibratedWhite: 0.3, alpha: 1))
        super.draw(dirtyRect)
    }
}

private final class CaptureColorButton: NSButton {
    let color: NSColor
    var isSelectedColor = false { didSet { needsDisplay = true } }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryPushIn)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 22),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        let swatch = NSBezierPath(ovalIn: bounds.insetBy(dx: 5, dy: 5))
        swatch.fill()
        NSColor.black.withAlphaComponent(0.16).setStroke()
        swatch.lineWidth = 0.5
        swatch.stroke()
        if isSelectedColor {
            CaptureToolbar.accent.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 1.5, dy: 1.5))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }
}
