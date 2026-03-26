import Foundation
import Security

enum KeychainError: Error {
    case itemNotFound
    case unexpectedData
    case systemError(OSStatus)
}

struct KeychainTokenReader {
    static func readAccessToken() throws -> String {
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

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let credentials = try decoder.decode(KeychainCredentials.self, from: data)
        return credentials.claudeAiOauth.accessToken
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
