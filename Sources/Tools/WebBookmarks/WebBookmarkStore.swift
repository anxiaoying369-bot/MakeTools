import Foundation

struct WebBookmark: Codable, Equatable {
    let title: String
    let url: URL

    init?(title: String, address: String) {
        let address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !address.isEmpty else { return nil }
        let hasScheme = address.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
        let candidate = hasScheme ? address : "https://" + address
        guard let url = URL(string: candidate), Self.isWebAddress(url),
              let host = url.host() else { return nil }

        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = name.isEmpty ? host : name
        self.url = url
    }

    static func isWebAddress(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty, host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              url.user() == nil, url.password() == nil else { return false }
        return true
    }
}

struct WebBookmarkStore {
    var defaults: UserDefaults = .standard
    private static let key = "MakeTools.DynamicIsland.webBookmarks"

    func load() throws -> [WebBookmark] {
        guard let data = defaults.data(forKey: Self.key) else { return [] }
        return try JSONDecoder().decode([WebBookmark].self, from: data)
    }

    func add(_ bookmark: WebBookmark) throws -> [WebBookmark] {
        let existing = try load()
        return try save([bookmark] + existing.filter { $0.url != bookmark.url })
    }

    func remove(url: URL) throws -> [WebBookmark] {
        try save(load().filter { $0.url != url })
    }

    private func save(_ bookmarks: [WebBookmark]) throws -> [WebBookmark] {
        defaults.set(try JSONEncoder().encode(bookmarks), forKey: Self.key)
        return bookmarks
    }
}
