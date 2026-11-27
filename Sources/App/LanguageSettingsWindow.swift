import AppKit
import UniformTypeIdentifiers

final class LanguageSettingsWindow: NSWindowController {
    private let heading = NSTextField(labelWithString: "")
    private let picker = NSPopUpButton()
    private let hint = NSTextField(wrappingLabelWithString: "")
    private let importButton = NSButton()
    private let exportButton = NSButton()
    private let feedback = NSTextField(wrappingLabelWithString: "")

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 272),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.backgroundColor = ToolAppearance.canvas
        window.isReleasedWhenClosed = false
        super.init(window: window)
        guard let root = window.contentView else { return }

        heading.font = .systemFont(ofSize: 24, weight: .semibold)
        let banner = NSStackView(views: [ToolAppearance.tile("globe", side: 35, size: 17), heading])
        banner.orientation = .horizontal
        banner.alignment = .centerY
        banner.spacing = 10
        hint.textColor = .secondaryLabelColor
        hint.maximumNumberOfLines = 0
        feedback.maximumNumberOfLines = 0
        picker.target = self
        picker.action = #selector(changeLanguage)
        for (button, action) in [(importButton, #selector(importPack)), (exportButton, #selector(exportTemplate))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
        }
        let buttons = NSStackView(views: [importButton, exportButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let settings = NSStackView(views: [picker, hint, buttons])
        settings.orientation = .vertical
        settings.alignment = .leading
        settings.spacing = 12
        for view in [picker, hint] { view.widthAnchor.constraint(equalTo: settings.widthAnchor).isActive = true }
        let card = ToolAppearance.section(settings)
        let layout = NSStackView(views: [banner, card, feedback])
        layout.orientation = .vertical
        layout.alignment = .leading
        layout.spacing = 12
        layout.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(layout)
        NSLayoutConstraint.activate([
            layout.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            layout.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            layout.topAnchor.constraint(equalTo: root.topAnchor, constant: 22),
            layout.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -18),
            card.widthAnchor.constraint(equalTo: layout.widthAnchor),
            feedback.widthAnchor.constraint(equalTo: layout.widthAnchor)
        ])
        refresh()
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func refresh() {
        let localization = Localization.shared
        let title = L10n.text("language.title", "语言")
        window?.title = title
        heading.stringValue = title
        picker.setAccessibilityLabel(title)
        hint.stringValue = L10n.text("language.hint", "导入 JSON 语言包即可使用自定义翻译。未翻译的内容会使用内置文案。")
        importButton.title = L10n.text("language.import", "导入语言包…")
        exportButton.title = L10n.text("language.export", "导出翻译模板…")
        picker.removeAllItems()
        picker.addItem(withTitle: L10n.text("language.system", "跟随系统"))
        picker.lastItem?.representedObject = Localization.systemID
        for choice in localization.choices {
            let item = NSMenuItem(title: choice.name, action: nil, keyEquivalent: "")
            item.representedObject = choice.id
            picker.menu?.addItem(item)
        }
        picker.select(picker.itemArray.first { $0.representedObject as? String == localization.selection } ?? picker.item(at: 0))
    }

    @objc private func changeLanguage() {
        guard let id = picker.selectedItem?.representedObject as? String else { return }
        Localization.shared.setSelection(id)
        feedback.stringValue = ""
        refresh()
    }

    @objc private func importPack() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                let data = try Localization.read(url)
                let pack = try Localization.shared.validate(data)
                if Localization.shared.choices.contains(where: { $0.id == "user:" + pack.locale.lowercased() }) {
                    let alert = NSAlert()
                    alert.messageText = L10n.text("language.replace.title", "替换现有语言包？")
                    alert.informativeText = pack.displayName
                    alert.addButton(withTitle: L10n.text("language.replace", "替换"))
                    alert.addButton(withTitle: L10n.text("passwords.cancel", "取消"))
                    alert.beginSheetModal(for: window) { [weak self] reply in
                        if reply == .alertFirstButtonReturn { self?.finishImport(data) }
                    }
                } else {
                    finishImport(data)
                }
            } catch {
                showError(error)
            }
        }
    }

    private func finishImport(_ data: Data) {
        do {
            try Localization.shared.install(data)
            refresh()
            feedback.textColor = .secondaryLabelColor
            feedback.stringValue = L10n.text("language.imported", "语言包已导入。请从列表中选择该语言。")
        } catch {
            showError(error)
        }
    }

    @objc private func exportTemplate() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MakeTools-language-template.json"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Localization.shared.template().write(to: url, options: .atomic)
            } catch {
                self?.showError(error)
            }
        }
    }

    private func showError(_ error: Error) {
        feedback.textColor = .systemRed
        feedback.stringValue = L10n.text("language.error", "无法处理语言文件。{detail}",
                                         ["detail": error.localizedDescription])
    }
}
