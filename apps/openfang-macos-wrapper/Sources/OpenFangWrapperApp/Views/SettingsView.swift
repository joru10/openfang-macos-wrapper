import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var openClawSecretDraft = ""
    @State private var provider: LLMProvider = .groq
    @State private var providerKeyDraft = ""
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Text("General") }
                .tag(0)

            integrationsTab
                .tabItem { Text("Integrations") }
                .tag(1)

            providerTab
                .tabItem { Text("Provider") }
                .tag(2)
        }
        .padding(16)
    }

    private var generalTab: some View {
        Form {
            HStack {
                TextField("OpenFang binary path", text: $state.settings.openFangPath)
                Button("Choose...") { state.chooseBinaryPath() }
            }

            TextField("Dashboard URL", text: $state.settings.dashboardURL)

            Picker("Quit behavior", selection: $state.settings.quitBehavior) {
                ForEach(QuitBehavior.allCases) { behavior in
                    Text(behavior.rawValue).tag(behavior)
                }
            }

            Stepper(value: $state.settings.logLines, in: 100 ... 5000, step: 100) {
                Text("Log lines shown: \(state.settings.logLines)")
            }

            Text("OpenFang is expected on localhost:4200 unless changed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var integrationsTab: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading) {
                Text("Targets")
                    .font(.headline)
                List(selection: $state.selectedTargetID) {
                    ForEach(state.settings.integrationTargets) { target in
                        Text(target.name.isEmpty ? "Unnamed target" : target.name)
                            .tag(target.id)
                    }
                }
                HStack {
                    Button("Add") { state.addIntegrationTarget() }
                    Button("Delete") { state.removeSelectedTarget() }
                        .disabled(state.selectedTargetID == nil)
                }
            }
            .frame(width: 220)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let selectedTarget = state.settings.integrationTargets.first(where: { $0.id == state.selectedTargetID }) {
                        IntegrationTargetEditor(target: selectedTarget) { updated in
                            state.updateTarget(updated)
                        }

                        HStack {
                            Button("Test Webhook") { state.testSelectedWebhook() }
                            Text("POST sample payload to selected target")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Select an integration target")
                            .foregroundStyle(.secondary)
                    }

                    Divider().padding(.vertical, 8)

                    Text("OpenClaw GW")
                        .font(.headline)

                    TextField("OpenClaw GW webhook URL", text: $state.settings.openClawGWURL)
                    TextField("Secret header name", text: $state.settings.openClawSecretHeader)

                    HStack {
                        TextField("Secret keychain account", text: Binding(
                            get: { state.settings.openClawSecretKeychainKey ?? "" },
                            set: { state.settings.openClawSecretKeychainKey = $0.isEmpty ? nil : $0 }
                        ))
                        SecureField("Secret value", text: $openClawSecretDraft)
                        Button("Save Secret") {
                            guard let account = state.settings.openClawSecretKeychainKey, !openClawSecretDraft.isEmpty else { return }
                            state.saveSecret(openClawSecretDraft, account: account)
                            openClawSecretDraft = ""
                        }
                    }

                    HStack {
                        Button("Check GW Reachability") { state.checkGWReachability() }
                        Button("Test E2E (OpenClaw -> Telegram)") { state.testE2EToTelegram() }
                    }

                    Text(state.integrationResult)
                        .font(.system(.footnote, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                    Text("Policy: OpenFang -> OpenClaw webhook -> Telegram (OpenClaw is sole Telegram sender)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var providerTab: some View {
        Form {
            Text("Configure OpenFang LLM Provider")
                .font(.headline)

            Picker("Provider", selection: $provider) {
                ForEach(LLMProvider.allCases) { p in
                    Text(p.title).tag(p)
                }
            }

            SecureField("API Key", text: $providerKeyDraft)

            HStack {
                Button("Save Provider Key") {
                    state.setProviderKey(provider: provider, apiKey: providerKeyDraft)
                    providerKeyDraft = ""
                }
                Button("Run OpenFang Doctor") {
                    state.runDoctor()
                }
            }

            Text("Writes \(provider.envKey) into ~/.openfang/.env")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text(state.integrationResult)
                .font(.system(.footnote, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(NSColor.textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct IntegrationTargetEditor: View {
    @State var target: IntegrationTarget
    var onChange: (IntegrationTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Configuration")
                .font(.headline)

            TextField("Name", text: $target.name)
                .onChange(of: target) { _ in onChange(target) }

            TextField("URL", text: $target.url)
                .onChange(of: target) { _ in onChange(target) }

            Picker("Payload format", selection: $target.payloadFormat) {
                ForEach(PayloadFormat.allCases) { format in
                    Text(format.rawValue).tag(format)
                }
            }
            .onChange(of: target) { _ in onChange(target) }

            TextField("Secret keychain account (optional)", text: Binding(
                get: { target.secretKeychainKey ?? "" },
                set: {
                    target.secretKeychainKey = $0.isEmpty ? nil : $0
                    onChange(target)
                }
            ))

            Text("Headers")
                .font(.subheadline)
            HeaderEditor(headers: target.headers) { headers in
                target.headers = headers
                onChange(target)
            }
        }
    }
}

private struct HeaderEditor: View {
    @State private var headers: [String: String]
    @State private var key = ""
    @State private var value = ""
    var onUpdate: ([String: String]) -> Void

    init(headers: [String: String], onUpdate: @escaping ([String: String]) -> Void) {
        _headers = State(initialValue: headers)
        self.onUpdate = onUpdate
    }

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(headers.keys.sorted(), id: \.self) { headerKey in
                HStack {
                    Text(headerKey).font(.system(.footnote, design: .monospaced))
                    Spacer()
                    Text(headers[headerKey] ?? "")
                        .font(.system(.footnote, design: .monospaced))
                    Button("Remove") {
                        headers.removeValue(forKey: headerKey)
                        onUpdate(headers)
                    }
                }
            }

            HStack {
                TextField("Header", text: $key)
                TextField("Value", text: $value)
                Button("Add") {
                    guard !key.isEmpty else { return }
                    headers[key] = value
                    key = ""
                    value = ""
                    onUpdate(headers)
                }
            }
        }
    }
}
