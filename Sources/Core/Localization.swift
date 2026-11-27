import Foundation
import JavaScriptCore

struct LanguagePack: Codable, Equatable {
    let formatVersion: Int
    let locale: String
    let displayName: String
    let messages: [String: String]
    var plurals: [String: [String: String]]? = nil
}

struct LanguagePackError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

final class Localization {
    static let shared = Localization()
    static let didChange = Notification.Name("MakeTools.LanguageDidChange")
    static let systemID = "system"
    static let maximumPackSize = 2 * 1024 * 1024

    struct Choice {
        let id: String
        let name: String
        let pack: LanguagePack
    }

    private struct Snapshot: Equatable {
        let locale: String
        let messages: [String: String]
        let plurals: [String: Plural]
    }

    private struct Plural: Equatable {
        let locale: String
        let forms: [String: String]
    }

    private let defaults: UserDefaults
    private let directory: URL?
    private let builtins: [LanguagePack]
    private let selectionKey = "MakeTools.language"
    private let lock = NSLock()
    private var snapshot = Snapshot(locale: "zh-Hans", messages: [:], plurals: [:])

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard, directory: URL? = nil) {
        self.defaults = defaults
        // The Finder extension owns its UI and loads only the built-in translations.
        let isExtension = bundle.bundleURL.pathExtension == "appex"
        if isExtension {
            self.directory = nil
        } else if let directory {
            self.directory = directory
        } else if bundle.bundleURL.pathExtension == "app" {
            self.directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("MakeTools/Languages", isDirectory: true)
        } else {
            self.directory = nil
        }
        builtins = ["zh-Hans", "en"].compactMap { code in
            guard let url = bundle.url(forResource: code, withExtension: "json", subdirectory: "Languages") else { return nil }
            return try? Self.decode(Self.read(url))
        }
        reload(followSystem: isExtension)
    }

    var selection: String { defaults.string(forKey: selectionKey) ?? Self.systemID }
    var locale: String { lock.withLock { snapshot.locale } }

    var choices: [Choice] {
        let packaged = builtins.map { Choice(id: "builtin:" + $0.locale.lowercased(), name: $0.displayName, pack: $0) }
        guard let directory, let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return packaged }
        let imported = files.compactMap { url -> Choice? in
            guard url.pathExtension == "json", let data = try? Self.read(url), let pack = try? validate(data),
                  url.deletingPathExtension().lastPathComponent == pack.locale.lowercased() else { return nil }
            return Choice(id: "user:" + pack.locale.lowercased(), name: "\(pack.displayName) (\(pack.locale))", pack: pack)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return packaged + imported
    }

    func setSelection(_ id: String) {
        guard id == Self.systemID || choices.contains(where: { $0.id == id }) else { return }
        guard selection != id else { return }
        defaults.set(id, forKey: selectionKey)
        reload()
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    func install(_ data: Data) throws {
        let pack = try validate(data)
        guard let directory else { throw LanguagePackError("Language pack storage is unavailable.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(pack.locale.lowercased() + ".json"), options: .atomic)
        let previous = lock.withLock { snapshot }
        reload()
        if lock.withLock({ snapshot != previous }) {
            NotificationCenter.default.post(name: Self.didChange, object: nil)
        }
    }

    func template() throws -> Data {
        let template = builtins.first { $0.locale == "en" }
            ?? LanguagePack(formatVersion: 1, locale: "en", displayName: "English", messages: [:])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(template)
    }

    func text(_ key: String, fallback: String, arguments: [String: String] = [:]) -> String {
        let entry = lock.withLock { (snapshot.messages[key] ?? fallback, snapshot.plurals[key]) }
        let value: String
        if let plural = entry.1, let count = arguments["count"].flatMap(Int.init) {
            let category = Self.pluralCategory(locale: plural.locale, count: count)
            value = plural.forms[category] ?? plural.forms["other"] ?? entry.0
        } else {
            value = entry.0
        }
        guard !arguments.isEmpty else { return value }
        var result = ""
        var cursor = value.startIndex
        for match in Self.placeholders.matches(in: value, range: NSRange(value.startIndex..., in: value)) {
            guard let name = Range(match.range(at: 1), in: value), let replacement = arguments[String(value[name])],
                  let range = Range(match.range, in: value) else { continue }
            result += value[cursor..<range.lowerBound]
            result += replacement
            cursor = range.upperBound
        }
        result += value[cursor...]
        return result
    }

    func validate(_ data: Data) throws -> LanguagePack {
        let pack = try Self.decode(data)
        let reference = builtins.first { $0.locale == "zh-Hans" }?.messages ?? [:]
        var translations = pack.messages.map { ($0.key, $0.value) }
        for (key, forms) in pack.plurals ?? [:] {
            translations.append(contentsOf: forms.values.map { (key, $0) })
        }
        for (key, value) in translations {
            guard let original = reference[key], Self.parameters(in: value) != Self.parameters(in: original) else { continue }
            throw LanguagePackError(text("language.error.placeholders",
                fallback: "翻译标识 {key} 的占位符与模板不一致。", arguments: ["key": key]))
        }
        return pack
    }

    static func read(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: maximumPackSize + 1) ?? Data()
    }

    private static let placeholders = try! NSRegularExpression(pattern: #"\{([A-Za-z][A-Za-z0-9_]*)\}"#)

    private static func parameters(in text: String) -> Set<String> {
        Set(placeholders.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            Range(match.range(at: 1), in: text).map { String(text[$0]) }
        })
    }

    private static func decode(_ data: Data) throws -> LanguagePack {
        guard data.count <= maximumPackSize, String(data: data, encoding: .utf8) != nil,
              let pack = try? JSONDecoder().decode(LanguagePack.self, from: data), pack.formatVersion == 1,
              pack.locale.utf8.count <= 64,
              pack.locale.range(of: #"^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$"#, options: .regularExpression) != nil,
              !pack.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pack.displayName.count <= 80, pack.messages.count <= 5000,
              pack.messages.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 120 && !$0.value.isEmpty && $0.value.count <= 16_000 }),
              (pack.plurals ?? [:]).allSatisfy({ key, forms in
                  pack.messages[key].map { parameters(in: $0).contains("count") } == true &&
                      forms["other"] != nil && forms.allSatisfy {
                          ["zero", "one", "two", "few", "many", "other"].contains($0.key) &&
                              !$0.value.isEmpty && $0.value.count <= 16_000
                      }
              })
        else {
            // Decoding happens while the localization singleton is being initialized.
            throw LanguagePackError("Invalid language pack. Check its JSON, format version, locale and size.")
        }
        return pack
    }

    private func reload(followSystem: Bool = false) {
        let choices = choices
        let selected = followSystem ? nil : choices.first { $0.id == selection }?.pack
        let preferred = Locale.preferredLanguages.map { $0.replacingOccurrences(of: "_", with: "-").lowercased() }
        let best = preferred.lazy.compactMap { locale in
            let exact = choices.first { $0.pack.locale.lowercased() == locale }
            let family = choices.first { Self.languageFamily($0.pack.locale) == Self.languageFamily(locale) }
            return (exact ?? family)?.pack
        }.first
        let language = selected ?? best ?? builtins.first { $0.locale == "en" } ?? builtins.first
        var messages: [String: String] = [:]
        var plurals: [String: Plural] = [:]
        func merge(_ pack: LanguagePack) {
            for (key, value) in pack.messages {
                messages[key] = value
                plurals[key] = pack.plurals?[key].map { Plural(locale: pack.locale, forms: $0) }
            }
        }
        for code in ["zh-Hans", "en"] {
            if let pack = builtins.first(where: { $0.locale == code }) { merge(pack) }
        }
        if let language {
            for pack in builtins where Self.languageFamily(pack.locale) == Self.languageFamily(language.locale) {
                merge(pack)
            }
            merge(language)
        }
        lock.withLock { snapshot = Snapshot(locale: language?.locale ?? "zh-Hans", messages: messages, plurals: plurals) }
    }

    // Intl provides locale-specific plural rules. Only this fixed function is evaluated as code.
    private static let pluralLock = NSLock()
    private static let pluralRules = JSContext()?.evaluateScript("""
        (function(locale, count) {
            try { return new Intl.PluralRules(locale).select(count); }
            catch (_) { return 'other'; }
        })
        """)

    private static func pluralCategory(locale: String, count: Int) -> String {
        pluralLock.withLock {
            pluralRules?.call(withArguments: [locale, count])?.toString() ?? "other"
        }
    }

    private static func languageFamily(_ locale: String) -> String {
        locale.split(separator: "-").first.map { $0.lowercased() } ?? ""
    }
}

enum L10n {
    static var locale: Locale { Locale(identifier: Localization.shared.locale) }

    static func text(_ key: String, _ fallback: String, _ arguments: [String: String] = [:]) -> String {
        Localization.shared.text(key, fallback: fallback, arguments: arguments)
    }

    static func html(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    static func scriptString(_ value: String) -> String {
        let encoded = (try? JSONEncoder().encode(value)).map { String(decoding: $0, as: UTF8.self) } ?? "\"\""
        return encoded.replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
