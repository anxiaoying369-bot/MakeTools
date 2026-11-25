import Foundation
import Security

struct PasswordBookEntry {
    let id: UUID
    let website: String
    let account: String
}

struct PasswordBookStore {
    private let service: String

    init(service: String = "com.make.MakeTools.PasswordBook") {
        self.service = service
    }

    func entries() throws -> [PasswordBookEntry] {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status)
        guard let items = result as? [[String: Any]] else { throw StoreError.invalidItem }
        var entries = try items.map { item in
            guard let identifier = item[kSecAttrAccount as String] as? String,
                  let id = UUID(uuidString: identifier),
                  let website = item[kSecAttrLabel as String] as? String,
                  let account = item[kSecAttrComment as String] as? String else {
                throw StoreError.invalidItem
            }
            return PasswordBookEntry(id: id, website: website, account: account)
        }
        Self.sort(&entries)
        return entries
    }

    static func sort(_ entries: inout [PasswordBookEntry]) {
        entries.sort { first, second in
            let websiteOrder = first.website.localizedStandardCompare(second.website)
            if websiteOrder != .orderedSame { return websiteOrder == .orderedAscending }
            return first.account.localizedStandardCompare(second.account) == .orderedAscending
        }
    }

    func save(_ entry: PasswordBookEntry, password: String?, isNew: Bool) throws {
        var attributes: [String: Any] = [
            kSecAttrLabel as String: entry.website,
            kSecAttrComment as String: entry.account
        ]
        if let password {
            attributes[kSecValueData as String] = Data(password.utf8)
        }
        let query = itemQuery(for: entry.id)
        if isNew {
            guard password != nil else { throw StoreError.invalidItem }
            try check(SecItemAdd(query.merging(attributes) { _, value in value } as CFDictionary, nil))
        } else {
            try check(SecItemUpdate(query as CFDictionary, attributes as CFDictionary))
        }
    }

    func password(for id: UUID) throws -> String {
        var query = itemQuery(for: id)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        try check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { throw StoreError.invalidItem }
        return password
    }

    // The app's ad-hoc build uses the standard macOS keychain without an access group.
    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    private func itemQuery(for id: UUID) -> [String: Any] {
        var query = baseQuery
        query[kSecAttrAccount as String] = id.uuidString
        return query
    }

    private func check(_ status: OSStatus) throws {
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
    }

    private enum StoreError: LocalizedError {
        case invalidItem
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidItem:
                return "无法读取或保存这条密码记录。"
            case .keychain(errSecItemNotFound):
                return "这条记录已不在钥匙串中。"
            case .keychain(let status):
                return "无法访问钥匙串（\(status)）。"
            }
        }
    }
}
