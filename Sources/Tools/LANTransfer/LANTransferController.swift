import AppKit
import CoreImage.CIFilterBuiltins

final class LANTransferController: NSObject {
    static let shared = LANTransferController()
    static let didChange = Notification.Name("MakeTools.LANTransferDidChange")

    enum State: Equatable {
        case off
        case starting
        case listening(URL)
        case failed(String)

        var isEnabled: Bool {
            switch self {
            case .starting, .listening: return true
            case .off, .failed: return false
            }
        }

        var url: URL? {
            if case .listening(let url) = self { return url }
            return nil
        }
    }

    private let server = LANTransferServer()
    private let defaults = UserDefaults.standard
    private let portKey = "MakeTools.LANTransfer.port"
    private let directoryKey = "MakeTools.LANTransfer.directory"
    private var generation = UUID()
    private(set) var state = State.off
    private(set) var lastReceivedName: String?

    var port: UInt16 {
        let value = defaults.integer(forKey: portKey)
        return (1024...65535).contains(value) ? UInt16(value) : 8765
    }

    var directory: URL {
        if let path = defaults.string(forKey: directoryKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads", isDirectory: true)
    }

    func setPort(_ value: UInt16) {
        guard !state.isEnabled, value >= 1024, port != value else { return }
        defaults.set(Int(value), forKey: portKey)
        notify()
    }

    func setDirectory(_ url: URL) {
        guard !state.isEnabled, url.isFileURL else { return }
        defaults.set(url.path, forKey: directoryKey)
        notify()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != state.isEnabled else { return }
        let id = UUID()
        generation = id
        if enabled {
            state = .starting
            lastReceivedName = nil
            server.start(port: port, directory: directory) { [weak self] event in
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == id else { return }
                    switch event {
                    case .ready(let url): self.state = .listening(url)
                    case .failed(let message): self.state = .failed(message)
                    case .received(let name): self.lastReceivedName = name
                    }
                    self.notify()
                }
            }
        } else {
            state = .off
            server.stop()
        }
        notify()
    }

    @discardableResult
    func copyLink() -> Bool {
        guard let url = state.url else { return false }
        return ClipboardHelper.copyTransientText(url.absoluteString)
    }

    func shutdown() {
        server.shutdown()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}

final class LANTransferLinkView: NSStackView {
    private static let context = CIContext()
    private let qr = NSImageView()
    private let urlField = NSTextField(labelWithString: "")
    private let copy = NSButton(title: L10n.text("lanTransfer.copyLink", "复制链接"), target: nil, action: nil)
    private var currentURL: URL?

    init() {
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .centerX
        spacing = 9
        isHidden = true

        qr.imageScaling = .scaleProportionallyDown
        qr.setAccessibilityLabel(L10n.text("lanTransfer.localNetworkUploadQrCode", "局域网上传二维码"))
        urlField.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        urlField.alignment = .left
        urlField.isSelectable = true
        urlField.cell?.lineBreakMode = .byTruncatingMiddle
        urlField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        ToolAppearance.configure(copy, symbol: "link")
        copy.target = self
        copy.action = #selector(copyURL)
        copy.setContentCompressionResistancePriority(.required, for: .horizontal)
        let actions = NSStackView(views: [urlField, copy])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 10
        addArrangedSubview(qr)
        addArrangedSubview(actions)
        NSLayoutConstraint.activate([
            qr.widthAnchor.constraint(equalToConstant: 180),
            qr.heightAnchor.constraint(equalTo: qr.widthAnchor),
            actions.widthAnchor.constraint(equalTo: widthAnchor)
        ])
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ url: URL?) {
        guard url != currentURL else { return }
        currentURL = url
        isHidden = url == nil
        urlField.stringValue = url?.absoluteString ?? ""
        urlField.toolTip = url?.absoluteString
        qr.image = url.flatMap(Self.makeQR)
    }

    private static func makeQR(_ url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let padding: CGFloat = 4
        let white = CIImage(color: .white).cropped(to: code.extent.insetBy(dx: -padding, dy: -padding))
        let image = code.composited(over: white).transformed(by: CGAffineTransform(translationX: padding, y: padding))
        let scale = floor(180 / image.extent.width)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let rendered = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: rendered, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }

    @objc private func copyURL() {
        if LANTransferController.shared.copyLink() {
            ClipboardHelper.flashButton(copy, restoreTitle: L10n.text("lanTransfer.copyLink", "复制链接"))
        }
    }
}

private final class LANTransferLinkPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class LANTransferLinkWindowController: NSWindowController {
    private let link = LANTransferLinkView()

    init() {
        let panel = LANTransferLinkPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 286),
            styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.backgroundColor = ToolAppearance.canvas
        panel.title = L10n.text("lanTransfer.title", "局域网传输")
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        super.init(window: panel)
        guard let root = panel.contentView else { return }

        let hint = NSTextField(labelWithString: L10n.text("lanTransfer.scanToUploadOnTheSameWi", "在同一 Wi-Fi 或有线网络中扫码上传"))
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: 12)
        let content = NSStackView(views: [hint, link])
        content.orientation = .vertical
        content.alignment = .centerX
        content.spacing = 12
        let card = ToolAppearance.section(content, inset: 13)
        card.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 17),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -17),
            link.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(url: URL, from anchor: NSView) {
        guard let window, let parent = anchor.window, parent.isVisible else { return }
        link.show(url)
        if let screen = parent.screen {
            let visible = screen.visibleFrame.insetBy(dx: 10, dy: 10)
            let x = max(visible.minX, min(parent.frame.midX - window.frame.width / 2, visible.maxX - window.frame.width))
            let top = max(visible.minY + window.frame.height, min(parent.frame.minY - 8, visible.maxY))
            window.setFrameTopLeftPoint(NSPoint(x: x, y: top))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }
}
