import AppKit

final class LANTransferTool: ToolModule {
    let id = "lan-transfer"
    let title = L10n.text("lanTransfer.title", "局域网传输")
    let subtitle = L10n.text("lanTransfer.scanToUploadFilesToYourMac", "手机扫码上传到 Mac")
    let symbolName = "wifi"

    func makeViewController() -> NSViewController {
        LANTransferViewController()
    }
}

private final class LANTransferSettingsDocument: NSView {
    override var isFlipped: Bool { true }
}

private final class LANTransferViewController: NSViewController {
    private let transfer = LANTransferController.shared
    private let toggle = NSSwitch()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let port = NSTextField(string: "")
    private let directory = NSTextField(labelWithString: "")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let link = LANTransferLinkView()
    private var linkCard: NSView?
    private var savePort: NSButton?
    private var chooseFolder: NSButton?
    private var observer: NSObjectProtocol?
    private var lastDisplayedPort: UInt16?

    override var nibName: NSNib.Name? { nil }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    override func loadView() {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        let root = LANTransferSettingsDocument()
        root.translatesAutoresizingMaskIntoConstraints = false
        let header = ToolAppearance.header(
            title: L10n.text("lanTransfer.title", "局域网传输"), subtitle: L10n.text("lanTransfer.uploadFilesToThisMacFromA", "在同一 Wi-Fi 或有线网络中，用浏览器将文件传到这台 Mac。"), symbol: "wifi"
        )

        toggle.target = self
        toggle.action = #selector(toggleReceiving)
        toggle.setAccessibilityLabel(L10n.text("lanTransfer.receive.title", "接收文件"))
        let title = NSTextField(labelWithString: L10n.text("lanTransfer.receive.title", "接收文件"))
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
        let switchRow = row([ToolAppearance.tile("arrow.down.to.line", side: 34, size: 15), title, spacer, toggle])

        for label in [status, feedback] {
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        feedback.isHidden = true
        port.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        port.widthAnchor.constraint(equalToConstant: 76).isActive = true
        port.target = self
        port.action = #selector(applyPort)
        port.setAccessibilityLabel(L10n.text("lanTransfer.port", "端口"))
        let savePort = button(L10n.text("lanTransfer.savePort", "保存端口"), "checkmark", #selector(applyPort))
        self.savePort = savePort
        let portRow = row([fieldLabel(L10n.text("lanTransfer.port", "端口")), port, savePort])

        directory.lineBreakMode = .byTruncatingMiddle
        directory.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let chooseFolder = button(L10n.text("lanTransfer.chooseFolder", "选择文件夹"), "folder", #selector(selectFolder))
        self.chooseFolder = chooseFolder
        let openFolder = button(L10n.text("lanTransfer.showInFinder", "在访达中打开"), "arrow.up.right.square", #selector(openFolder))
        let destinationTitle = L10n.text("lanTransfer.destination", "保存到")
        let destinationHeader = ToolAppearance.sectionTitle(destinationTitle, symbol: "folder")
        let folderActions = row([chooseFolder, openFolder])
        let configuration = column([portRow, destinationHeader, directory, folderActions])
        configuration.setCustomSpacing(16, after: portRow)
        let network = column([switchRow, status])
        let receivingCard = ToolAppearance.section(network)
        let configurationCard = ToolAppearance.section(configuration)
        let linkCard = ToolAppearance.section(link)
        self.linkCard = linkCard

        let stack = column([header, receivingCard, configurationCard, feedback, linkCard])
        stack.spacing = 14
        for item in stack.arrangedSubviews {
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        for (item, parent) in [(switchRow, network), (status, network), (directory, configuration)] {
            item.widthAnchor.constraint(equalTo: parent.widthAnchor).isActive = true
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        scroll.documentView = root
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            root.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            root.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24)
        ])
        view = scroll
        observer = NotificationCenter.default.addObserver(forName: LANTransferController.didChange, object: transfer, queue: .main) {
            [weak self] _ in self?.refresh()
        }
        refresh()
    }

    private func fieldLabel(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.font = .systemFont(ofSize: 12, weight: .semibold)
        return field
    }

    private func column(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        return stack
    }

    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        return stack
    }

    private func button(_ title: String, _ symbol: String, _ action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        ToolAppearance.configure(button, symbol: symbol)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    private func refresh() {
        let state = transfer.state
        toggle.state = state.isEnabled ? .on : .off
        port.isEnabled = !state.isEnabled
        savePort?.isEnabled = !state.isEnabled
        chooseFolder?.isEnabled = !state.isEnabled
        if lastDisplayedPort != transfer.port || state.isEnabled {
            lastDisplayedPort = transfer.port
            port.stringValue = String(transfer.port)
        }
        directory.stringValue = (transfer.directory.path as NSString).abbreviatingWithTildeInPath
        directory.toolTip = transfer.directory.path
        status.textColor = .secondaryLabelColor
        switch state {
        case .off:
            status.stringValue = L10n.text("lanTransfer.offTurnOnReceptionToGenerateA", "已关闭。开启后生成本次接收的二维码和链接。")
        case .starting:
            status.stringValue = L10n.text("lanTransfer.startingReception", "正在启动接收…")
        case .listening:
            status.stringValue = transfer.lastReceivedName.map { L10n.text("lanTransfer.status.saved", "最近收到  {filename}", ["filename": String(describing: $0)]) }
                ?? L10n.text("lanTransfer.readyToReceiveShareThisHttpLink", "正在接收。链接使用 HTTP，请仅在可信的局域网内分享。")
        case .failed(let message):
            status.stringValue = message
            status.textColor = .systemRed
        }
        linkCard?.isHidden = state.url == nil
        link.show(state.url)
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        feedback.stringValue = message
        feedback.textColor = isError ? .systemRed : .secondaryLabelColor
        feedback.isHidden = message.isEmpty
    }

    private func savePortValue() -> Bool {
        let text = port.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = UInt16(text), value >= 1024 else {
            showFeedback(L10n.text("lanTransfer.enterAPortBetween1024And65535", "请输入 1024 至 65535 之间的端口号。"), isError: true)
            return false
        }
        port.stringValue = String(value)
        transfer.setPort(value)
        return true
    }

    @objc private func applyPort() {
        if savePortValue() {
            showFeedback(L10n.text("lanTransfer.portSaved", "端口已保存。"))
        }
    }

    @objc private func toggleReceiving() {
        let enabled = toggle.state == .on
        if enabled && !savePortValue() {
            toggle.state = .off
            return
        }
        showFeedback("")
        transfer.setEnabled(enabled)
    }

    @objc private func selectFolder() {
        guard let window = view.window else { return }
        let picker = NSOpenPanel()
        picker.canChooseDirectories = true
        picker.canChooseFiles = false
        picker.canCreateDirectories = true
        picker.allowsMultipleSelection = false
        picker.directoryURL = transfer.directory
        picker.prompt = L10n.text("lanTransfer.choose", "选择")
        picker.beginSheetModal(for: window) { [weak self] result in
            guard result == .OK, let directory = picker.url else { return }
            self?.transfer.setDirectory(directory)
            self?.showFeedback("")
        }
    }

    @objc private func openFolder() {
        guard NSWorkspace.shared.open(transfer.directory) else {
            showFeedback(L10n.text("lanTransfer.couldnTOpenTheCurrentDestinationChoose", "无法打开当前保存目录，请重新选择文件夹。"), isError: true)
            return
        }
    }
}
