import AppKit
import Foundation

/// Shared pasteboard utilities for both MakeTools app and extensions.
public enum ClipboardHelper {
    public static let messageHandlerName = "clipboard"
    public static let copiedTitle = "已复制 ✓"
    private static var pendingTimers: [ObjectIdentifier: DispatchWorkItem] = [:]

    /// Writes plain UTF-8 text to the system general pasteboard.
    public static func copyText(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func historyText(from pasteboard: NSPasteboard) -> String? {
        guard pasteboard.availableType(from: [concealedType, transientType]) == nil else { return nil }
        return pasteboard.string(forType: .string)
    }

    @discardableResult
    static func copyPassword(_ password: String, to pasteboard: NSPasteboard = .general,
                             expiresAfter duration: TimeInterval = 45) -> Bool {
        let item = NSPasteboardItem()
        item.setString(password, forType: .string)
        item.setData(Data(), forType: concealedType)
        item.setData(Data(), forType: transientType)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return false }

        let changeCount = pasteboard.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            if pasteboard.changeCount == changeCount {
                pasteboard.clearContents()
            }
        }
        return true
    }

    /// Temporarily updates a button title to indicate a copy succeeded, then restores its original title.
    public static func flashButton(
        _ button: NSButton,
        copiedTitle: String = ClipboardHelper.copiedTitle,
        restoreTitle: String,
        duration: TimeInterval = 1.5
    ) {
        let work = { [weak button] in
            guard let button else { return }
            let key = ObjectIdentifier(button)
            pendingTimers[key]?.cancel()
            button.title = copiedTitle
            ToolAppearance.reveal(button, from: 0.72, duration: 0.16)

            let item = DispatchWorkItem { [weak button] in
                pendingTimers.removeValue(forKey: key)
                button?.title = restoreTitle
            }
            pendingTimers[key] = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
        }

        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}
