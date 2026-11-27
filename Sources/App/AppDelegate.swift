import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var backgroundStatusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        restorePreferencesFromSandbox()
        setupMainMenu()
        let controller = MainWindowController(tools: ToolRegistry.defaultTools())
        controller.onWindowShouldClose = { [weak self] window in
            self?.hideMainWindowToBackground(window)
            return false
        }
        controller.showWindow(nil)
        self.mainWindowController = controller

        DynamicIslandManager.shared.onOpenMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        DynamicIslandManager.shared.startIfEnabled()
        NSApp.activate(ignoringOtherApps: true)
        configureMarkdownQuickLook()

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
            button.toolTip = "MakeTools 后台运行中"
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "打开 MakeTools 主窗口", action: #selector(openMainWindowFromMenu(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "显示 / 隐藏灵动岛", action: #selector(toggleDynamicIslandEnabled(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "展开 / 收起灵动岛", action: #selector(toggleDynamicIslandExpand(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出 MakeTools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
            alert.messageText = "访达 Markdown 快速预览设置失败"
            let settingsPath: String
            if #available(macOS 15, *) {
                settingsPath = "系统设置 → 通用 → 登录项与扩展 → 快速查看"
            } else {
                settingsPath = "系统设置 → 隐私与安全性 → 扩展 → 快速查看"
            }
            alert.informativeText = """
            请在「\(settingsPath)」启用 MakeTools 的 Markdown 预览扩展，再在访达选中 Markdown 文件并按空格试用。

            如果列表中没有 MakeTools，请将应用拖入「应用程序」文件夹，从该文件夹重新打开。
            """
            alert.addButton(withTitle: "打开系统设置")
            alert.addButton(withTitle: "稍后")
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
        appMenu.addItem(withTitle: "关于 MakeTools", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 MakeTools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "打开 Markdown 文件...", action: #selector(openMarkdownDocument(_:)), keyEquivalent: "o")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "关闭窗口", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        let islandMenuItem = NSMenuItem()
        let islandMenu = NSMenu(title: "灵动岛")
        islandMenu.addItem(withTitle: "显示 / 隐藏灵动岛", action: #selector(toggleDynamicIslandEnabled(_:)), keyEquivalent: "")
        let expandItem = NSMenuItem(title: "展开 / 收起灵动岛", action: #selector(toggleDynamicIslandExpand(_:)), keyEquivalent: "d")
        expandItem.keyEquivalentModifierMask = [.command, .shift]
        islandMenu.addItem(expandItem)
        islandMenuItem.submenu = islandMenu
        mainMenu.addItem(islandMenuItem)

        NSApp.mainMenu = mainMenu
    }
}
