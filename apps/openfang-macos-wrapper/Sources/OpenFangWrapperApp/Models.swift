import Foundation

enum OpenFangStatus: String, Codable, CaseIterable {
    case stopped = "Stopped"
    case starting = "Starting"
    case running = "Running"
    case stopping = "Stopping"
    case runningExternal = "Running (external)"
    case error = "Error"
}

enum QuitBehavior: String, Codable, CaseIterable, Identifiable {
    case ask = "Ask"
    case stopAndQuit = "Stop and Quit"
    case leaveRunning = "Leave Running"

    var id: String { rawValue }
}

enum PayloadFormat: String, Codable, CaseIterable, Identifiable {
    case json = "JSON"
    case plainText = "Plain text"

    var id: String { rawValue }
}

enum LLMProvider: String, Codable, CaseIterable, Identifiable {
    case groq
    case openai
    case openrouter
    case anthropic
    case gemini
    case deepseek
    case google
    case together
    case mistral
    case fireworks

    var id: String { rawValue }

    var envKey: String {
        switch self {
        case .groq: return "GROQ_API_KEY"
        case .openai: return "OPENAI_API_KEY"
        case .openrouter: return "OPENROUTER_API_KEY"
        case .anthropic: return "ANTHROPIC_API_KEY"
        case .gemini: return "GEMINI_API_KEY"
        case .deepseek: return "DEEPSEEK_API_KEY"
        case .google: return "GOOGLE_API_KEY"
        case .together: return "TOGETHER_API_KEY"
        case .mistral: return "MISTRAL_API_KEY"
        case .fireworks: return "FIREWORKS_API_KEY"
        }
    }

    var title: String {
        rawValue.uppercased()
    }
}

struct IntegrationTarget: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var headers: [String: String]
    var secretKeychainKey: String?
    var payloadFormat: PayloadFormat

    static let empty = IntegrationTarget(
        name: "",
        url: "",
        headers: [:],
        secretKeychainKey: nil,
        payloadFormat: .json
    )
}

struct AppSettings: Codable {
    var openFangPath: String
    var dashboardURL: String
    var logLines: Int
    var quitBehavior: QuitBehavior
    var openClawGWURL: String
    var openClawSecretHeader: String
    var openClawSecretKeychainKey: String?
    var integrationTargets: [IntegrationTarget]

    static let defaults = AppSettings(
        openFangPath: BinaryDiscovery.findOpenFangPath() ?? "",
        dashboardURL: "http://localhost:4200",
        logLines: 1000,
        quitBehavior: .ask,
        openClawGWURL: "",
        openClawSecretHeader: "X-Webhook-Secret",
        openClawSecretKeychainKey: nil,
        integrationTargets: []
    )
}

enum BinaryDiscovery {
    static func findOpenFangPath() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/opt/homebrew/bin/openfang",
            "/usr/local/bin/openfang",
            "\(home)/.openfang/bin/openfang",
        ]

        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lic", "which openfang"]

        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               let data = try out.fileHandleForReading.readToEnd(),
               var path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                if path.hasPrefix("/") {
                    return path
                }
                path = URL(fileURLWithPath: path).path
                return path
            }
        } catch {
            return nil
        }
        return nil
    }
}
