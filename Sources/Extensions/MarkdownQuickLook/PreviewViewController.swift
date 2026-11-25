import AppKit
import Foundation
import QuickLookUI

@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController, NSUserInterfaceValidations {
    private var markdownView: NativeMarkdownView?
    private var fileLabel: NSTextField?
    private var copyMarkdownButton: NSButton?
    private var copyPlainTextButton: NSButton?
    private var currentMarkdown: String = ""
    private var keyDownMonitor: Any?

    override var nibName: NSNib.Name? { nil }
    override var acceptsFirstResponder: Bool { true }

    deinit {
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func loadView() {
        let rootView = NSView(frame: NSRect(x: 0, y: 0, width: 860, height: 1000))
        preferredContentSize = NSSize(width: 860, height: 1000)

        let label = NSTextField(labelWithString: "Markdown")
        let context = NSTextField(labelWithString: "快速预览")
        fileLabel = label

        let mdButton = NSButton(title: "复制 Markdown", target: self, action: #selector(copyMarkdown(_:)))
        mdButton.controlSize = .small
        ToolAppearance.configureCopy(mdButton, symbol: "doc.on.doc")
        self.copyMarkdownButton = mdButton

        let textButton = NSButton(title: "复制纯文本", target: self, action: #selector(copyPlainText(_:)))
        textButton.controlSize = .small
        ToolAppearance.configureCopy(textButton, symbol: "text.alignleft")
        self.copyPlainTextButton = textButton

        let toolbar = ToolAppearance.documentToolbar(
            filename: label,
            context: context,
            buttons: [mdButton, textButton],
            insets: NSEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        )

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let nativeView = NativeMarkdownView(frame: .zero)
        nativeView.translatesAutoresizingMaskIntoConstraints = false
        nativeView.onOpenLink = { [weak self] url in
            self?.extensionContext?.open(url, completionHandler: nil)
        }
        self.markdownView = nativeView

        rootView.addSubview(toolbar)
        rootView.addSubview(separator)
        rootView.addSubview(nativeView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: rootView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),

            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),

            nativeView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            nativeView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            nativeView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            nativeView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        self.view = rootView
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if keyDownMonitor == nil {
            keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.markdownView?.handleShortcutEvent(event) == true {
                    return nil
                }
                return event
            }
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let monitor = keyDownMonitor {
            NSEvent.removeMonitor(monitor)
            keyDownMonitor = nil
        }
    }

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                let markdown = try Self.readMarkdown(at: url)
                let title = url.lastPathComponent

                DispatchQueue.main.async {
                    guard let self else {
                        handler(nil)
                        return
                    }
                    self.loadViewIfNeeded()
                    self.currentMarkdown = markdown
                    self.fileLabel?.stringValue = title
                    self.fileLabel?.toolTip = url.path
                    self.markdownView?.render(markdown: markdown)
                    handler(nil)
                }
            } catch {
                DispatchQueue.main.async {
                    handler(error)
                }
            }
        }
    }

    // MARK: - Actions & Responder

    @objc func copy(_ sender: Any?) {
        markdownView?.copy(sender)
    }

    override func selectAll(_ sender: Any?) {
        markdownView?.selectAll(sender)
    }

    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        markdownView?.validateUserInterfaceItem(item) ?? false
    }

    @objc private func copyMarkdown(_ sender: Any?) {
        ClipboardHelper.copyText(currentMarkdown)
        if let button = copyMarkdownButton {
            ClipboardHelper.flashButton(button, restoreTitle: "复制 Markdown")
        }
    }

    @objc private func copyPlainText(_ sender: Any?) {
        let plainText = MarkdownRenderer.renderPlainText(currentMarkdown)
        ClipboardHelper.copyText(plainText)
        if let button = copyPlainTextButton {
            ClipboardHelper.flashButton(button, restoreTitle: "复制纯文本")
        }
    }

    // MARK: - Helpers

    private static func readMarkdown(at url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        var detectedEncoding: UInt = 0
        let nsString = try NSString(contentsOf: url, usedEncoding: &detectedEncoding)
        return nsString as String
    }
}
