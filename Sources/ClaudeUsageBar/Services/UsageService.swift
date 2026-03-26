import Foundation

@MainActor
class UsageService: ObservableObject {
    static let shared = UsageService()

    @Published var currentUsage: UsageSnapshot? = nil
    @Published var error: String? = nil
    @Published var isLoading: Bool = false

    private var cachedToken: String? = nil
    private var pollTimer: Timer? = nil

    private let normalInterval: TimeInterval = 300   // 5 minutes
    private let backoffInterval: TimeInterval = 900  // 15 minutes

    private init() {}

    // MARK: - Public API

    func startPolling() {
        Task { @MainActor in
            await fetchUsage()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Fetch

    func fetchUsage() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let token = try resolveToken()
            let request = buildRequest(token: token)

            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 429 {
                // Rate limited — clear cached token and back off
                cachedToken = nil
                schedulePoll(interval: backoffInterval)
                error = "Rate limited (429). Retrying in 15 minutes."
                return
            }

            let decoded = try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
            currentUsage = UsageSnapshot.from(response: decoded)
            error = nil
            schedulePoll(interval: normalInterval)

        } catch KeychainError.itemNotFound {
            error = "Claude Code credentials not found in Keychain. Please sign in to Claude Code."
            schedulePoll(interval: backoffInterval)
        } catch {
            self.error = error.localizedDescription
            schedulePoll(interval: normalInterval)
        }
    }

    // MARK: - Helpers

    private func resolveToken() throws -> String {
        if let cached = cachedToken {
            return cached
        }
        let token = try KeychainTokenReader.readAccessToken()
        cachedToken = token
        return token
    }

    private func buildRequest(token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        return request
    }

    private func schedulePoll(interval: TimeInterval) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.fetchUsage()
            }
        }
        RunLoop.main.add(pollTimer!, forMode: .common)
    }
}
