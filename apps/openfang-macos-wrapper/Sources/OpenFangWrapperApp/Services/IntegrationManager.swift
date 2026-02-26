import Foundation

struct IntegrationTestResult {
    let statusCode: Int?
    let responseSnippet: String
}

struct IntegrationManager {
    static func testWebhook(target: IntegrationTarget) async throws -> IntegrationTestResult {
        guard let url = URL(string: target.url), !target.url.isEmpty else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8

        target.headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        if let key = target.secretKeychainKey,
           let secret = KeychainHelper.read(account: key) {
            request.setValue(secret, forHTTPHeaderField: "X-Webhook-Secret")
        }

        switch target.payloadFormat {
        case .json:
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "source": "openfang-wrapper",
                "title": "OpenFang Wrapper test",
                "timestamp": ISO8601DateFormatter().string(from: Date()),
            ])
        case .plainText:
            request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("OpenFang Wrapper test".utf8)
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        return IntegrationTestResult(
            statusCode: http?.statusCode,
            responseSnippet: String(decoding: data.prefix(512), as: UTF8.self)
        )
    }

    static func checkReachability(urlString: String) async -> IntegrationTestResult {
        guard let url = URL(string: urlString), !urlString.isEmpty else {
            return IntegrationTestResult(statusCode: nil, responseSnippet: "No URL configured")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 4

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            return IntegrationTestResult(
                statusCode: http?.statusCode,
                responseSnippet: String(decoding: data.prefix(512), as: UTF8.self)
            )
        } catch {
            return IntegrationTestResult(statusCode: nil, responseSnippet: "Unreachable: \(error.localizedDescription)")
        }
    }

    static func testE2E(
        openClawURL: String,
        secretHeaderName: String,
        secretKeychainAccount: String?
    ) async -> IntegrationTestResult {
        guard let url = URL(string: openClawURL), !openClawURL.isEmpty else {
            return IntegrationTestResult(statusCode: nil, responseSnippet: "No OpenClaw URL configured")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let account = secretKeychainAccount,
           let secret = KeychainHelper.read(account: account),
           !secretHeaderName.isEmpty {
            request.setValue(secret, forHTTPHeaderField: secretHeaderName)
        }

        let payload: [String: Any] = [
            "source": "openfang",
            "hand": "collector",
            "topic": "OpenFang Wrapper E2E Test",
            "severity": "info",
            "title": "Test E2E (OpenClaw -> Telegram)",
            "summary": "Sample payload from OpenFang macOS wrapper integration test.",
            "bullets": [
                "Validates OpenFang -> OpenClaw webhook ingestion",
                "Confirms forwarding pipeline to Telegram via OpenClaw",
            ],
            "links": [["title": "OpenFang", "url": "https://github.com/RightNow-AI/openfang"]],
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "dedupe_key": "openfang-wrapper-e2e-test",
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            return IntegrationTestResult(
                statusCode: http?.statusCode,
                responseSnippet: String(decoding: data.prefix(512), as: UTF8.self)
            )
        } catch {
            return IntegrationTestResult(statusCode: nil, responseSnippet: "Request failed: \(error.localizedDescription)")
        }
    }
}
