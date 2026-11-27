import AppKit
import Foundation

private var totalAssertions = 0
private var failedAssertions = 0

private func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
    totalAssertions += 1
    if !condition {
        failedAssertions += 1
        fputs("FAIL [\(file):\(line)] \(message)\n", stderr)
    }
}

private func makeDummyApp(
    at appURL: URL,
    shortVersion: String,
    buildNumber: String = "1",
    includeQuickLookExtension: Bool = false,
    markerText: String? = nil
) throws {
    let fm = FileManager.default
    let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
    try fm.createDirectory(at: contentsURL, withIntermediateDirectories: true)

    let plist: [String: Any] = [
        "CFBundleIdentifier": InstallationInspector.appBundleIdentifier,
        "CFBundleShortVersionString": shortVersion,
        "CFBundleVersion": buildNumber,
        "CFBundleName": "MakeTools"
    ]
    let plistData = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

    if let markerText {
        try markerText.write(to: contentsURL.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
    }

    if includeQuickLookExtension {
        let extContents = contentsURL
            .appendingPathComponent("PlugIns", isDirectory: true)
            .appendingPathComponent(InstallationInspector.quickLookExtensionName, isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: extContents, withIntermediateDirectories: true)
        let extPlist: [String: Any] = [
            "CFBundleIdentifier": InstallationInspector.quickLookExtensionIdentifier,
            "CFBundleDisplayName": "MakeTools Markdown 预览",
            "CFBundleShortVersionString": shortVersion,
            "CFBundleVersion": buildNumber
        ]
        let extData = try PropertyListSerialization.data(fromPropertyList: extPlist, format: .xml, options: 0)
        try extData.write(to: extContents.appendingPathComponent("Info.plist"))
    }
}

@main
struct InstallationTests {
    static func main() {
        testAppVersionComparison()
        testInstallStatusClassification()
        testOnboardingPreferencesAndLaunchPolicy()
        testProgressSummary()
        testAtomicBundleInstaller()
        testShellCommandBuilder()

        print("InstallationTests: \(totalAssertions - failedAssertions)/\(totalAssertions) assertions passed.")
        if failedAssertions > 0 {
            exit(1)
        }
    }

    private static func testAppVersionComparison() {
        let v101 = AppVersion(shortVersion: "1.0.1", buildNumber: "2")
        let v110 = AppVersion(shortVersion: "1.1.0", buildNumber: "3")
        let v110b4 = AppVersion(shortVersion: "1.1.0", buildNumber: "4")
        let v110b10 = AppVersion(shortVersion: "1.1.0", buildNumber: "10")
        let v1100 = AppVersion(shortVersion: "1.10.0", buildNumber: "1")
        let v11Short = AppVersion(shortVersion: "1.1", buildNumber: nil)
        let v11Zero = AppVersion(shortVersion: "1.1.0", buildNumber: nil)

        check(v101 < v110, "1.0.1 should be older than 1.1.0")
        check(v110 < v1100, "1.1.0 should be older than 1.10.0 numerically")
        check(v110 < v110b4, "Higher build number should compare newer for identical marketing version")
        check(v110b4 < v110b10, "Build 4 should be older than build 10 numerically")
        check(!(v11Short < v11Zero) && !(v11Zero < v11Short), "1.1 and 1.1.0 should compare equal in order")
        check(v110.displayString == "v1.1.0 (3)", "Display string should include build number when present")
        check(v11Zero.displayString == "v1.1.0", "Display string should omit parentheses without build number")
    }

    private static func testInstallStatusClassification() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("MakeTools-InstallClassify-\(UUID().uuidString)", isDirectory: true)
        let sysApps = root.appendingPathComponent("SystemApplications", isDirectory: true)
        let userApps = root.appendingPathComponent("UserApplications", isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        do {
            try fm.createDirectory(at: sysApps, withIntermediateDirectories: true)
            try fm.createDirectory(at: userApps, withIntermediateDirectories: true)
            try fm.createDirectory(at: downloads, withIntermediateDirectories: true)

            let runningDownloads = downloads.appendingPathComponent("MakeTools.app", isDirectory: true)
            try makeDummyApp(at: runningDownloads, shortVersion: "1.1.0", buildNumber: "3", includeQuickLookExtension: true)
            let v110 = AppVersion(shortVersion: "1.1.0", buildNumber: "3")

            // 1. Not installed anywhere
            let notInstalled = InstallationInspector.classifyInstallStatus(
                runningAppURL: runningDownloads,
                runningVersion: v110,
                systemApplicationsURL: sysApps,
                userApplicationsURL: userApps
            )
            check(notInstalled == .notInstalled(runningVersion: v110), "Missing /Applications copy should report notInstalled")
            check(!notInstalled.isRunningFromApplications && !notInstalled.isInstalledInApplications, "notInstalled flags should be false")

            // 2. Translocated copy when not installed
            let translocatedURL = URL(fileURLWithPath: "/private/var/folders/aa/bb/T/AppTranslocation/1234/d/MakeTools.app", isDirectory: true)
            let translocated = InstallationInspector.classifyInstallStatus(
                runningAppURL: translocatedURL,
                runningVersion: v110,
                systemApplicationsURL: sysApps,
                userApplicationsURL: userApps
            )
            check(translocated == .translocated(runningVersion: v110), "AppTranslocation path should report translocated")

            // 3. Older version installed in SystemApplications -> updateAvailable
            let installedApp = sysApps.appendingPathComponent("MakeTools.app", isDirectory: true)
            try makeDummyApp(at: installedApp, shortVersion: "1.0.1", buildNumber: "2")
            let updateAvail = InstallationInspector.classifyInstallStatus(
                runningAppURL: runningDownloads,
                runningVersion: v110,
                systemApplicationsURL: sysApps,
                userApplicationsURL: userApps
            )
            check(updateAvail == .updateAvailable(
                installedURL: installedApp,
                installedVersion: AppVersion(shortVersion: "1.0.1", buildNumber: "2"),
                runningVersion: v110
            ), "Older installed version should report updateAvailable")
            check(updateAvail.isInstalledInApplications && !updateAvail.isInstalledAndUpToDate, "updateAvailable should not count as up to date")

            // 4. Same version installed in SystemApplications, running from Downloads -> installedSameOrNewer
            try fm.removeItem(at: installedApp)
            try makeDummyApp(at: installedApp, shortVersion: "1.1.0", buildNumber: "3", includeQuickLookExtension: true)
            let installedSame = InstallationInspector.classifyInstallStatus(
                runningAppURL: runningDownloads,
                runningVersion: v110,
                systemApplicationsURL: sysApps,
                userApplicationsURL: userApps
            )
            check(installedSame == .installedSameOrNewer(
                installedURL: installedApp,
                installedVersion: v110,
                runningVersion: v110
            ), "Same version in Applications while running outside should report installedSameOrNewer")

            // 5. Running directly from SystemApplications -> runningFromApplications
            let runningSys = InstallationInspector.classifyInstallStatus(
                runningAppURL: installedApp,
                runningVersion: v110,
                systemApplicationsURL: sysApps,
                userApplicationsURL: userApps
            )
            check(runningSys.isRunningFromApplications && runningSys.isInstalledAndUpToDate, "Running from SystemApplications should report runningFromApplications")

            // 6. Running directly from UserApplications -> runningFromApplications
            let userInstalled = userApps.appendingPathComponent("MakeTools.app", isDirectory: true)
            try makeDummyApp(at: userInstalled, shortVersion: "1.1.0", buildNumber: "3")
            let runningUser = InstallationInspector.classifyInstallStatus(
                runningAppURL: userInstalled,
                runningVersion: v110,
                systemApplicationsURL: sysApps,
                userApplicationsURL: userApps
            )
            check(runningUser.isRunningFromApplications, "Running from ~/Applications should also count as installed")

            // 7. Embedded Quick Look extension metadata and legacy app detection
            let extInfo = InstallationInspector.readEmbeddedQuickLookExtension(in: installedApp)
            check(extInfo?.bundleIdentifier == InstallationInspector.quickLookExtensionIdentifier
                  && extInfo?.version == v110
                  && extInfo?.displayName == "MakeTools Markdown 预览",
                  "Should read embedded MarkdownQuickLook.appex metadata")

            check(InstallationInspector.detectLegacyApp(in: sysApps) == nil, "Legacy app should be nil before creation")
            let legacyURL = sysApps.appendingPathComponent(InstallationInspector.legacyAppBundleName, isDirectory: true)
            try fm.createDirectory(at: legacyURL, withIntermediateDirectories: true)
            check(InstallationInspector.detectLegacyApp(in: sysApps) == legacyURL, "Should detect legacy MarkdownQuickLook.app")
        } catch {
            check(false, "Classification fixture setup failed: \(error)")
        }
    }

    private static func testOnboardingPreferencesAndLaunchPolicy() {
        let suite = "MakeTools.InstallationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let prefs = InstallationPreferences(defaults: defaults)
        let v110 = AppVersion(shortVersion: "1.1.0", buildNumber: "3")
        let v120 = AppVersion(shortVersion: "1.2.0", buildNumber: "4")
        let appURL = URL(fileURLWithPath: "/Applications/MakeTools.app", isDirectory: true)

        check(prefs.shouldOpenOnLaunch(installStatus: .notInstalled(runningVersion: v110), runningVersion: v110),
              "First launch outside Applications should open the installation page")
        check(prefs.shouldOpenOnLaunch(installStatus: .translocated(runningVersion: v110), runningVersion: v110),
              "Translocated launch should open the installation page")
        check(!prefs.shouldOpenOnLaunch(installStatus: .runningFromApplications(appURL: appURL, version: v110), runningVersion: v110),
              "Already running from Applications should skip auto-opening onboarding")

        prefs.markOnboardingCompleted(for: v110)
        check(!prefs.shouldOpenOnLaunch(installStatus: .notInstalled(runningVersion: v110), runningVersion: v110),
              "Dismissed onboarding should not reopen for the same version")
        check(prefs.shouldOpenOnLaunch(installStatus: .notInstalled(runningVersion: v120), runningVersion: v120),
              "A newer version running outside Applications should offer installation again")

        check(!prefs.isQuickLookRegistered(for: appURL, version: v110), "Fresh profile should not claim Quick Look registered")
        let timestamp = Date(timeIntervalSince1970: 1_760_000_000)
        prefs.recordQuickLookRegistration(appURL: appURL, version: v110, at: timestamp)
        check(prefs.isQuickLookRegistered(for: appURL, version: v110), "Recorded Quick Look registration should match same app and version")
        check(!prefs.isQuickLookRegistered(for: appURL, version: v120), "Recorded Quick Look registration should invalidate on version change")
        check(prefs.lastRegisteredAt == timestamp, "Registration timestamp should persist")
    }

    private static func testProgressSummary() {
        let v110 = AppVersion(shortVersion: "1.1.0", buildNumber: "3")
        let appURL = URL(fileURLWithPath: "/Applications/MakeTools.app", isDirectory: true)
        let ext = QuickLookExtensionInfo(
            bundleIdentifier: InstallationInspector.quickLookExtensionIdentifier,
            displayName: "MakeTools Markdown 预览",
            version: v110,
            extensionURL: appURL.appendingPathComponent("Contents/PlugIns/MarkdownQuickLook.appex")
        )

        let fresh = InstallationSnapshot(
            runningAppURL: URL(fileURLWithPath: "/tmp/MakeTools.app"),
            runningVersion: v110,
            osVersion: "macOS 15.0.0",
            architecture: "arm64",
            installStatus: .notInstalled(runningVersion: v110),
            legacyAppURL: nil,
            quickLook: QuickLookCheckResult(
                targetAppURL: URL(fileURLWithPath: "/tmp/MakeTools.app"),
                embeddedExtension: ext,
                registeredAppURLs: [],
                lastRegisteredAt: nil,
                registeredForCurrentTarget: false
            ),
            loginItemState: .notRegistered,
            dynamicIslandEnabled: false
        )
        check(fresh.progress.completedSteps == 0 && fresh.progress.totalSteps == 3 && !fresh.progress.isCoreReady,
              "Fresh uninstalled snapshot should report 0/3 and not core ready")

        let ready = InstallationSnapshot(
            runningAppURL: appURL,
            runningVersion: v110,
            osVersion: "macOS 15.0.0",
            architecture: "arm64",
            installStatus: .runningFromApplications(appURL: appURL, version: v110),
            legacyAppURL: nil,
            quickLook: QuickLookCheckResult(
                targetAppURL: appURL,
                embeddedExtension: ext,
                registeredAppURLs: [appURL],
                lastRegisteredAt: Date(),
                registeredForCurrentTarget: true
            ),
            loginItemState: .enabled,
            dynamicIslandEnabled: true
        )
        check(ready.progress.completedSteps == 3 && ready.progress.totalSteps == 3 && ready.progress.isCoreReady,
              "Fully configured snapshot should report 3/3 and core ready")
    }

    private static func testAtomicBundleInstaller() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("MakeTools-BundleInstaller-\(UUID().uuidString)", isDirectory: true)
        let srcDir = root.appendingPathComponent("Source", isDirectory: true)
        let dstDir = root.appendingPathComponent("Dest", isDirectory: true)
        defer { try? fm.removeItem(at: root) }

        do {
            try fm.createDirectory(at: srcDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: dstDir, withIntermediateDirectories: true)

            let srcV1 = srcDir.appendingPathComponent("MakeTools.app", isDirectory: true)
            try makeDummyApp(at: srcV1, shortVersion: "1.0.1", buildNumber: "2", markerText: "v1")

            // 1. Fresh install
            let freshOutcome = try AppBundleInstaller.install(sourceAppURL: srcV1, into: dstDir)
            let expectedDest = dstDir.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent("MakeTools.app", isDirectory: true)
            check(freshOutcome == .installedFresh(destinationURL: expectedDest), "First install should report installedFresh")
            check(InstallationInspector.readBundleVersion(at: expectedDest) == AppVersion(shortVersion: "1.0.1", buildNumber: "2"),
                  "Installed bundle should contain expected version")

            // 2. Replace existing with newer version
            try fm.removeItem(at: srcV1)
            try makeDummyApp(at: srcV1, shortVersion: "1.1.0", buildNumber: "3", markerText: "v2")
            let oldStray = expectedDest.appendingPathComponent("Contents/old-file.txt")
            try "stale".write(to: oldStray, atomically: true, encoding: .utf8)

            let replaceOutcome = try AppBundleInstaller.install(sourceAppURL: srcV1, into: dstDir)
            check(replaceOutcome == .replacedExisting(destinationURL: expectedDest), "Second install should report replacedExisting")
            check(InstallationInspector.readBundleVersion(at: expectedDest) == AppVersion(shortVersion: "1.1.0", buildNumber: "3"),
                  "Replaced bundle should have updated version")
            check(!fm.fileExists(atPath: oldStray.path), "Atomic replacement should not keep stale files from the old bundle")

            let leftoverStaging = (try fm.contentsOfDirectory(atPath: dstDir.path)).filter { $0.contains(".staging-") }
            check(leftoverStaging.isEmpty, "No staging bundles should remain after install")

            // 3. Already in place
            let inPlace = try AppBundleInstaller.install(sourceAppURL: expectedDest, into: dstDir)
            check(inPlace == .alreadyInPlace(destinationURL: expectedDest), "Installing onto itself should report alreadyInPlace")

            // 4. Reject destination inside source bundle
            let nestedDir = srcV1.appendingPathComponent("Contents", isDirectory: true)
            do {
                _ = try AppBundleInstaller.install(sourceAppURL: srcV1, into: nestedDir)
                check(false, "Installing a bundle inside itself should throw")
            } catch let err as AppBundleInstallError {
                check(err == .destinationInsideSource, "Nested install should throw destinationInsideSource")
            }

            // 5. Reject non-.app source
            let nonApp = root.appendingPathComponent("NotAnApp", isDirectory: true)
            try fm.createDirectory(at: nonApp, withIntermediateDirectories: true)
            do {
                _ = try AppBundleInstaller.install(sourceAppURL: nonApp, into: dstDir)
                check(false, "Non-.app source should throw")
            } catch let err as AppBundleInstallError {
                if case .sourceBundleInvalid = err {
                    check(true, "Non-.app source throws sourceBundleInvalid")
                } else {
                    check(false, "Unexpected error for non-.app source: \(err)")
                }
            }

            // 6. Legacy cleanup
            let legacy = dstDir.appendingPathComponent(InstallationInspector.legacyAppBundleName, isDirectory: true)
            try fm.createDirectory(at: legacy, withIntermediateDirectories: true)
            check(AppBundleInstaller.removeLegacyAppIfPresent(in: dstDir), "Should remove existing legacy app")
            check(!fm.fileExists(atPath: legacy.path), "Legacy app directory should be deleted")
            check(!AppBundleInstaller.removeLegacyAppIfPresent(in: dstDir), "Removing absent legacy app should return false")
        } catch {
            check(false, "Bundle installer test failed unexpectedly: \(error)")
        }
    }

    private static func testShellCommandBuilder() {
        check(InstallationCommandBuilder.shellQuote("/Applications/MakeTools.app") == "'/Applications/MakeTools.app'",
              "Standard path should be single-quoted")
        check(InstallationCommandBuilder.shellQuote("/Users/o'neil/My Apps/MakeTools.app")
              == "'/Users/o'\\''neil/My Apps/MakeTools.app'",
              "Paths with spaces and apostrophes should be shell-escaped safely")

        let src = URL(fileURLWithPath: "/Users/test/My Downloads/MakeTools.app")
        let cmd = InstallationCommandBuilder.terminalInstallCommand(sourceAppURL: src)
        check(cmd.contains("cp -R '/Users/test/My Downloads/MakeTools.app' '/Applications/MakeTools.app'"),
              "Terminal install command should copy the quoted source app")
        check(cmd.contains("xattr -dr com.apple.quarantine '/Applications/MakeTools.app'"),
              "Terminal install command should strip quarantine attributes")
        check(cmd.contains("pluginkit -a '/Applications/MakeTools.app/Contents/PlugIns/MarkdownQuickLook.appex'"),
              "Terminal install command should register the Quick Look extension")
        check(cmd.contains("pluginkit -e use -i com.make.MakeTools.MarkdownQuickLook"),
              "Terminal install command should enable the Quick Look extension")
        check(cmd.contains("qlmanage -r && qlmanage -r cache"),
              "Terminal install command should reset Quick Look and cache")

        check(InstallationCommandBuilder.quickLookVerifyCommand.contains("pluginkit -m -v -p com.apple.quicklook.preview"),
              "Verify command should query Quick Look preview extensions")
        check(InstallationCommandBuilder.quarantineClearCommand(appURL: src)
              == "xattr -dr com.apple.quarantine '/Users/test/My Downloads/MakeTools.app'",
              "Quarantine clear command should properly quote target path")
    }
}
