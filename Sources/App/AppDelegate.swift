import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var backgroundStatusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        let installService = InstallationService.shared
        let runningVersion = installService.currentRunningVersion()
        let installStatus = InstallationInspector.classifyInstallStatus(
            runningAppURL: installService.currentRunningAppURL(),
            runningVersion: runningVersion
        )
        let initialToolID = installService.preferences.shouldOpenOnLaunch(
            installStatus: installStatus,
            runningVersion: runningVersion
        ) ? "installation-guide" : nil

        let controller = MainWindowController(
            tools: ToolRegistry.defaultTools(),
            initialToolID: initialToolID
        )
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
        menu.addItem(withTitle: "安装与引导…", action: #selector(openInstallationGuide(_:)), keyEquivalent: "")
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

    @objc private func openInstallationGuide(_ sender: Any?) {
        showMainWindow()
        mainWindowController?.openInstallationGuide()
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
        appMenu.addItem(withTitle: "安装与引导…", action: #selector(openInstallationGuide(_:)), keyEquivalent: "")
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
