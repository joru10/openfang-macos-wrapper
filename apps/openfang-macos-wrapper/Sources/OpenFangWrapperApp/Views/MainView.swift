import SwiftUI

struct MainView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                Text(state.controller.status.rawValue)
                    .font(.headline)
                Text(state.controller.statusDetail)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Start") { state.startOpenFang() }
                    .disabled(state.controller.status == .running || state.controller.status == .starting || state.controller.isBusy)
                Button("Stop") { state.stopOpenFang() }
                    .disabled(state.controller.status == .stopped || state.controller.status == .stopping || state.controller.isBusy)
                Button("Open Dashboard") { state.openDashboard() }
                if state.controller.status == .runningExternal {
                    Button("Adopt Control") { state.adoptControl() }
                        .disabled(!state.canAdoptControl())
                }
            }

            Text("Logs")
                .font(.headline)

            ScrollView {
                Text(state.logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(8)
            }
            .frame(maxHeight: .infinity)
            .background(Color(NSColor.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Copy Logs") { state.copyLogs() }
                Button("Reveal in Finder") { state.revealLogsInFinder() }
                Spacer()
                Text("Binary: \(state.settings.openFangPath.isEmpty ? "Not set" : state.settings.openFangPath)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(16)
    }

    private var statusColor: Color {
        switch state.controller.status {
        case .running, .runningExternal: return .green
        case .starting, .stopping: return .orange
        case .error: return .red
        case .stopped: return .gray
        }
    }
}
