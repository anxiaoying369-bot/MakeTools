import AppKit

public final class DynamicIslandTool: ToolModule {
    public let id = "dynamic-island"
    public let title = L10n.text("island.dynamicIsland", "系统灵动岛")
    public let subtitle = L10n.text("island.floatingControlsAndLiveSystemStatus", "顶部悬浮中控与实时状态")
    public let symbolName = "rectangle.topthird.inset.filled"

    public init() {}

    public func makeViewController() -> NSViewController {
        DynamicIslandViewController()
    }
}

private final class FlippedIslandSettingsContainer: NSView {
    override var isFlipped: Bool { true }
}

public final class DynamicIslandViewController: NSViewController, NSTextFieldDelegate, NSMenuDelegate {
    private let pages = NSSegmentedControl(
        labels: [L10n.text("island.shortcuts", "快捷操作"),
                 L10n.text("island.appearanceAndInteraction", "外观与交互"),
                 L10n.text("island.features", "功能模块")],
        trackingMode: .selectOne, target: nil, action: nil
    )
    private var pageSections: [[NSView]] = []
    private var updateObserver: NSObjectProtocol?

    private let enabledSwitch = NSSwitch()
    private let hoverSwitch = NSSwitch()
    private let dragExpandSwitch = NSSwitch()
    private let customTitleSwitch = NSSwitch()
    private let customTitleField = NSTextField(string: "")
    private let collapsedWidthSlider = NSSlider(value: 340, minValue: 160, maxValue: 680, target: nil, action: nil)
    private let collapsedWidthValueLabel = NSTextField(labelWithString: L10n.text("island.automatic.203", "自动"))
    private let collapsedWidthAutoButton = NSButton(title: L10n.text("island.automatic", "自动适配"), target: nil, action: nil)
    private let collapsedPreviewLabel = NSTextField(wrappingLabelWithString: "")
    private var collapsedMetricCheckboxes: [CollapsedMetricItem: NSButton] = [:]
    private var featureSwitches: [DynamicIslandFeature: NSSwitch] = [:]
    private let materialPicker = NSPopUpButton()
    private var materialMenuTracking = false
    private let styleSegmented = NSSegmentedControl(
        labels: DynamicIslandStyle.allCases.map(\.displayTitle),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    private let expandedOrderLabel = NSTextField(wrappingLabelWithString: "")

    private let telemetryLabel = NSTextField(wrappingLabelWithString: "")
    private var focusControls: [NSButton] = []
    private let timerDisplayLabel = NSTextField(labelWithString: "25:00")
    private let timerToggleButton = NSButton(title: L10n.text("island.startFocus", "开始专注"), target: nil, action: nil)
    private let keepAwakeQuickButton = NSButton(title: L10n.text("island.keepAwake.208", "开启防休眠"), target: nil, action: nil)

    public override var nibName: NSNib.Name? { nil }

    deinit {
        if let updateObserver {
            NotificationCenter.default.removeObserver(updateObserver)
        }
    }

    public override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        let container = FlippedIslandSettingsContainer()
        container.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 30, left: 32, bottom: 36, right: 32)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let header = ToolAppearance.header(
            title: L10n.text("island.dynamicIsland", "系统灵动岛"),
            subtitle: L10n.text("island.customizeTheFloatingPanelAtTheTop", "自定义屏幕顶部的悬浮控制中心，管理实时指标、快捷操作和功能模块。"),
            symbol: "rectangle.topthird.inset.filled"
        )

        let controlCard = buildControlCard()
        let expandedLayoutCard = buildExpandedLayoutCard()
        let collapsedDisplayCard = buildCollapsedDisplayCard()
        let featuresCard = buildFeaturesCard()
        let appearanceCard = buildAppearanceCard()
        let timerCard = buildTimerAndGuideCard()

        pageSections = [[controlCard, timerCard], [appearanceCard, expandedLayoutCard, collapsedDisplayCard], [featuresCard]]
        pages.target = self
        pages.action = #selector(showSelectedPage)
        pages.selectedSegment = 0
        pages.segmentDistribution = .fillEqually

        for item in [header, pages] + pageSections.flatMap({ $0 }) {
            stack.addArrangedSubview(item)
            item.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -64).isActive = true
        }
        stack.setCustomSpacing(16, after: header)
        stack.setCustomSpacing(18, after: pages)
        showSelectedPage()

        container.addSubview(stack)
        scrollView.documentView = container

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            container.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            container.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor)
        ])

        self.view = scrollView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        syncFromManager()
        updateObserver = NotificationCenter.default.addObserver(
            forName: DynamicIslandManager.didUpdateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncFromManager()
        }
    }

    @objc private func showSelectedPage() {
        for (index, sections) in pageSections.enumerated() {
            for section in sections { section.isHidden = index != pages.selectedSegment }
        }
    }

    // MARK: - Card Builders

    private func makeSettingsCard(title: String, symbol: String, views: [NSView]) -> NSView {
        let card = ToolSurfaceView()
        card.translatesAutoresizingMaskIntoConstraints = false

        let inner = NSStackView()
        inner.orientation = .vertical
        inner.alignment = .leading
        inner.spacing = 12
        inner.translatesAutoresizingMaskIntoConstraints = false

        let header = ToolAppearance.sectionTitle(title, symbol: symbol)
        inner.addArrangedSubview(header)
        header.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true

        for view in views {
            inner.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }

        card.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            inner.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            inner.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            inner.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18)
        ])
        return card
    }

    private func makeSwitchRow(title: String, toggle: NSSwitch, action: Selector) -> NSView {
        toggle.target = self
        toggle.action = action
        toggle.controlSize = .small
        toggle.setAccessibilityLabel(title)

        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.isSelectable = true

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [label, spacer, toggle])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func buildControlCard() -> NSView {
        let enableRow = makeSwitchRow(title: L10n.text("island.enableDynamicIsland", "启用系统灵动岛"), toggle: enabledSwitch, action: #selector(handleEnabledChanged(_:)))

        let toggleExpandBtn = NSButton(title: L10n.text("menu.expandOrCollapseDynamicIsland", "展开 / 收起灵动岛"), target: self, action: #selector(handleToggleExpand(_:)))
        ToolAppearance.configure(toggleExpandBtn, symbol: "arrow.up.and.down")

        let hudDemoBtn = NSButton(title: L10n.text("island.showDemoAlert", "发送灵动提示演示"), target: self, action: #selector(handleDemoHUD(_:)))
        ToolAppearance.configure(hudDemoBtn, symbol: "bell")

        let btnRow = NSStackView(views: [toggleExpandBtn, hudDemoBtn])
        btnRow.orientation = .horizontal
        btnRow.spacing = 10
        btnRow.translatesAutoresizingMaskIntoConstraints = false

        telemetryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        telemetryLabel.textColor = .secondaryLabelColor
        telemetryLabel.isSelectable = true
        telemetryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return makeSettingsCard(title: L10n.text("island.shortcuts", "快捷操作"), symbol: "power", views: [enableRow, btnRow, telemetryLabel])
    }

    private func buildExpandedLayoutCard() -> NSView {
        expandedOrderLabel.font = .systemFont(ofSize: 12)
        expandedOrderLabel.textColor = .secondaryLabelColor
        let edit = NSButton(title: L10n.text("island.layout.edit", "编辑布局…"), target: self, action: #selector(openLayoutEditor(_:)))
        ToolAppearance.configure(edit, symbol: "square.grid.2x2")
        let row = NSStackView(views: [edit, expandedOrderLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 12
        return makeSettingsCard(title: L10n.text("island.expandedPanelLayout.220", "展开面板布局"),
                                symbol: "rectangle.split.2x2", views: [row])
    }

    private func buildCollapsedDisplayCard() -> NSView {
        customTitleSwitch.target = self
        customTitleSwitch.action = #selector(handleCustomTitleSwitchChanged(_:))
        customTitleSwitch.controlSize = .small
        customTitleSwitch.setAccessibilityLabel(L10n.text("island.showCustomTextOnTheLeft", "显示左侧自定义文字"))

        let customLabel = NSTextField(labelWithString: L10n.text("island.showCustomTextOnTheLeft", "显示左侧自定义文字"))
        customLabel.font = .systemFont(ofSize: 13)
        customLabel.isSelectable = true

        customTitleField.placeholderString = L10n.text("island.enterCustomTextSuchAsMaketoolsOr", "输入自定义文案，如 MakeTools / 工作模式")
        customTitleField.font = .systemFont(ofSize: 12.5)
        customTitleField.delegate = self
        customTitleField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let customRow = NSStackView(views: [customLabel, customTitleField, spacer, customTitleSwitch])
        customRow.orientation = .horizontal
        customRow.alignment = .centerY
        customRow.spacing = 10
        customRow.translatesAutoresizingMaskIntoConstraints = false
        customTitleField.widthAnchor.constraint(greaterThanOrEqualToConstant: 144).isActive = true

        let metricsCaption = NSTextField(wrappingLabelWithString: L10n.text("island.chooseWhichLiveMetricsToShowMultiple", "选择要显示的实时指标。勾选多项时，每 3 秒轮播一项。"))
        metricsCaption.font = .systemFont(ofSize: 12)
        metricsCaption.textColor = .secondaryLabelColor
        metricsCaption.isSelectable = true
        metricsCaption.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        collapsedMetricCheckboxes.removeAll()
        let items = CollapsedMetricItem.allCases
        var gridRows: [[NSView]] = []
        for rowStart in stride(from: 0, to: items.count, by: 3) {
            var rowCells: [NSView] = []
            for offset in 0..<3 {
                let idx = rowStart + offset
                if idx < items.count {
                    let item = items[idx]
                    let checkbox = NSButton(
                        checkboxWithTitle: item.displayTitle,
                        target: self,
                        action: #selector(handleCollapsedMetricToggled(_:))
                    )
                    checkbox.tag = idx
                    checkbox.font = .systemFont(ofSize: 12.5)
                    collapsedMetricCheckboxes[item] = checkbox
                    rowCells.append(checkbox)
                } else {
                    rowCells.append(NSView())
                }
            }
            gridRows.append(rowCells)
        }

        let metricsGrid = NSGridView(views: gridRows)
        metricsGrid.rowSpacing = 8
        metricsGrid.columnSpacing = 24
        metricsGrid.xPlacement = .leading
        metricsGrid.yPlacement = .center
        metricsGrid.translatesAutoresizingMaskIntoConstraints = false

        let metricsRow = NSView()
        metricsRow.addSubview(metricsGrid)
        NSLayoutConstraint.activate([
            metricsGrid.leadingAnchor.constraint(equalTo: metricsRow.leadingAnchor),
            metricsGrid.trailingAnchor.constraint(lessThanOrEqualTo: metricsRow.trailingAnchor),
            metricsGrid.topAnchor.constraint(equalTo: metricsRow.topAnchor),
            metricsGrid.bottomAnchor.constraint(equalTo: metricsRow.bottomAnchor)
        ])

        collapsedWidthSlider.isContinuous = true
        collapsedWidthSlider.target = self
        collapsedWidthSlider.action = #selector(handleCollapsedWidthSliderChanged(_:))
        collapsedWidthSlider.controlSize = .small
        collapsedWidthSlider.setAccessibilityLabel(L10n.text("island.collapsedIslandWidth", "灵动岛收起长度"))
        collapsedWidthSlider.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let widthTitleLabel = NSTextField(labelWithString: L10n.text("island.collapsedIslandWidth", "灵动岛收起长度"))
        widthTitleLabel.font = .systemFont(ofSize: 13)
        widthTitleLabel.isSelectable = true

        collapsedWidthValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        collapsedWidthValueLabel.textColor = .secondaryLabelColor
        collapsedWidthValueLabel.alignment = .right
        collapsedWidthValueLabel.translatesAutoresizingMaskIntoConstraints = false
        collapsedWidthValueLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 82).isActive = true

        collapsedWidthAutoButton.bezelStyle = .rounded
        collapsedWidthAutoButton.controlSize = .small
        collapsedWidthAutoButton.target = self
        collapsedWidthAutoButton.action = #selector(handleCollapsedWidthAutoReset(_:))

        let widthRow = NSStackView(views: [widthTitleLabel, collapsedWidthSlider, collapsedWidthValueLabel, collapsedWidthAutoButton])
        widthRow.orientation = .horizontal
        widthRow.alignment = .centerY
        widthRow.spacing = 10
        widthRow.translatesAutoresizingMaskIntoConstraints = false
        collapsedWidthSlider.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true

        collapsedPreviewLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        collapsedPreviewLabel.textColor = .secondaryLabelColor
        collapsedPreviewLabel.isSelectable = true
        collapsedPreviewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return makeSettingsCard(
            title: L10n.text("island.collapsedDisplay", "收起时显示"),
            symbol: "rectangle.compress.vertical",
            views: [customRow, metricsCaption, metricsRow, widthRow, collapsedPreviewLabel]
        )
    }

    private func buildFeaturesCard() -> NSView {
        featureSwitches.removeAll()
        var rows: [NSView] = []

        for (index, feature) in DynamicIslandFeature.allCases.enumerated() {
            let icon = NSImageView()
            icon.image = NSImage(systemSymbolName: feature.symbolName, accessibilityDescription: feature.title)
            icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
            icon.contentTintColor = .controlAccentColor
            icon.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                icon.widthAnchor.constraint(equalToConstant: 20),
                icon.heightAnchor.constraint(equalToConstant: 20)
            ])

            let nameLabel = NSTextField(labelWithString: feature.title)
            nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
            nameLabel.isSelectable = true

            let descLabel = NSTextField(wrappingLabelWithString: feature.subtitle)
            descLabel.font = .systemFont(ofSize: 11.5)
            descLabel.textColor = .secondaryLabelColor
            descLabel.isSelectable = true
            descLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let textStack = NSStackView(views: [nameLabel, descLabel])
            textStack.orientation = .vertical
            textStack.alignment = .leading
            textStack.spacing = 2
            textStack.translatesAutoresizingMaskIntoConstraints = false
            descLabel.widthAnchor.constraint(equalTo: textStack.widthAnchor).isActive = true

            let toggle = NSSwitch()
            toggle.controlSize = .small
            toggle.setAccessibilityLabel(feature.title)
            toggle.tag = index
            toggle.target = self
            toggle.action = #selector(handleFeatureSwitchChanged(_:))
            toggle.setContentHuggingPriority(.required, for: .horizontal)
            featureSwitches[feature] = toggle

            let spacer = NSView()
            spacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
            let row = NSStackView(views: [icon, textStack, spacer, toggle])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 12
            row.translatesAutoresizingMaskIntoConstraints = false
            rows.append(row)

            if index < DynamicIslandFeature.allCases.count - 1 {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                rows.append(divider)
            }
        }

        return makeSettingsCard(title: L10n.text("island.features", "功能模块"), symbol: "square.grid.2x2", views: rows)
    }

    private func buildAppearanceCard() -> NSView {
        let styleLabel = NSTextField(labelWithString: L10n.text("island.displayStyle", "显示样式"))
        styleLabel.font = .systemFont(ofSize: 13)
        styleLabel.isSelectable = true

        styleSegmented.target = self
        styleSegmented.action = #selector(handleStyleChanged(_:))

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let styleRow = NSStackView(views: [styleLabel, spacer, styleSegmented])
        styleRow.orientation = .horizontal
        styleRow.alignment = .centerY
        styleRow.translatesAutoresizingMaskIntoConstraints = false

        let materialTitle = L10n.text("island.material.title", "外观材质")
        let materialLabel = NSTextField(labelWithString: materialTitle)
        materialLabel.font = .systemFont(ofSize: 13)
        materialPicker.addItems(withTitles: DynamicIslandMaterial.allCases.map(\.title))
        (materialPicker.cell as? NSPopUpButtonCell)?.altersStateOfSelectedItem = false
        materialPicker.menu?.delegate = self
        materialPicker.setAccessibilityLabel(materialTitle)
        materialPicker.target = self
        materialPicker.action = #selector(handleMaterialChanged(_:))
        let materialSpacer = NSView()
        materialSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let materialRow = NSStackView(views: [materialLabel, materialSpacer, materialPicker])
        materialRow.orientation = .horizontal
        materialRow.alignment = .centerY

        let hoverRow = makeSwitchRow(title: L10n.text("island.expandOnHoverAndCollapseWhenThe", "指针悬停时展开，移出时收起"), toggle: hoverSwitch, action: #selector(handleHoverChanged(_:)))
        let dragRow = makeSwitchRow(title: L10n.text("island.expandDynamicIslandWhenDraggingFiles", "拖动文件时展开灵动岛"), toggle: dragExpandSwitch, action: #selector(handleDragExpandChanged(_:)))

        return makeSettingsCard(title: L10n.text("island.appearanceAndInteraction", "外观与交互"), symbol: "slider.horizontal.3", views: [styleRow, materialRow, hoverRow, dragRow])
    }

    private func buildTimerAndGuideCard() -> NSView {
        timerDisplayLabel.font = .monospacedDigitSystemFont(ofSize: 28, weight: .semibold)
        timerDisplayLabel.isSelectable = true

        ToolAppearance.configure(timerToggleButton, symbol: "timer")
        timerToggleButton.target = self
        timerToggleButton.action = #selector(handleTimerToggle(_:))

        let resetBtn = NSButton(title: L10n.text("island.reset", "重置"), target: self, action: #selector(handleTimerReset(_:)))
        resetBtn.bezelStyle = .rounded

        let p5 = NSButton(title: L10n.text("island.5Min", "5 分钟"), target: self, action: #selector(handlePreset5(_:)))
        p5.bezelStyle = .rounded
        let p15 = NSButton(title: L10n.text("island.15Min", "15 分钟"), target: self, action: #selector(handlePreset15(_:)))
        p15.bezelStyle = .rounded
        let p25 = NSButton(title: L10n.text("island.25Min", "25 分钟"), target: self, action: #selector(handlePreset25(_:)))
        p25.bezelStyle = .rounded

        ToolAppearance.configure(keepAwakeQuickButton, symbol: "cup.and.saucer")
        keepAwakeQuickButton.target = self
        keepAwakeQuickButton.action = #selector(handleKeepAwakeQuick(_:))

        focusControls = [timerToggleButton, resetBtn, p5, p15, p25]
        timerDisplayLabel.textColor = ToolAppearance.accent
        let timerRow = NSStackView(views: [timerDisplayLabel, timerToggleButton, resetBtn])
        timerRow.orientation = .horizontal
        timerRow.alignment = .centerY
        timerRow.spacing = 9

        let presets = NSStackView(views: [p5, p15, p25, keepAwakeQuickButton])
        presets.orientation = .horizontal
        presets.alignment = .centerY
        presets.spacing = 7

        let guideLabel = NSTextField(wrappingLabelWithString: L10n.text("island.shortcutPressCmdShiftDToExpand", "• 快捷键：按下 Cmd + Shift + D 可随时展开或收起灵动岛\n• 后台常驻：点击主窗口左上角红色关闭按钮后，应用会从程序坞（Dock）隐藏并保持灵动岛运行，可在灵动岛或顶部菜单栏图标重新打开主窗口\n• 拖放与预览：拖动文件时灵动岛会自动弹出，九宫格支持图片缩略图、文本内容预览、点选切换、拖出及系统分享 / 隔空投送"))
        guideLabel.font = .systemFont(ofSize: 12.5)
        guideLabel.textColor = .secondaryLabelColor
        guideLabel.isSelectable = true
        guideLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        return makeSettingsCard(title: L10n.text("island.focusAndKeepAwake", "专注与防休眠"), symbol: "timer", views: [timerRow, presets, guideLabel])
    }

    // MARK: - Sync & Actions

    private func syncFromManager() {
        let manager = DynamicIslandManager.shared
        enabledSwitch.state = manager.isEnabled ? .on : .off
        hoverSwitch.state = manager.hoverToExpand ? .on : .off
        dragExpandSwitch.state = manager.dragToExpand ? .on : .off
        customTitleSwitch.state = manager.showCollapsedCustomTitle ? .on : .off
        if customTitleField.currentEditor() == nil {
            customTitleField.stringValue = manager.collapsedCustomTitle
        }
        customTitleField.isEnabled = manager.showCollapsedCustomTitle
        if styleSegmented.selectedSegment != manager.style.rawValue {
            styleSegmented.selectedSegment = manager.style.rawValue
        }
        syncMaterialSelection()
        expandedOrderLabel.stringValue = manager.expandedLayout.title

        for (item, checkbox) in collapsedMetricCheckboxes {
            checkbox.state = manager.isCollapsedMetricEnabled(item) ? .on : .off
        }

        if manager.collapsedCustomWidth > 0 {
            collapsedWidthSlider.doubleValue = Double(manager.collapsedCustomWidth)
            collapsedWidthValueLabel.stringValue = "\(Int(manager.collapsedCustomWidth.rounded())) pt"
            collapsedWidthAutoButton.isEnabled = true
        } else {
            let actualWidth = manager.currentCollapsedPillWidth
            collapsedWidthSlider.doubleValue = Double(min(680, max(160, actualWidth)))
            collapsedWidthValueLabel.stringValue = L10n.text("island.automaticPt", "自动 ({arg1} pt)", ["arg1": String(describing: Int(actualWidth.rounded()))])
            collapsedWidthAutoButton.isEnabled = false
        }

        let (previewLeft, previewRight) = manager.collapsedDisplayContent()
        let previewParts = [previewLeft, previewRight].compactMap { $0 }
        collapsedPreviewLabel.stringValue = previewParts.isEmpty
            ? L10n.text("island.topBarPreviewStatusDotOnly", "当前顶部预览：●（仅状态指示点）")
            : L10n.text("island.topBarPreview", "当前顶部预览：● ") + previewParts.joined(separator: "   ")

        for (feature, toggle) in featureSwitches {
            toggle.state = manager.isFeatureEnabled(feature) ? .on : .off
        }

        let snap = manager.latestSnapshot
        let batteryText: String
        if let battery = snap.batteryPercent {
            batteryText = snap.isCharging ? L10n.text("island.batteryCharging", "电量 {arg1}%（充电中）", ["arg1": String(describing: battery)]) : L10n.text("island.battery.243", "电量 {arg1}%", ["arg1": String(describing: battery)])
        } else {
            batteryText = L10n.text("island.externalPower", "外接电源")
        }
        let volText: String
        if let pct = snap.volumePercentInt {
            volText = snap.isMuted ? L10n.text("island.muted.198", "静音") : L10n.text("island.volume.199", "音量 {arg1}%", ["arg1": String(describing: pct)])
        } else {
            volText = L10n.text("island.volumeNA", "音量 N/A")
        }
        let awakeText = manager.isKeepAwakeActive ? L10n.text("island.keepAwakeOn.248", "防休眠开启") : L10n.text("island.keepAwakeOff.249", "防休眠关闭")
        let down = SystemSnapshot.formatSpeed(snap.downloadBytesPerSec)
        let up = SystemSnapshot.formatSpeed(snap.uploadBytesPerSec)
        telemetryLabel.stringValue = L10n.text("island.liveStatusCpuMemoryDownUp", "实时状态：CPU {arg1}% · 内存 {arg2} · 下行 {arg3} · 上行 {arg4} · {arg5} · {arg6} · {arg7}", ["arg1": String(describing: snap.cpuPercentInt), "arg2": String(describing: snap.formattedMemory), "arg3": String(describing: down), "arg4": String(describing: up), "arg5": String(describing: volText), "arg6": String(describing: batteryText), "arg7": String(describing: awakeText)])

        for button in focusControls { button.isEnabled = manager.isFeatureEnabled(.focusTimer) }
        timerDisplayLabel.stringValue = manager.focusTimer.formattedRemaining
        timerToggleButton.title = manager.focusTimer.isRunning ? L10n.text("island.pauseFocus", "暂停专注") : L10n.text("island.startFocus", "开始专注")
        keepAwakeQuickButton.title = manager.isKeepAwakeActive ? L10n.text("island.allowSleep", "关闭防休眠") : L10n.text("island.keepAwake.208", "开启防休眠")
        keepAwakeQuickButton.isEnabled = manager.isFeatureEnabled(.keepAwake)
    }

    @objc private func handleEnabledChanged(_ sender: NSSwitch) {
        DynamicIslandManager.shared.setEnabled(sender.state == .on)
    }

    @objc private func handleHoverChanged(_ sender: NSSwitch) {
        DynamicIslandManager.shared.hoverToExpand = (sender.state == .on)
    }

    @objc private func handleDragExpandChanged(_ sender: NSSwitch) {
        DynamicIslandManager.shared.dragToExpand = (sender.state == .on)
    }

    @objc private func handleCustomTitleSwitchChanged(_ sender: NSSwitch) {
        DynamicIslandManager.shared.showCollapsedCustomTitle = (sender.state == .on)
    }

    @objc private func handleCollapsedMetricToggled(_ sender: NSButton) {
        let items = CollapsedMetricItem.allCases
        guard sender.tag >= 0 && sender.tag < items.count else { return }
        DynamicIslandManager.shared.setCollapsedMetric(items[sender.tag], enabled: sender.state == .on)
    }

    @objc private func handleCollapsedWidthSliderChanged(_ sender: NSSlider) {
        DynamicIslandManager.shared.collapsedCustomWidth = CGFloat(sender.doubleValue.rounded())
    }

    @objc private func handleCollapsedWidthAutoReset(_ sender: Any?) {
        DynamicIslandManager.shared.collapsedCustomWidth = 0
    }

    public func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field === customTitleField else { return }
        DynamicIslandManager.shared.collapsedCustomTitle = field.stringValue
    }

    @objc private func handleFeatureSwitchChanged(_ sender: NSSwitch) {
        let features = DynamicIslandFeature.allCases
        guard sender.tag >= 0 && sender.tag < features.count else { return }
        DynamicIslandManager.shared.setFeature(features[sender.tag], enabled: sender.state == .on)
    }

    private func syncMaterialSelection() {
        guard !materialMenuTracking else { return }
        let index = DynamicIslandMaterial.allCases.firstIndex(of: DynamicIslandManager.shared.material) ?? 0
        if materialPicker.indexOfSelectedItem != index { materialPicker.selectItem(at: index) }
        for (itemIndex, item) in materialPicker.itemArray.enumerated() {
            let state: NSControl.StateValue = index == itemIndex ? .on : .off
            if item.state != state { item.state = state }
        }
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard menu === materialPicker.menu else { return }
        syncMaterialSelection()
        materialMenuTracking = true
    }

    public func menuDidClose(_ menu: NSMenu) {
        guard menu === materialPicker.menu else { return }
        materialMenuTracking = false
        DispatchQueue.main.async { [weak self] in self?.syncMaterialSelection() }
    }

    @objc private func handleMaterialChanged(_ sender: NSPopUpButton) {
        let choices = DynamicIslandMaterial.allCases
        guard choices.indices.contains(sender.indexOfSelectedItem) else { return }
        DynamicIslandManager.shared.material = choices[sender.indexOfSelectedItem]
        syncMaterialSelection()
    }

    @objc private func handleStyleChanged(_ sender: NSSegmentedControl) {
        if let style = DynamicIslandStyle(rawValue: sender.selectedSegment) {
            DynamicIslandManager.shared.style = style
        }
    }

    @objc private func openLayoutEditor(_ sender: NSButton) {
        DynamicIslandManager.shared.openLayoutEditor(from: sender)
    }

    @objc private func handleToggleExpand(_ sender: Any?) {
        DynamicIslandManager.shared.toggleExpanded()
    }

    @objc private func handleDemoHUD(_ sender: Any?) {
        DynamicIslandManager.shared.showHUD(
            title: L10n.text("island.maketoolsDynamicIsland", "MakeTools 灵动岛"),
            detail: L10n.text("island.featuresAreReadyAndCanBeToggled", "功能模块已就绪，支持独立开关"),
            symbolName: "sparkles",
            duration: 2.6
        )
    }

    @objc private func handleTimerToggle(_ sender: Any?) {
        DynamicIslandManager.shared.toggleFocusTimer()
    }

    @objc private func handleTimerReset(_ sender: Any?) {
        DynamicIslandManager.shared.resetFocusTimer()
    }

    @objc private func handlePreset5(_ sender: Any?) {
        DynamicIslandManager.shared.setFocusDuration(minutes: 5)
    }

    @objc private func handlePreset15(_ sender: Any?) {
        DynamicIslandManager.shared.setFocusDuration(minutes: 15)
    }

    @objc private func handlePreset25(_ sender: Any?) {
        DynamicIslandManager.shared.setFocusDuration(minutes: 25)
    }

    @objc private func handleKeepAwakeQuick(_ sender: Any?) {
        DynamicIslandManager.shared.toggleKeepAwake()
    }
}
