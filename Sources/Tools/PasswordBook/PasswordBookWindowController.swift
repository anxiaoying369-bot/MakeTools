import AppKit

private final class PasswordBookPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class PasswordBookWindowController: NSWindowController, NSWindowDelegate {
    private let store = PasswordBookStore()
    private let keychainQueue = DispatchQueue(label: "com.make.MakeTools.PasswordBook.Keychain")
    private let recordPicker = NSPopUpButton()
    private let websiteField = NSTextField(string: "")
    private let accountField = NSTextField(string: "")
    private let passwordField = NSSecureTextField(string: "")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let copyAccountButton = NSButton(title: L10n.text("passwords.copyAccount", "复制账户"), target: nil, action: nil)
    private let copyPasswordButton = NSButton(title: L10n.text("passwords.copyPassword", "复制密码"), target: nil, action: nil)
    private let deleteButton = NSButton(title: L10n.text("passwords.delete", "删除"), target: nil, action: nil)
    private let saveButton = NSButton(title: L10n.text("passwords.save", "保存"), target: nil, action: nil)

    private var entries: [PasswordBookEntry] = []
    private var isBusy = false
    private var hasLoadedEntries = false

    private var selectedEntry: PasswordBookEntry? {
        let index = recordPicker.indexOfSelectedItem - 1
        return entries.indices.contains(index) ? entries[index] : nil
    }

    init() {
        let panel = PasswordBookPanel(
            contentRect: NSRect(x: 0, y: 0, width: 518, height: 330),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = ToolAppearance.canvas
        panel.title = L10n.text("island.passwordBook", "密码本")
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.sharingType = .none
        super.init(window: panel)
        panel.delegate = self
        configureView(in: panel)
        updateControls()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(from anchor: NSView) {
        guard let panel = window, let parent = anchor.window else { return }
        let wasVisible = panel.isVisible
        if !wasVisible {
            position(panel, beside: anchor, in: parent)
        }
        panel.makeKeyAndOrderFront(nil)
        if (!wasVisible || !hasLoadedEntries) && !isBusy {
            loadEntries(selecting: selectedEntry?.id)
        }
    }

    func windowWillClose(_ notification: Notification) {
        window?.endEditing(for: nil)
        passwordField.stringValue = ""
    }

    private func position(_ panel: NSWindow, beside anchor: NSView, in parent: NSWindow) {
        let anchorOnScreen = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        guard let screen = parent.screen ?? NSScreen.main else {
            panel.center()
            return
        }
        let visible = screen.visibleFrame.insetBy(dx: 9, dy: 9)
        let x = min(max(anchorOnScreen.maxX - panel.frame.width, visible.minX), visible.maxX - panel.frame.width)
        let y = min(max(parent.frame.minY - 6, visible.minY + panel.frame.height), visible.maxY)
        panel.setFrameTopLeftPoint(NSPoint(x: x, y: y))
    }

    private func configureView(in window: NSWindow) {
        guard let root = window.contentView else { return }

        recordPicker.target = self
        recordPicker.action = #selector(handleRecordChange)
        recordPicker.setAccessibilityLabel(L10n.text("passwords.passwordEntries", "密码记录"))

        let fields: [(String, NSView)] = [
            (L10n.text("passwords.saveEntry", "保存记录"), recordPicker),
            (L10n.text("passwords.website", "网站名称"), websiteField),
            (L10n.text("passwords.account", "账户"), accountField),
            (L10n.text("passwords.password", "密码"), passwordField)
        ]
        let form = NSStackView()
        form.orientation = .vertical
        form.alignment = .leading
        form.spacing = 9
        for (title, field) in fields {
            let caption = label(title)
            caption.lineBreakMode = .byTruncatingTail
            caption.toolTip = title
            caption.widthAnchor.constraint(equalToConstant: 116).isActive = true
            field.setContentHuggingPriority(.defaultLow - 1, for: .horizontal)
            let row = NSStackView(views: [caption, field])
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 11
            form.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: form.widthAnchor).isActive = true
        }

        websiteField.placeholderString = L10n.text("passwords.forExampleExampleCom", "例如 example.com")
        websiteField.setAccessibilityLabel(L10n.text("passwords.website", "网站名称"))
        accountField.placeholderString = L10n.text("passwords.usernameOrEmail", "用户名或邮箱")
        accountField.setAccessibilityLabel(L10n.text("passwords.account", "账户"))
        passwordField.setAccessibilityLabel(L10n.text("passwords.password", "密码"))
        websiteField.nextKeyView = accountField
        accountField.nextKeyView = passwordField
        passwordField.nextKeyView = saveButton
        window.initialFirstResponder = websiteField

        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.setAccessibilityLabel(L10n.text("passwords.passwordBookStatus", "密码本状态"))
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        setup(copyAccountButton, symbol: "person.crop.rectangle", action: #selector(handleCopyAccount))
        setup(copyPasswordButton, symbol: "key", action: #selector(handleCopyPassword))
        setup(deleteButton, symbol: "trash", action: #selector(handleDelete))
        deleteButton.hasDestructiveAction = true
        setup(saveButton, symbol: "checkmark", action: #selector(handleSave))
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.fittingSizeCompression, for: .horizontal)
        let actions = NSStackView(views: [copyAccountButton, copyPasswordButton, spacer, deleteButton, saveButton])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let heading = ToolAppearance.sectionTitle(L10n.text("island.passwordBook", "密码本"), symbol: "lock.shield")
        let formCard = ToolAppearance.section(form)
        let stack = NSStackView(views: [heading, formCard, actions, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        for view in [formCard, actions, status] {
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -14)
        ])

        populatePicker(selecting: nil)
    }

    private func label(_ title: String) -> NSTextField {
        let field = NSTextField(labelWithString: title)
        field.textColor = .secondaryLabelColor
        return field
    }

    private func setup(_ button: NSButton, symbol: String, action: Selector) {
        ToolAppearance.configure(button, symbol: symbol)
        button.target = self
        button.action = action
    }

    private func populatePicker(selecting id: UUID?) {
        recordPicker.removeAllItems()
        recordPicker.addItem(withTitle: L10n.text("passwords.newEntry", "新增记录"))
        for entry in entries {
            recordPicker.menu?.addItem(NSMenuItem(title: "\(entry.website) — \(entry.account)", action: nil, keyEquivalent: ""))
        }
        let index = entries.firstIndex { $0.id == id }.map { $0 + 1 } ?? 0
        recordPicker.selectItem(at: index)
        showSelectedEntry()
    }

    private func showSelectedEntry() {
        let entry = selectedEntry
        websiteField.stringValue = entry?.website ?? ""
        accountField.stringValue = entry?.account ?? ""
        passwordField.stringValue = ""
        passwordField.placeholderString = entry == nil ? L10n.text("passwords.enterPassword", "输入密码") : L10n.text("passwords.leaveBlankToKeepTheSavedPassword", "留空保留已保存的密码")
        saveButton.title = entry == nil ? L10n.text("passwords.save", "保存") : L10n.text("passwords.update", "更新")
        updateControls()
    }

    private func updateControls() {
        let canEdit = !isBusy && hasLoadedEntries
        recordPicker.isEnabled = canEdit
        [websiteField, accountField, passwordField].forEach { $0.isEnabled = canEdit }
        copyAccountButton.isEnabled = canEdit && selectedEntry != nil
        copyPasswordButton.isEnabled = canEdit && selectedEntry != nil
        deleteButton.isEnabled = canEdit && selectedEntry != nil
        saveButton.isEnabled = canEdit
    }

    private func perform<T>(_ operation: @escaping (PasswordBookStore) throws -> T, then complete: @escaping (T) -> Void) {
        guard !isBusy else { return }
        isBusy = true
        updateControls()
        keychainQueue.async { [store, weak self] in
            let result = Result { try operation(store) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                isBusy = false
                updateControls()
                switch result {
                case .success(let value): complete(value)
                case .failure(let error): status.stringValue = error.localizedDescription
                }
            }
        }
    }

    private func loadEntries(selecting id: UUID?) {
        guard !isBusy else { return }
        hasLoadedEntries = false
        status.stringValue = L10n.text("passwords.readingTheKeychain", "正在读取钥匙串…")
        perform({ try $0.entries() }) { [weak self] entries in
            guard let self else { return }
            hasLoadedEntries = true
            self.entries = entries
            populatePicker(selecting: id)
            status.stringValue = entries.isEmpty ? L10n.text("passwords.noSavedEntriesYet", "还没有保存的记录。") : ""
            if window?.isKeyWindow == true { window?.makeFirstResponder(websiteField) }
        }
    }

    @objc private func handleRecordChange() {
        showSelectedEntry()
        status.stringValue = ""
    }

    @objc private func handleSave() {
        let website = websiteField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = accountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        let existing = selectedEntry
        guard !website.isEmpty, !account.isEmpty, existing != nil || !password.isEmpty else {
            status.stringValue = L10n.text("passwords.enterAWebsiteAccountAndPassword", "请填写网站名称、账户和密码。")
            return
        }

        let entry = PasswordBookEntry(id: existing?.id ?? UUID(), website: website, account: account)
        perform({ try $0.save(entry, password: password.isEmpty ? nil : password, isNew: existing == nil) }) { [weak self] _ in
            guard let self else { return }
            entries.removeAll { $0.id == entry.id }
            entries.append(entry)
            PasswordBookStore.sort(&entries)
            populatePicker(selecting: entry.id)
            status.stringValue = L10n.text("passwords.savedToTheKeychain", "已保存至钥匙串。")
        }
    }

    @objc private func handleDelete() {
        guard !isBusy, let entry = selectedEntry, let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = L10n.text("passwords.deleteThisPasswordEntry", "删除这条密码记录？")
        alert.informativeText = L10n.text("passwords.willBeRemovedFromTheLocalKeychain", "{arg1} · {arg2} 将从本机钥匙串移除。", ["arg1": String(describing: entry.website), "arg2": String(describing: entry.account)])
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("passwords.delete", "删除")).hasDestructiveAction = true
        let cancel = alert.addButton(withTitle: L10n.text("passwords.cancel", "取消"))
        cancel.keyEquivalent = "\r"
        alert.buttons[0].keyEquivalent = ""
        alert.beginSheetModal(for: window) { [weak self] result in
            guard result == .alertFirstButtonReturn, let self else { return }
            perform({ try $0.delete(id: entry.id) }) { [weak self] _ in
                guard let self else { return }
                entries.removeAll { $0.id == entry.id }
                populatePicker(selecting: nil)
                status.stringValue = L10n.text("passwords.entryDeleted", "已删除记录。")
            }
        }
    }

    @objc private func handleCopyAccount() {
        guard let entry = selectedEntry else { return }
        ClipboardHelper.copyText(entry.account)
        status.stringValue = L10n.text("passwords.accountCopied", "已复制账户。")
    }

    @objc private func handleCopyPassword() {
        guard let entry = selectedEntry else { return }
        perform({ try $0.password(for: entry.id) }) { [weak self] password in
            guard let self, window?.isVisible == true else { return }
            status.stringValue = ClipboardHelper.copyPassword(password)
                ? L10n.text("passwords.passwordCopiedItWillBeClearedAfter", "已复制密码。若剪贴板内容未改变，将在 45 秒后清除。")
                : L10n.text("passwords.couldNotCopyThePassword", "无法复制密码。")
        }
    }
}
