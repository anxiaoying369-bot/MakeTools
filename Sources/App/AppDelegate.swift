import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var backgroundStatusItem: NSStatusItem?
    private var languageSettings: LanguageSettingsWindow?
    private var pendingLanguageRefresh: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        restorePreferencesFromSandbox()
        setupMainMenu()
        installMainWindow().showWindow(nil)
        NotificationCenter.default.addObserver(self, selector: #selector(languageDidChange),
                                               name: Localization.didChange, object: nil)
        DynamicIslandManager.shared.onOpenMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        DynamicIslandManager.shared.startIfEnabled()
        NSApp.activate(ignoringOtherApps: true)
        configureMarkdownQuickLook()

    }

    private func installMainWindow(toolID: String? = nil) -> MainWindowController {
        let controller = MainWindowController(tools: ToolRegistry.defaultTools(), initialToolID: toolID)
        controller.onWindowShouldClose = { [weak self] window in
            self?.hideMainWindowToBackground(window)
            return false
        }
        controller.onOpenLanguageSettings = { [weak self] in self?.openLanguageSettings() }
        mainWindowController = controller
        return controller
    }

    @objc private func languageDidChange() {
        setupMainMenu()
        if backgroundStatusItem != nil {
            removeBackgroundStatusItem()
            installBackgroundStatusItem()
        }
        DynamicIslandManager.shared.reloadLocalizedInterface()
        reloadLocalizedMainWindow()
    }

    private func reloadLocalizedMainWindow() {
        if let window = mainWindowController?.window, window.attachedSheet != nil {
            guard pendingLanguageRefresh == nil else { return }
            pendingLanguageRefresh = NotificationCenter.default.addObserver(
                forName: NSWindow.didEndSheetNotification, object: window, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.reloadLocalizedMainWindow() }
            }
            return
        }
        if let pendingLanguageRefresh {
            NotificationCenter.default.removeObserver(pendingLanguageRefresh)
            self.pendingLanguageRefresh = nil
        }

        // Rebuild static AppKit labels while keeping the managers and the active upload session.
        let previous = mainWindowController
        let visible = previous?.window?.isVisible == true
        let controller = installMainWindow(toolID: previous?.selectedToolID)
        if let frame = previous?.window?.frame {
            controller.window?.setFrame(frame, display: false)
        }
        if let preview = previous?.markdownPreview {
            controller.restoreMarkdownPreview(preview)
        }
        previous?.window?.orderOut(nil)
        if visible { controller.window?.orderFront(nil) }
    }

    @objc private func openLanguageSettings() {
        if languageSettings == nil { languageSettings = LanguageSettingsWindow() }
        languageSettings?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        languageSettings?.window?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showMainWindow()
        }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeBackgroundStatusItem()
        DynamicIslandManager.shared.shutdown()
        LANTransferController.shared.shutdown()
    }

    func application(_ sender: NSApplication, open urls: [URL]) {
        showMainWindow()
        if let first = urls.first {
            mainWindowController?.openMarkdownFile(at: first)
        }
    }

    @objc private func openMainWindowFromMenu(_ sender: Any?) {
        showMainWindow()
    }

    private func hideMainWindowToBackground(_ window: NSWindow) {
        window.orderOut(nil)
        installBackgroundStatusItem()
        if NSApp.activationPolicy() != .accessory {
            NSApp.setActivationPolicy(.accessory)
        }
        DispatchQueue.main.async {
            DynamicIslandManager.shared.ensureOverlayVisible()
        }
    }

    private func showMainWindow() {
        removeBackgroundStatusItem()
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.mainWindowController?.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func installBackgroundStatusItem() {
        guard backgroundStatusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "MakeTools")
            button.toolTip = L10n.text("menu.maketoolsIsRunningInTheBackground", "MakeTools 后台运行中")
        }
        let menu = NSMenu()
        menu.addItem(withTitle: L10n.text("menu.openMaketools", "打开 MakeTools 主窗口"), action: #selector(openMainWindowFromMenu(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("menu.showOrHideDynamicIsland", "显示 / 隐藏灵动岛"), action: #selector(toggleDynamicIslandEnabled(_:)), keyEquivalent: "")
        menu.addItem(withTitle: L10n.text("menu.expandOrCollapseDynamicIsland", "展开 / 收起灵动岛"), action: #selector(toggleDynamicIslandExpand(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.text("menu.quitMaketools", "退出 MakeTools"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        backgroundStatusItem = item
    }

    private func removeBackgroundStatusItem() {
        if let item = backgroundStatusItem {
            NSStatusBar.system.removeStatusItem(item)
            backgroundStatusItem = nil
        }
    }

    @objc private func openMarkdownDocument(_ sender: Any?) {
        mainWindowController?.openMarkdownPicker()
    }

    private func restorePreferencesFromSandbox() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let defaults = UserDefaults.standard
        let migrationKey = "MakeTools.didRestoreSandboxPreferences"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let oldPreferencesURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/\(bundleID)/Data/Library/Preferences/\(bundleID).plist")
        if let data = try? Data(contentsOf: oldPreferencesURL),
           let preferences = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] {
            for (key, value) in preferences where key.hasPrefix("MakeTools.") && defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        defaults.set(true, forKey: migrationKey)
    }

    private func configureMarkdownQuickLook() {
        let service = InstallationService.shared
        service.registerQuickLookExtension(for: service.currentRunningAppURL()) { [weak self] outcome in
            guard !outcome.succeeded, let window = self?.mainWindowController?.window else { return }

            let alert = NSAlert()
            alert.messageText = L10n.text("menu.finderMarkdownQuickLookSetupFailed", "访达 Markdown 快速预览设置失败")
            let settingsPath: String
            if #available(macOS 15, *) {
                settingsPath = L10n.text("menu.systemSettingsGeneralLoginItemsExtensionsQuick", "系统设置 → 通用 → 登录项与扩展 → 快速查看")
            } else {
                settingsPath = L10n.text("menu.systemSettingsPrivacySecurityExtensionsQuickLook", "系统设置 → 隐私与安全性 → 扩展 → 快速查看")
            }
            alert.informativeText = L10n.text("menu.enableTheMaketoolsMarkdownPreviewExtensionIn", "请在「{arg1}」启用 MakeTools 的 Markdown 预览扩展，再在访达选中 Markdown 文件并按空格试用。\n\n如果列表中没有 MakeTools，请将应用拖入「应用程序」文件夹，从该文件夹重新打开。", ["arg1": String(describing: settingsPath)])
            alert.addButton(withTitle: L10n.text("menu.openSystemSettings", "打开系统设置"))
            alert.addButton(withTitle: L10n.text("menu.later", "稍后"))
            alert.beginSheetModal(for: window) { response in
                if response == .alertFirstButtonReturn {
                    service.openExtensionsSettings()
                }
            }
        }
    }

    @objc private func toggleDynamicIslandEnabled(_ sender: Any?) {
        DynamicIslandManager.shared.setEnabled(!DynamicIslandManager.shared.isEnabled)
    }

    @objc private func toggleDynamicIslandExpand(_ sender: Any?) {
        DynamicIslandManager.shared.toggleExpanded()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: L10n.text("menu.aboutMaketools", "关于 MakeTools"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: L10n.text("language.menu", "语言设置…"),
                        action: #selector(openLanguageSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: L10n.text("menu.quitMaketools", "退出 MakeTools"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: L10n.text("menu.file", "文件"))
        fileMenu.addItem(withTitle: L10n.text("menu.openMarkdownFile", "打开 Markdown 文件..."), action: #selector(openMarkdownDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: L10n.text("menu.closeWindow", "关闭窗口"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: L10n.text("menu.edit", "编辑"))
        editMenu.addItem(withTitle: L10n.text("menu.copy", "拷贝"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: L10n.text("menu.selectAll", "全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let islandMenuItem = NSMenuItem()
        let islandMenu = NSMenu(title: L10n.text("menu.dynamicIsland", "灵动岛"))
        islandMenu.addItem(withTitle: L10n.text("menu.showOrHideDynamicIsland", "显示 / 隐藏灵动岛"), action: #selector(toggleDynamicIslandEnabled(_:)), keyEquivalent: "")
        let expandItem = NSMenuItem(title: L10n.text("menu.expandOrCollapseDynamicIsland", "展开 / 收起灵动岛"), action: #selector(toggleDynamicIslandExpand(_:)), keyEquivalent: "d")
        expandItem.keyEquivalentModifierMask = [.command, .shift]
        islandMenu.addItem(expandItem)
        islandMenuItem.submenu = islandMenu
        mainMenu.addItem(islandMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
