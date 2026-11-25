import AppKit
import Foundation
import WebKit

/// Receives copy and selection-sync requests posted from WKWebView via `window.webkit.messageHandlers.clipboard.postMessage(...)`.
public final class ClipboardScriptMessageHandler: NSObject, WKScriptMessageHandler {
    public var onCopied: (() -> Void)?
    public var onSelectionChanged: ((String) -> Void)?

    public init(
        onCopied: (() -> Void)? = nil,
        onSelectionChanged: ((String) -> Void)? = nil
    ) {
        self.onCopied = onCopied
        self.onSelectionChanged = onSelectionChanged
        super.init()
    }

    public func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        if let dict = message.body as? [String: Any] {
            let type = (dict["type"] as? String) ?? "copy"
            if type == "selection" {
                onSelectionChanged?((dict["text"] as? String) ?? "")
                return
            }
            if type == "copy",
               let text = dict["text"] as? String,
               !text.isEmpty {
                ClipboardHelper.copyText(text)
                onCopied?()
            }
            return
        }
        if let text = message.body as? String, !text.isEmpty {
            ClipboardHelper.copyText(text)
            onCopied?()
        }
    }
}

/// WKWebView subclass that preserves mouse selection and handles Cmd+C / Cmd+A across the host app.
public final class CopyableWebView: WKWebView {
    public var allowEmptyCopyValidation: Bool = false
    public private(set) var cachedSelection: String = ""
    public var hasSelection: Bool { !cachedSelection.isEmpty }
    public var onSelectionCopied: (() -> Void)?

    public static func makeConfigured(
        allowEmptyCopyValidation: Bool = false,
        onCopied: (() -> Void)? = nil
    ) -> CopyableWebView {
        let handler = ClipboardScriptMessageHandler(onCopied: onCopied)
        let config = WKWebViewConfiguration()
        config.userContentController.add(handler, name: ClipboardHelper.messageHandlerName)

        let webView = CopyableWebView(frame: .zero, configuration: config)
        webView.allowEmptyCopyValidation = allowEmptyCopyValidation
        handler.onSelectionChanged = { [weak webView] text in
            webView?.updateCachedSelection(text)
        }
        return webView
    }

    deinit {
        configuration.userContentController.removeScriptMessageHandler(
            forName: ClipboardHelper.messageHandlerName
        )
    }

    public override var acceptsFirstResponder: Bool { true }

    public override func mouseDown(with event: NSEvent) {
        if let win = window {
            let first = win.firstResponder
            let alreadyFocused = (first === self) || ((first as? NSView)?.isDescendant(of: self) == true)
            if !alreadyFocused {
                win.makeFirstResponder(self)
            }
        }
        super.mouseDown(with: event)
    }

    public func updateCachedSelection(_ text: String) {
        if Thread.isMainThread {
            cachedSelection = text
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.cachedSelection = text
            }
        }
    }

    public func resetCachedSelection() {
        cachedSelection = ""
    }

    public func copySelectionToPasteboard(completion: ((Bool) -> Void)? = nil) {
        let cached = cachedSelection
        if !cached.isEmpty {
            ClipboardHelper.copyText(cached)
            onSelectionCopied?()
        }

        evaluateJavaScript("window.getSelection ? window.getSelection().toString() : ''") { [weak self] result, _ in
            let liveText = (result as? String) ?? ""
            self?.cachedSelection = liveText
            if !liveText.isEmpty && liveText != cached {
                ClipboardHelper.copyText(liveText)
                self?.onSelectionCopied?()
            }
            completion?(!liveText.isEmpty || !cached.isEmpty)
        }
    }

    public func selectAllContent() {
        evaluateJavaScript("window.__makeToolsSelectAll ? window.__makeToolsSelectAll() : ''") { [weak self] result, _ in
            if let text = result as? String {
                self?.cachedSelection = text
            }
        }
    }

    public func handleShortcutEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        guard flags == .command else {
            return false
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            if hasSelection || allowEmptyCopyValidation {
                copySelectionToPasteboard()
                return true
            }
            return false
        case "a":
            selectAllContent()
            return true
        default:
            return false
        }
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleShortcutEvent(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    @objc public func copy(_ sender: Any?) {
        copySelectionToPasteboard()
    }

    public override func selectAll(_ sender: Any?) {
        selectAllContent()
    }

    public override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(NSText.copy(_:)):
            return allowEmptyCopyValidation || hasSelection
        case #selector(NSText.selectAll(_:)):
            return true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }
}
