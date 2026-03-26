import Foundation
import Combine

@MainActor
class UsageService: ObservableObject {
    static let shared = UsageService()

    @Published var currentUsage: UsageSnapshot? = nil
    @Published var error: String? = nil
    @Published var isLoading: Bool = false

    private var cachedToken: String? = nil
    private var pollTimer: Timer? = nil
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Public API

    func startPolling() {
        SettingsManager.shared.$settings
            .map(\.pollInterval)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                let interval = SettingsManager.shared.settings.pollInterval
                self.schedulePoll(interval: interval)
            }
            .store(in: &cancellables)

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

            if let httpResponse = response as? HTTPURLResponse {
                let statusCode = httpResponse.statusCode
                if statusCode == 429 {
                    // Rate limited — clear cached token and back off
                    cachedToken = nil
                    schedulePoll(interval: max(900, SettingsManager.shared.settings.pollInterval * 2))
                    error = "Rate limited (429). Retrying in 15 minutes."
                    return
                } else if statusCode == 401 || statusCode == 403 {
                    cachedToken = nil
                    schedulePoll(interval: max(900, SettingsManager.shared.settings.pollInterval * 2))
                    error = "Authentication failed. Please re-sign in to Claude Code."
                    return
                } else if statusCode < 200 || statusCode >= 300 {
                    schedulePoll(interval: SettingsManager.shared.settings.pollInterval)
                    error = "API error (\(statusCode)). Retrying..."
                    return
                }
            }

            let decoded = try JSONDecoder().decode(OAuthUsageResponse.self, from: data)
            let snapshot = UsageSnapshot.from(response: decoded)
            currentUsage = snapshot
            error = nil
            UsageHistoryStore.shared.append(snapshot: snapshot)
            schedulePoll(interval: SettingsManager.shared.settings.pollInterval)

        } catch KeychainError.itemNotFound {
            error = "Claude Code credentials not found in Keychain. Please sign in to Claude Code."
            schedulePoll(interval: max(900, SettingsManager.shared.settings.pollInterval * 2))
        } catch is DecodingError {
            self.error = "Failed to parse usage data. The API response format may have changed."
            schedulePoll(interval: SettingsManager.shared.settings.pollInterval)
        } catch {
            self.error = error.localizedDescription
            schedulePoll(interval: SettingsManager.shared.settings.pollInterval)
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
