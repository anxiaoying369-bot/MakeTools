import Foundation

@main
enum LocalizationTests {
    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: root) }
        let bundleURL = root.appendingPathComponent("TestLanguages.bundle")
        let resources = bundleURL.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "CFBundleIdentifier": "com.make.MakeTools.LocalizationTests",
            "CFBundlePackageType": "BNDL"
        ], format: .xml, options: 0)
        try plist.write(to: bundleURL.appendingPathComponent("Contents/Info.plist"))
        try fileManager.copyItem(
            at: URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true),
            to: resources.appendingPathComponent("Languages", isDirectory: true)
        )

        let suite = "MakeTools.LocalizationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let bundle = Bundle(url: bundleURL)!
        let directory = root.appendingPathComponent("Installed", isDirectory: true)
        let localization = Localization(bundle: bundle, defaults: defaults, directory: directory)
        precondition(localization.choices.count == 2)
        localization.setSelection("builtin:en")
        precondition(localization.text("lanTransfer.receive.title", fallback: "missing") == "Receive Files")
        precondition(localization.text("calendar.daysRemaining", fallback: "missing", arguments: ["count": "1"]) == "There is 1 day left")
        precondition(localization.text("calendar.daysRemaining", fallback: "missing", arguments: ["count": "2"]) == "There are 2 days left")

        let pack = LanguagePack(formatVersion: 1, locale: "fr-FR", displayName: "Français", messages: [
            "lanTransfer.receive.title": "Recevoir des fichiers",
            "lanTransfer.status.saved": "Fichier reçu : {filename}",
            "bookmarks.bookmarks": "{count} favoris"
        ], plurals: ["bookmarks.bookmarks": ["one": "{count} favori", "other": "{count} favoris"]])
        try localization.install(JSONEncoder().encode(pack))
        localization.setSelection("user:fr-fr")
        precondition(localization.text("lanTransfer.receive.title", fallback: "missing") == "Recevoir des fichiers")
        precondition(localization.text("calendar.daysSince", fallback: "missing", arguments: ["count": "1"]) == "1 day ago")
        precondition(localization.text("bookmarks.bookmarks", fallback: "missing", arguments: ["count": "1"]) == "1 favori")
        precondition(localization.text("lanTransfer.status.saved", fallback: "missing",
                                       arguments: ["filename": "{filename}.pdf"]) == "Fichier reçu : {filename}.pdf")

        let invalid = LanguagePack(formatVersion: 1, locale: "fr-FR", displayName: "Broken",
                                   messages: ["lanTransfer.status.saved": "Missing the filename parameter"])
        do {
            try localization.install(JSONEncoder().encode(invalid))
            preconditionFailure("Invalid parameters must prevent installation")
        } catch is LanguagePackError {}
        let reopened = Localization(bundle: bundle, defaults: defaults, directory: directory)
        precondition(reopened.locale == "fr-FR")
        precondition(reopened.text("lanTransfer.receive.title", fallback: "missing") == "Recevoir des fichiers")

        let customChinese = LanguagePack(formatVersion: 1, locale: "zh-Hans", displayName: "我的语言包", messages: [:])
        try reopened.install(JSONEncoder().encode(customChinese))
        reopened.setSelection("user:zh-hans")
        precondition(reopened.text("lanTransfer.receive.title", fallback: "missing") == "接收文件")

        let template = try localization.validate(localization.template())
        precondition(template.messages["lanTransfer.status.saved"]?.contains("{filename}") == true)
        precondition(template.plurals?["calendar.daysRemaining"]?["other"] != nil)
        precondition(!L10n.scriptString("</script><a>").contains("<"))
        precondition(L10n.html("<a>") == "&lt;a&gt;")
        print("LocalizationTests: overrides, fallbacks, plurals, persistence, validation, and escaping passed.")
    }
}
