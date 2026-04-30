import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case unexpectedData
    case systemError(OSStatus)
}

struct KeychainTokenReader {
    static func readAccessToken() throws -> String {
        if let cached = try? readCachedToken(), !isExpiredOrNearExpiry(cached.expiresAt) {
            return cached.accessToken
        }

        let rawData = try readRawDataFromClaudeCode()

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let credentials = try decoder.decode(KeychainCredentials.self, from: rawData)

        writeCachedData(rawData)

        return credentials.claudeAiOauth.accessToken
    }
}

// MARK: - Private Helpers

private extension KeychainTokenReader {
    static let cacheService = "com.chinoyoung.ClaudeUsageBar.cached-credentials"
    static let cacheAccount = "oauth"
    static let expiryMarginSeconds: Double = 60

    static func isExpiredOrNearExpiry(_ expiresAt: Double) -> Bool {
        expiresAt - expiryMarginSeconds <= Date().timeIntervalSince1970
    }

    static func readCachedToken() throws -> OAuthData {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: cacheService,
            kSecAttrAccount: cacheAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.systemError(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let credentials = try decoder.decode(KeychainCredentials.self, from: data)
        return credentials.claudeAiOauth
    }

    static func readRawDataFromClaudeCode() throws -> Data {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.systemError(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return data
    }

    static func writeCachedData(_ data: Data) {
        let attributes: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: cacheService,
            kSecAttrAccount: cacheAccount,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData: data
        ]

        var status = SecItemAdd(attributes as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let query: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: cacheService,
                kSecAttrAccount: cacheAccount
            ]
            let update: [CFString: Any] = [kSecValueData: data]
            status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        }

        if status != errSecSuccess {
            NSLog("ClaudeUsageBar: cache write failed with status %d", status)
        }
    }
}

// MARK: - Private Codable Models

private struct KeychainCredentials: Codable {
    let claudeAiOauth: OAuthData
}

private struct OAuthData: Codable {
    let accessToken: String
    let expiresAt: Double
}
