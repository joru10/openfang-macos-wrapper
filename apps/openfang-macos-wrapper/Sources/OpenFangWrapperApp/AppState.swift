import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var settings: AppSettings {
        didSet { saveSettings() }
    }
    @Published var logText = ""
    @Published var integrationResult = ""
    @Published var selectedTargetID: UUID?

    let logManager = LogManager()
    let controller: OpenFangController

    private let settingsKey = "OpenFangWrapperSettings"
    private var logTask: Task<Void, Never>?

    init() {
        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = .defaults
        }

        controller = OpenFangController(logManager: logManager)
        selectedTargetID = settings.integrationTargets.first?.id

        startLogTailLoop()
        controller.detectExternalRunning(dashboardURL: settings.dashboardURL)
    }

    func startOpenFang() {
        controller.start(binaryPath: settings.openFangPath, dashboardURL: settings.dashboardURL)
    }

    func stopOpenFang() {
        controller.stop(binaryPath: settings.openFangPath, dashboardURL: settings.dashboardURL)
    }

    func openDashboard() {
        if controller.status == .stopped {
            startOpenFang()
            return
        }

        guard let url = URL(string: settings.dashboardURL) else { return }
        NSWorkspace.shared.open(url)
    }

    func revealLogsInFinder() {
        Task {
            let url = await logManager.logFileURL
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func copyLogs() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(logText, forType: .string)
    }

    func chooseBinaryPath() {
        let panel = NSOpenPanel()
        panel.title = "Select openfang binary"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            settings.openFangPath = url.path
        }
    }

    func saveSecret(_ secret: String, account: String) {
        guard !account.isEmpty else { return }
        try? KeychainHelper.save(value: secret, account: account)
    }

    func testSelectedWebhook() {
        guard let target = settings.integrationTargets.first(where: { $0.id == selectedTargetID }) else {
            integrationResult = "No target selected"
            return
        }

        Task {
            do {
                let result = try await IntegrationManager.testWebhook(target: target)
                integrationResult = "Webhook test status: \(result.statusCode.map(String.init) ?? "n/a")\n\(result.responseSnippet)"
            } catch {
                integrationResult = "Webhook test failed: \(error.localizedDescription)"
            }
        }
    }

    func checkGWReachability() {
        Task {
            let result = await IntegrationManager.checkReachability(urlString: settings.openClawGWURL)
            integrationResult = "GW reachability status: \(result.statusCode.map(String.init) ?? "n/a")\n\(result.responseSnippet)"
        }
    }

    func testE2EToTelegram() {
        Task {
            let result = await IntegrationManager.testE2E(
                openClawURL: settings.openClawGWURL,
                secretHeaderName: settings.openClawSecretHeader,
                secretKeychainAccount: settings.openClawSecretKeychainKey
            )
            let status = result.statusCode.map(String.init) ?? "n/a"
            integrationResult = "E2E POST status: \(status)\n\(result.responseSnippet)\n\nIf status is 2xx, confirm delivery in Telegram manually."
        }
    }

    func addIntegrationTarget() {
        var target = IntegrationTarget.empty
        target.name = "New Target"
        settings.integrationTargets.append(target)
        selectedTargetID = target.id
    }

    func removeSelectedTarget() {
        guard let selectedTargetID else { return }
        settings.integrationTargets.removeAll(where: { $0.id == selectedTargetID })
        self.selectedTargetID = settings.integrationTargets.first?.id
    }

    func updateTarget(_ target: IntegrationTarget) {
        guard let idx = settings.integrationTargets.firstIndex(where: { $0.id == target.id }) else { return }
        settings.integrationTargets[idx] = target
    }

    private func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: settingsKey)
        }
    }

    private func startLogTailLoop() {
        logTask?.cancel()
        logTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let tail = await logManager.tail(lines: settings.logLines)
                await MainActor.run {
                    self.logText = tail
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }
}
