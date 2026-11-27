import AppKit
import Darwin
import Foundation
import ServiceManagement

/// Comparable representation of a macOS bundle version (`CFBundleShortVersionString` + `CFBundleVersion`).
public struct AppVersion: Equatable, Comparable, CustomStringConvertible {
    public let shortVersion: String
    public let buildNumber: String?

    public init(shortVersion: String, buildNumber: String? = nil) {
        let trimmedShort = shortVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        self.shortVersion = trimmedShort.isEmpty ? "0.0.0" : trimmedShort
        let trimmedBuild = buildNumber?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.buildNumber = (trimmedBuild?.isEmpty == false) ? trimmedBuild : nil
    }

    public var displayString: String {
        if let buildNumber {
            return "v\(shortVersion) (\(buildNumber))"
        }
        return "v\(shortVersion)"
    }

    public var description: String { displayString }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let leftParts = numericComponents(of: lhs.shortVersion)
        let rightParts = numericComponents(of: rhs.shortVersion)
        let count = max(leftParts.count, rightParts.count)
        for index in 0..<count {
            let l = index < leftParts.count ? leftParts[index] : 0
            let r = index < rightParts.count ? rightParts[index] : 0
            if l != r {
                return l < r
            }
        }
        let leftSuffix = nonNumericSuffix(of: lhs.shortVersion)
        let rightSuffix = nonNumericSuffix(of: rhs.shortVersion)
        if leftSuffix != rightSuffix {
            if leftSuffix.isEmpty { return false }
            if rightSuffix.isEmpty { return true }
            return leftSuffix.localizedStandardCompare(rightSuffix) == .orderedAscending
        }
        if let lb = lhs.buildNumber, let rb = rhs.buildNumber {
            let lbParts = numericComponents(of: lb)
            let rbParts = numericComponents(of: rb)
            let bCount = max(lbParts.count, rbParts.count)
            for index in 0..<bCount {
                let l = index < lbParts.count ? lbParts[index] : 0
                let r = index < rbParts.count ? rbParts[index] : 0
                if l != r {
                    return l < r
                }
            }
            return false
        }
        return false
    }

    private static func numericComponents(of version: String) -> [Int] {
        let numericPrefix = version.prefix { $0.isNumber || $0 == "." }
        return numericPrefix.split(separator: ".").map { Int($0) ?? 0 }
    }

    private static func nonNumericSuffix(of version: String) -> String {
        String(version.drop { $0.isNumber || $0 == "." })
    }
}

/// Describes where MakeTools is currently running relative to standard macOS Applications folders.
public enum AppInstallStatus: Equatable {
    case runningFromApplications(appURL: URL, version: AppVersion)
    case updateAvailable(installedURL: URL, installedVersion: AppVersion, runningVersion: AppVersion)
    case installedSameOrNewer(installedURL: URL, installedVersion: AppVersion, runningVersion: AppVersion)
    case translocated(runningVersion: AppVersion)
    case notInstalled(runningVersion: AppVersion)

    public var isRunningFromApplications: Bool {
        if case .runningFromApplications = self { return true }
        return false
    }

    public var isInstalledInApplications: Bool {
        switch self {
        case .runningFromApplications, .updateAvailable, .installedSameOrNewer:
            return true
        case .translocated, .notInstalled:
            return false
        }
    }

    public var isInstalledAndUpToDate: Bool {
        switch self {
        case .runningFromApplications, .installedSameOrNewer:
            return true
        case .updateAvailable, .translocated, .notInstalled:
            return false
        }
    }

    public var installedAppURL: URL? {
        switch self {
        case .runningFromApplications(let url, _),
             .updateAvailable(let url, _, _),
             .installedSameOrNewer(let url, _, _):
            return url
        case .translocated, .notInstalled:
            return nil
        }
    }

    public var badgeText: String {
        switch self {
        case .runningFromApplications:
            return "已安装"
        case .updateAvailable:
            return "可更新"
        case .installedSameOrNewer:
            return "未从安装目录启动"
        case .translocated:
            return "运行在隔离路径"
        case .notInstalled:
            return "未安装"
        }
    }

    public var summaryText: String {
        switch self {
        case .runningFromApplications(let appURL, let version):
            return "当前正从 \(appURL.path) 运行 \(version.displayString)，安装位置正常。"
        case .updateAvailable(let installedURL, let installedVersion, let runningVersion):
            return "\(installedURL.path) 中已安装旧版本 \(installedVersion.displayString)，当前运行 \(runningVersion.displayString)，建议一键更新。"
        case .installedSameOrNewer(let installedURL, let installedVersion, _):
            return "\(installedURL.path) 中已存在 \(installedVersion.displayString)，但当前进程从其他位置启动，建议从「应用程序」打开。"
        case .translocated:
            return "当前应用正运行在 macOS App Translocation 临时只读路径中，移入「应用程序」后才能稳定使用 Quick Look 扩展和开机自启。"
        case .notInstalled:
            return "当前未在「应用程序」中检测到 MakeTools.app。安装到 /Applications 后，Quick Look 扩展、系统启动与后续更新都会更稳定。"
        }
    }
}

public struct QuickLookExtensionInfo: Equatable {
    public let bundleIdentifier: String
    public let displayName: String
    public let version: AppVersion
    public let extensionURL: URL
}

public struct QuickLookCheckResult: Equatable {
    public let targetAppURL: URL
    public let embeddedExtension: QuickLookExtensionInfo?
    public let registeredAppURLs: [URL]
    public let lastRegisteredAt: Date?
    public let registeredForCurrentTarget: Bool

    public var hasEmbeddedExtension: Bool {
        embeddedExtension != nil
    }

    public var hasMultipleRegisteredCopies: Bool {
        let uniquePaths = Set(registeredAppURLs.map { $0.standardizedFileURL.resolvingSymlinksInPath().path })
        return uniquePaths.count > 1
    }

    public var badgeText: String {
        guard hasEmbeddedExtension else { return "缺少扩展" }
        return registeredForCurrentTarget ? "已提交注册" : "待注册"
    }
}

public enum LoginItemState: Equatable {
    case enabled
    case requiresApproval
    case notRegistered
    case notFound

    public var badgeText: String {
        switch self {
        case .enabled: return "已开启"
        case .requiresApproval: return "需系统批准"
        case .notRegistered: return "未开启"
        case .notFound: return "需先安装"
        }
    }

    public var detailText: String {
        switch self {
        case .enabled:
            return "MakeTools 已加入系统登录项，开机登录后会自动启动。"
        case .requiresApproval:
            return "已请求开机自启，请前往「系统设置 → 通用 → 登录项与扩展」允许 MakeTools。"
        case .notRegistered:
            return "当前未启用开机自动启动，可随时通过下方开关开启。"
        case .notFound:
            return "请先将 MakeTools 安装并从「应用程序」启动，再开启开机自动启动。"
        }
    }
}

public struct InstallationProgressSummary: Equatable {
    public let completedSteps: Int
    public let totalSteps: Int
    public let isCoreReady: Bool

    public var fraction: Double {
        guard totalSteps > 0 else { return 1 }
        return Double(completedSteps) / Double(totalSteps)
    }

    public var title: String {
        if completedSteps >= totalSteps {
            return "所有推荐安装步骤已就绪"
        }
        return "已完成 \(completedSteps) / \(totalSteps) 项核心准备"
    }
}

public struct InstallationSnapshot: Equatable {
    public let runningAppURL: URL
    public let runningVersion: AppVersion
    public let osVersion: String
    public let architecture: String
    public let installStatus: AppInstallStatus
    public let legacyAppURL: URL?
    public let quickLook: QuickLookCheckResult
    public let loginItemState: LoginItemState
    public let dynamicIslandEnabled: Bool

    public var progress: InstallationProgressSummary {
        var done = 0
        let total = 3
        if installStatus.isRunningFromApplications { done += 1 }
        if quickLook.hasEmbeddedExtension && quickLook.registeredForCurrentTarget { done += 1 }
        if dynamicIslandEnabled { done += 1 }
        let coreReady = installStatus.isRunningFromApplications && quickLook.hasEmbeddedExtension
        return InstallationProgressSummary(completedSteps: done, totalSteps: total, isCoreReady: coreReady)
    }
}

/// Persistent preferences for the onboarding & installation page.
public struct InstallationPreferences {
    private enum Key {
        static let dismissedOnboardingVersion = "MakeTools.Installation.dismissedOnboardingVersion"
        static let lastRegisteredAppPath = "MakeTools.Installation.lastRegisteredAppPath"
        static let lastRegisteredVersion = "MakeTools.Installation.lastRegisteredVersion"
        static let lastRegisteredTimestamp = "MakeTools.Installation.lastRegisteredTimestamp"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var dismissedOnboardingVersion: String? {
        get { defaults.string(forKey: Key.dismissedOnboardingVersion) }
        nonmutating set {
            if let newValue {
                defaults.set(newValue, forKey: Key.dismissedOnboardingVersion)
            } else {
                defaults.removeObject(forKey: Key.dismissedOnboardingVersion)
            }
        }
    }

    public var lastRegisteredAppPath: String? {
        defaults.string(forKey: Key.lastRegisteredAppPath)
    }

    public var lastRegisteredVersion: String? {
        defaults.string(forKey: Key.lastRegisteredVersion)
    }

    public var lastRegisteredAt: Date? {
        let interval = defaults.double(forKey: Key.lastRegisteredTimestamp)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    public func markOnboardingCompleted(for version: AppVersion) {
        dismissedOnboardingVersion = version.shortVersion
    }

    public func recordQuickLookRegistration(appURL: URL, version: AppVersion, at date: Date = Date()) {
        let normalized = appURL.standardizedFileURL.resolvingSymlinksInPath().path
        defaults.set(normalized, forKey: Key.lastRegisteredAppPath)
        defaults.set(version.displayString, forKey: Key.lastRegisteredVersion)
        defaults.set(date.timeIntervalSince1970, forKey: Key.lastRegisteredTimestamp)
    }

    public func isQuickLookRegistered(for appURL: URL, version: AppVersion) -> Bool {
        let normalized = appURL.standardizedFileURL.resolvingSymlinksInPath().path
        return lastRegisteredAppPath == normalized && lastRegisteredVersion == version.displayString
    }

    /// Opens the installation page automatically on launch when the app is not yet running from Applications
    /// and the user has not dismissed onboarding for the current version.
    public func shouldOpenOnLaunch(installStatus: AppInstallStatus, runningVersion: AppVersion) -> Bool {
        guard !installStatus.isRunningFromApplications else { return false }
        return dismissedOnboardingVersion != runningVersion.shortVersion
    }
}

/// Pure helpers for classifying install status, reading bundle metadata, and generating shell fallback commands.
public enum InstallationInspector {
    public static let appBundleName = "MakeTools.app"
    public static let appBundleIdentifier = "com.make.MakeTools"
    public static let quickLookExtensionName = "MarkdownQuickLook.appex"
    public static let quickLookExtensionIdentifier = "com.make.MakeTools.MarkdownQuickLook"
    public static let legacyAppBundleName = "MarkdownQuickLook.app"
    public static let lsregisterPath = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

    /// Resolves the actual user home directory even when running inside App Sandbox.
    public static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    public static func standardApplicationDirectories(
        systemApplications: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        userApplications: URL? = nil
    ) -> [URL] {
        let resolvedUserApps = userApplications ?? realHomeDirectory().appendingPathComponent("Applications", isDirectory: true)
        return [systemApplications, resolvedUserApps]
    }

    public static func isTranslocated(bundleURL: URL) -> Bool {
        bundleURL.path.contains("/AppTranslocation/")
    }

    public static func isInsideStandardApplications(
        bundleURL: URL,
        applicationDirectories: [URL]
    ) -> Bool {
        let normalizedBundleParent = bundleURL.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent().path
        for directory in applicationDirectories {
            let normalizedDir = directory.standardizedFileURL.resolvingSymlinksInPath().path
            if normalizedBundleParent == normalizedDir {
                return true
            }
        }
        return false
    }

    public static func readBundleVersion(at bundleURL: URL) -> AppVersion? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any],
              let short = dict["CFBundleShortVersionString"] as? String else {
            return nil
        }
        let build = dict["CFBundleVersion"] as? String
        return AppVersion(shortVersion: short, buildNumber: build)
    }

    public static func readEmbeddedQuickLookExtension(in appURL: URL) -> QuickLookExtensionInfo? {
        let extURL = appURL
            .appendingPathComponent("Contents/PlugIns", isDirectory: true)
            .appendingPathComponent(quickLookExtensionName, isDirectory: true)
        let plistURL = extURL.appendingPathComponent("Contents/Info.plist")
        guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any],
              let bundleID = dict["CFBundleIdentifier"] as? String,
              let shortVersion = dict["CFBundleShortVersionString"] as? String else {
            return nil
        }
        let displayName = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? "MakeTools Markdown 预览"
        let build = dict["CFBundleVersion"] as? String
        return QuickLookExtensionInfo(
            bundleIdentifier: bundleID,
            displayName: displayName,
            version: AppVersion(shortVersion: shortVersion, buildNumber: build),
            extensionURL: extURL
        )
    }

    public static func classifyInstallStatus(
        runningAppURL: URL,
        runningVersion: AppVersion,
        systemApplicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        userApplicationsURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> AppInstallStatus {
        let normalizedRunning = runningAppURL.standardizedFileURL.resolvingSymlinksInPath()
        let appDirs = standardApplicationDirectories(
            systemApplications: systemApplicationsURL,
            userApplications: userApplicationsURL
        )

        if isInsideStandardApplications(bundleURL: normalizedRunning, applicationDirectories: appDirs) {
            return .runningFromApplications(appURL: normalizedRunning, version: runningVersion)
        }

        for dir in appDirs {
            let candidate = dir.appendingPathComponent(appBundleName, isDirectory: true)
            if fileManager.fileExists(atPath: candidate.path) {
                let installedVersion = readBundleVersion(at: candidate) ?? AppVersion(shortVersion: "0.0.0")
                if installedVersion < runningVersion {
                    return .updateAvailable(
                        installedURL: candidate,
                        installedVersion: installedVersion,
                        runningVersion: runningVersion
                    )
                }
                return .installedSameOrNewer(
                    installedURL: candidate,
                    installedVersion: installedVersion,
                    runningVersion: runningVersion
                )
            }
        }

        if isTranslocated(bundleURL: runningAppURL) {
            return .translocated(runningVersion: runningVersion)
        }

        return .notInstalled(runningVersion: runningVersion)
    }

    public static func detectLegacyApp(
        in systemApplicationsURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true),
        fileManager: FileManager = .default
    ) -> URL? {
        let legacyURL = systemApplicationsURL.appendingPathComponent(legacyAppBundleName, isDirectory: true)
        return fileManager.fileExists(atPath: legacyURL.path) ? legacyURL : nil
    }

    public static func currentArchitectureLabel() -> String {
        #if arch(arm64)
        return "arm64（Apple 芯片）"
        #elseif arch(x86_64)
        return "x86_64（Intel）"
        #else
        return "macOS"
        #endif
    }

    public static func currentOSVersionString() -> String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }
}

/// Builds safely escaped shell commands as a fallback when users prefer Terminal or lack folder write permissions.
public enum InstallationCommandBuilder {
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public static func terminalInstallCommand(
        sourceAppURL: URL,
        destinationDirectoryURL: URL = URL(fileURLWithPath: "/Applications", isDirectory: true)
    ) -> String {
        let destApp = destinationDirectoryURL.appendingPathComponent(InstallationInspector.appBundleName)
        let extPath = destApp
            .appendingPathComponent("Contents/PlugIns")
            .appendingPathComponent(InstallationInspector.quickLookExtensionName)
        let srcQ = shellQuote(sourceAppURL.path)
        let dstQ = shellQuote(destApp.path)
        let extQ = shellQuote(extPath.path)
        let lsrQ = shellQuote(InstallationInspector.lsregisterPath)
        let extID = InstallationInspector.quickLookExtensionIdentifier

        return [
            "rm -rf \(dstQ)",
            "cp -R \(srcQ) \(dstQ)",
            "xattr -dr com.apple.quarantine \(dstQ) 2>/dev/null || true",
            "\(lsrQ) -f -R \(dstQ)",
            "pluginkit -a \(extQ)",
            "pluginkit -e use -i \(extID)",
            "qlmanage -r",
            "qlmanage -r cache"
        ].joined(separator: " && ")
    }

    public static var quickLookVerifyCommand: String {
        "pluginkit -m -v -p com.apple.quicklook.preview | grep -i MakeTools"
    }

    public static func quarantineClearCommand(appURL: URL) -> String {
        "xattr -dr com.apple.quarantine \(shellQuote(appURL.path))"
    }
}

/// Errors that can occur when copying the application bundle into a user-authorized directory.
public enum AppBundleInstallError: LocalizedError, Equatable {
    case sourceBundleInvalid(String)
    case destinationNotDirectory(String)
    case destinationInsideSource
    case copyFailed(String)

    public var errorDescription: String? {
        switch self {
        case .sourceBundleInvalid(let path):
            return "当前应用包路径无效：\(path)"
        case .destinationNotDirectory(let path):
            return "所选安装位置不是有效文件夹：\(path)"
        case .destinationInsideSource:
            return "不能将应用安装到其自身目录内部，请选择「应用程序」文件夹。"
        case .copyFailed(let reason):
            return "复制应用包失败：\(reason)"
        }
    }
}

public enum AppBundleCopyOutcome: Equatable {
    case installedFresh(destinationURL: URL)
    case replacedExisting(destinationURL: URL)
    case alreadyInPlace(destinationURL: URL)

    public var destinationURL: URL {
        switch self {
        case .installedFresh(let url), .replacedExisting(let url), .alreadyInPlace(let url):
            return url
        }
    }
}

/// Safely copies and atomically replaces `MakeTools.app` inside a user-authorized target directory.
public enum AppBundleInstaller {
    public static func install(
        sourceAppURL: URL,
        into destinationDirectoryURL: URL,
        appBundleName: String = InstallationInspector.appBundleName,
        fileManager: FileManager = .default
    ) throws -> AppBundleCopyOutcome {
        let source = sourceAppURL.standardizedFileURL.resolvingSymlinksInPath()
        let destDir = destinationDirectoryURL.standardizedFileURL.resolvingSymlinksInPath()

        var sourceIsDir: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &sourceIsDir),
              sourceIsDir.boolValue,
              source.pathExtension == "app" else {
            throw AppBundleInstallError.sourceBundleInvalid(source.path)
        }

        var destIsDir: ObjCBool = false
        guard fileManager.fileExists(atPath: destDir.path, isDirectory: &destIsDir),
              destIsDir.boolValue else {
            throw AppBundleInstallError.destinationNotDirectory(destDir.path)
        }

        let destinationAppURL = destDir.appendingPathComponent(appBundleName, isDirectory: true)
        if source.path == destinationAppURL.path {
            return .alreadyInPlace(destinationURL: destinationAppURL)
        }

        let sourcePrefix = source.path.hasSuffix("/") ? source.path : source.path + "/"
        if destDir.path.hasPrefix(sourcePrefix) || destinationAppURL.path.hasPrefix(sourcePrefix) {
            throw AppBundleInstallError.destinationInsideSource
        }

        let stagingURL = destDir.appendingPathComponent(".\(appBundleName).staging-\(UUID().uuidString)", isDirectory: true)
        defer {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        do {
            try fileManager.copyItem(at: source, to: stagingURL)
            if fileManager.fileExists(atPath: destinationAppURL.path) {
                _ = try fileManager.replaceItemAt(
                    destinationAppURL,
                    withItemAt: stagingURL,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
                return .replacedExisting(destinationURL: destinationAppURL)
            } else {
                try fileManager.moveItem(at: stagingURL, to: destinationAppURL)
                return .installedFresh(destinationURL: destinationAppURL)
            }
        } catch {
            throw AppBundleInstallError.copyFailed(error.localizedDescription)
        }
    }

    @discardableResult
    public static func removeLegacyAppIfPresent(
        in destinationDirectoryURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let legacyURL = destinationDirectoryURL.appendingPathComponent(
            InstallationInspector.legacyAppBundleName,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: legacyURL.path) else { return false }
        do {
            try fileManager.removeItem(at: legacyURL)
            return true
        } catch {
            return false
        }
    }
}

/// Result of registering an app bundle and its Quick Look extension with macOS.
public struct RegistrationOutcome: Equatable {
    public let succeeded: Bool
    public let steps: [String]
    public let warning: String?
}

/// Coordinates environment inspection, in-app installation, Quick Look registration, and Login Item management.
public final class InstallationService {
    public static let shared = InstallationService()

    public let preferences: InstallationPreferences

    public init(preferences: InstallationPreferences = InstallationPreferences()) {
        self.preferences = preferences
    }

    public func currentRunningAppURL() -> URL {
        Bundle.main.bundleURL
    }

    public func currentRunningVersion() -> AppVersion {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return AppVersion(shortVersion: short, buildNumber: build)
    }

    public func makeSnapshot(dynamicIslandEnabled: Bool) -> InstallationSnapshot {
        let runningURL = currentRunningAppURL()
        let runningVersion = currentRunningVersion()
        let installStatus = InstallationInspector.classifyInstallStatus(
            runningAppURL: runningURL,
            runningVersion: runningVersion
        )
        let targetAppURL = installStatus.installedAppURL ?? runningURL
        let targetVersion = InstallationInspector.readBundleVersion(at: targetAppURL) ?? runningVersion
        let embeddedExt = InstallationInspector.readEmbeddedQuickLookExtension(in: targetAppURL)
        let registeredURLs = NSWorkspace.shared.urlsForApplications(
            withBundleIdentifier: InstallationInspector.appBundleIdentifier
        )
        let registeredRecently = preferences.isQuickLookRegistered(for: targetAppURL, version: targetVersion)

        let quickLook = QuickLookCheckResult(
            targetAppURL: targetAppURL,
            embeddedExtension: embeddedExt,
            registeredAppURLs: registeredURLs,
            lastRegisteredAt: preferences.lastRegisteredAt,
            registeredForCurrentTarget: registeredRecently
        )

        return InstallationSnapshot(
            runningAppURL: runningURL,
            runningVersion: runningVersion,
            osVersion: InstallationInspector.currentOSVersionString(),
            architecture: InstallationInspector.currentArchitectureLabel(),
            installStatus: installStatus,
            legacyAppURL: InstallationInspector.detectLegacyApp(),
            quickLook: quickLook,
            loginItemState: currentLoginItemState(),
            dynamicIslandEnabled: dynamicIslandEnabled
        )
    }

    public func currentLoginItemState() -> LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered:
            return .notRegistered
        case .notFound:
            return .notFound
        @unknown default:
            return .notRegistered
        }
    }

    public func setLoginItemEnabled(_ enabled: Bool) throws -> LoginItemState {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
        return currentLoginItemState()
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    public func openExtensionsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Runs `lsregister`, `pluginkit -a`, and `qlmanage -r` / `-r cache` on a background queue.
    public func registerQuickLookExtension(
        for appURL: URL,
        completion: @escaping (RegistrationOutcome) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [preferences] in
            let outcome = Self.performQuickLookRegistration(for: appURL, preferences: preferences)
            DispatchQueue.main.async {
                completion(outcome)
            }
        }
    }

    /// Performs the full install flow (copy into authorized folder + cleanup legacy app + register extension).
    public func installApp(
        into destinationDirectoryURL: URL,
        progress: @escaping (String) -> Void,
        completion: @escaping (Result<(AppBundleCopyOutcome, RegistrationOutcome), Error>) -> Void
    ) {
        let sourceURL = currentRunningAppURL()
        DispatchQueue.global(qos: .userInitiated).async { [preferences] in
            let didStart = destinationDirectoryURL.startAccessingSecurityScopedResource()
            defer {
                if didStart {
                    destinationDirectoryURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                DispatchQueue.main.async { progress("正在将 MakeTools.app 复制到目标文件夹…") }
                let copyOutcome = try AppBundleInstaller.install(
                    sourceAppURL: sourceURL,
                    into: destinationDirectoryURL
                )

                let legacyExtPath = destinationDirectoryURL
                    .appendingPathComponent(InstallationInspector.legacyAppBundleName)
                    .appendingPathComponent("Contents/PlugIns/MarkdownPreviewExtension.appex").path
                if FileManager.default.fileExists(atPath: legacyExtPath) {
                    _ = Self.runCommand("/usr/bin/pluginkit", arguments: ["-r", legacyExtPath])
                }
                _ = AppBundleInstaller.removeLegacyAppIfPresent(in: destinationDirectoryURL)

                DispatchQueue.main.async { progress("正在注册应用与 Quick Look 扩展…") }
                let regOutcome = Self.performQuickLookRegistration(
                    for: copyOutcome.destinationURL,
                    preferences: preferences
                )

                DispatchQueue.main.async {
                    completion(.success((copyOutcome, regOutcome)))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }

    public func relaunchApp(at appURL: URL, completion: @escaping (Error?) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    completion(error)
                } else {
                    completion(nil)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    private static func performQuickLookRegistration(
        for appURL: URL,
        preferences: InstallationPreferences
    ) -> RegistrationOutcome {
        var steps: [String] = []
        var warnings: [String] = []

        let ls = runCommand(InstallationInspector.lsregisterPath, arguments: ["-f", "-R", appURL.path])
        if ls.exitCode == 0 {
            steps.append("已向 LaunchServices 注册应用包")
        } else {
            warnings.append("LaunchServices 注册返回状态 \(ls.exitCode)")
        }

        let extURL = appURL
            .appendingPathComponent("Contents/PlugIns", isDirectory: true)
            .appendingPathComponent(InstallationInspector.quickLookExtensionName, isDirectory: true)
        var pluginAdded = false
        if FileManager.default.fileExists(atPath: extURL.path) {
            let pk = runCommand("/usr/bin/pluginkit", arguments: ["-a", extURL.path])
            if pk.exitCode == 0 {
                pluginAdded = true
                steps.append("已向 PlugInKit 提交 Quick Look 扩展")
            } else {
                let errDetail = pk.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                warnings.append("pluginkit 注册失败\(errDetail.isEmpty ? "" : "：\(errDetail)")")
            }
        } else {
            warnings.append("应用包内未找到 \(InstallationInspector.quickLookExtensionName)")
        }

        let qlReset = runCommand("/usr/bin/qlmanage", arguments: ["-r"])
        let qlCache = runCommand("/usr/bin/qlmanage", arguments: ["-r", "cache"])
        if qlReset.exitCode == 0 && qlCache.exitCode == 0 {
            steps.append("已刷新 Quick Look 服务与预览缓存")
        } else {
            warnings.append("刷新 Quick Look 缓存时出现警告")
        }

        let succeeded = pluginAdded && warnings.isEmpty
        if pluginAdded {
            let version = InstallationInspector.readBundleVersion(at: appURL) ?? AppVersion(shortVersion: "1.1.0")
            preferences.recordQuickLookRegistration(appURL: appURL, version: version)
        }

        return RegistrationOutcome(
            succeeded: succeeded,
            steps: steps,
            warning: warnings.isEmpty ? nil : warnings.joined(separator: "；")
        )
    }

    private struct CommandResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static func runCommand(
        _ executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 10
    ) -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            return CommandResult(exitCode: -1, stdout: "", stderr: "未找到可执行文件：\(executablePath)")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            return CommandResult(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        var stdoutData = Data()
        var stderrData = Data()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            exitSemaphore.signal()
        }

        if exitSemaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = exitSemaphore.wait(timeout: .now() + 1)
            return CommandResult(exitCode: -2, stdout: "", stderr: "命令执行超时")
        }

        readGroup.wait()
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
