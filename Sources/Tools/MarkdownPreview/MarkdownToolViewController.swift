import AppKit
import UniformTypeIdentifiers
import WebKit

public final class MarkdownPreviewTool: ToolModule {
    public let id = "markdown-preview"
    public let title = L10n.text("markdown.markdownPreview", "Markdown 预览")
    public let subtitle = L10n.text("markdown.offlineRenderingAndCodeCopying", "离线渲染与代码复制")
    public let symbolName = "doc.richtext"

    public init() {}

    public func makeViewController() -> NSViewController {
        MarkdownToolViewController()
    }
}

public final class MarkdownToolViewController: NSViewController, WKNavigationDelegate, NSUserInterfaceValidations {
    private var webView: CopyableWebView?
    private var fileLabel: NSTextField?
    private var contextLabel: NSTextField?
    private var copyMarkdownButton: NSButton?
    private var copyPlainTextButton: NSButton?
    private var currentMarkdown: String = ""
    struct Preview {
        let url: URL
        let markdown: String
    }
    private(set) var preview: Preview?

    public override var nibName: NSNib.Name? { nil }

    public override func loadView() {
        let rootView = NSView()

        let openButton = NSButton(title: L10n.text("markdown.openFile", "打开文件…"), target: self, action: #selector(openDocument(_:)))
        ToolAppearance.configure(openButton, symbol: "folder")

        let label = NSTextField(labelWithString: L10n.text("markdown.builtInDemo", "内置演示"))
        let context = NSTextField(labelWithString: L10n.text("markdown.markdownPreview", "Markdown 预览"))
        fileLabel = label
        contextLabel = context

        let copyMDButton = NSButton(title: L10n.text("quickLook.copyMarkdown", "复制 Markdown"), target: self, action: #selector(copyMarkdown(_:)))
        ToolAppearance.configureCopy(copyMDButton, symbol: "doc.on.doc")
        self.copyMarkdownButton = copyMDButton

        let copyTextButton = NSButton(title: L10n.text("quickLook.copyPlainText", "复制纯文本"), target: self, action: #selector(copyPlainText(_:)))
        ToolAppearance.configureCopy(copyTextButton, symbol: "text.alignleft")
        self.copyPlainTextButton = copyTextButton

        let toolbar = ToolAppearance.documentToolbar(
            filename: label,
            context: context,
            buttons: [openButton, copyMDButton, copyTextButton],
            insets: NSEdgeInsets(top: 13, left: 20, bottom: 13, right: 20)
        )

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let webView = CopyableWebView.makeConfigured(allowEmptyCopyValidation: true)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        self.webView = webView

        rootView.addSubview(toolbar)
        rootView.addSubview(separator)
        rootView.addSubview(webView)

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: rootView.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),

            separator.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),

            webView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor)
        ])

        self.view = rootView
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        loadInitialDemo()
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        if let webView {
            view.window?.makeFirstResponder(webView)
        }
    }

    // MARK: - Public API

    public func openFilePicker() {
        openDocument(nil)
    }

    public func loadMarkdownFile(at url: URL) {
        loadViewIfNeeded()
        let content: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            content = utf8
        } else {
            var usedEncoding: UInt = 0
            guard let fallback = try? NSString(contentsOf: url, usedEncoding: &usedEncoding) else {
                return
            }
            content = fallback as String
        }
        restorePreview(Preview(url: url, markdown: content))
    }

    func restorePreview(_ preview: Preview) {
        loadViewIfNeeded()
        self.preview = preview
        let url = preview.url
        render(markdown: preview.markdown, title: url.lastPathComponent)
        fileLabel?.stringValue = url.lastPathComponent
        fileLabel?.toolTip = url.path
        contextLabel?.stringValue = url.deletingLastPathComponent().path
        contextLabel?.toolTip = url.path
        view.window?.title = "\(url.lastPathComponent) — MakeTools"
    }

    // MARK: - Actions & Responder

    @objc public func copy(_ sender: Any?) {
        webView?.copy(sender)
    }

    public override func selectAll(_ sender: Any?) {
        webView?.selectAll(sender)
    }

    public func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        webView?.validateUserInterfaceItem(item) ?? false
    }

    @objc private func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "md") ?? .plainText,
            UTType(filenameExtension: "markdown") ?? .plainText,
            .plainText
        ]

        if panel.runModal() == .OK, let url = panel.url {
            loadMarkdownFile(at: url)
        }
    }

    @objc private func copyMarkdown(_ sender: Any?) {
        ClipboardHelper.copyText(currentMarkdown)
        if let button = copyMarkdownButton {
            ClipboardHelper.flashButton(button, restoreTitle: L10n.text("quickLook.copyMarkdown", "复制 Markdown"))
        }
    }

    @objc private func copyPlainText(_ sender: Any?) {
        let button = copyPlainTextButton
        let script = "document.querySelector('.markdown-body')?.innerText || document.body?.innerText || ''"
        webView?.evaluateJavaScript(script) { [weak self] result, _ in
            let text = (result as? String) ?? self?.currentMarkdown ?? ""
            ClipboardHelper.copyText(text)
            if let button {
                ClipboardHelper.flashButton(button, restoreTitle: L10n.text("quickLook.copyPlainText", "复制纯文本"))
            }
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let window = view.window else { return }
        if let responder = window.firstResponder, responder === window || responder === webView {
            window.makeFirstResponder(webView)
        }
    }

    public func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "mailto" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - Private Helpers

    private func loadInitialDemo() {
        let bundle = Bundle.main
        let language = L10n.locale.language.languageCode?.identifier
        let localizedDemo = language == "zh" ? nil
            : bundle.url(forResource: "demo", withExtension: "md", subdirectory: nil, localization: "en")
        let defaultDemo = bundle.resourceURL?.appendingPathComponent("demo.md")
        if let demoURL = localizedDemo ?? defaultDemo,
           let content = try? String(contentsOf: demoURL, encoding: .utf8) {
            render(markdown: content, title: "demo.md")
            return
        }
        render(markdown: "# MakeTools", title: "MakeTools")
    }

    private func render(markdown: String, title: String) {
        currentMarkdown = markdown
        let html = MarkdownRenderer.renderDocument(markdown, title: title, interactive: true)
        webView?.resetCachedSelection()
        webView?.loadHTMLString(html, baseURL: nil)
    }
}
