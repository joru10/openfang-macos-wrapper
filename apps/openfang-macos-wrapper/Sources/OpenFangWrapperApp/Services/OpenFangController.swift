import Foundation

@MainActor
final class OpenFangController: ObservableObject {
    @Published var status: OpenFangStatus = .stopped
    @Published var statusDetail: String = ""
    @Published var isBusy = false

    private var startProcess: Process?
    private var trackedPID: Int32?
    private var healthTask: Task<Void, Never>?
    private let logManager: LogManager

    init(logManager: LogManager) {
        self.logManager = logManager
    }

    func start(binaryPath: String, dashboardURL: String) {
        guard !isBusy else { return }
        if status == .running || status == .starting || status == .runningExternal {
            statusDetail = "Already running"
            return
        }

        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            status = .error
            statusDetail = "OpenFang binary not executable: \(binaryPath)"
            return
        }

        isBusy = true
        status = .starting
        statusDetail = "Starting OpenFang..."

        Task {
            await logManager.append("[\(Date())] Starting OpenFang: \(binaryPath) start")

            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["start"]

            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err

            startPipeReader(out.fileHandleForReading)
            startPipeReader(err.fileHandleForReading)

            do {
                try process.run()
                startProcess = process
                trackedPID = process.processIdentifier
            } catch {
                status = .error
                statusDetail = "Failed to start: \(error.localizedDescription)"
                isBusy = false
                await logManager.append("[\(Date())] ERROR start failed: \(error)")
                return
            }

            startHealthPolling(dashboardURL: dashboardURL)
            isBusy = false
        }
    }

    func stop(binaryPath: String, dashboardURL: String) {
        guard !isBusy else { return }
        if status == .stopped || status == .stopping {
            return
        }

        isBusy = true
        status = .stopping
        statusDetail = "Stopping OpenFang..."

        Task {
            await logManager.append("[\(Date())] Stopping OpenFang")

            if await tryStopCommand(binaryPath: binaryPath) {
                await verifyStopped(dashboardURL: dashboardURL)
                return
            }

            if await tryStopTrackedProcess(binaryPath: binaryPath) {
                await verifyStopped(dashboardURL: dashboardURL)
                return
            }

            if await tryPortFallback(binaryPath: binaryPath) {
                await verifyStopped(dashboardURL: dashboardURL)
                return
            }

            status = .error
            statusDetail = "Stop failed"
            isBusy = false
        }
    }

    func detectExternalRunning(dashboardURL: String) {
        Task {
            let healthy = await HealthChecker.isHealthy(urlString: dashboardURL)
            if healthy, status == .stopped {
                status = .runningExternal
                statusDetail = "Detected listener not started by app"
            }
        }
    }

    func shutdown() {
        healthTask?.cancel()
    }

    private func startPipeReader(_ handle: FileHandle) {
        handle.readabilityHandler = { [weak self] fileHandle in
            guard let data = try? fileHandle.readToEnd(), !data.isEmpty,
                  let line = String(data: data, encoding: .utf8), !line.isEmpty else { return }
            Task { [weak self] in
                await self?.logManager.append(line.trimmingCharacters(in: .newlines))
            }
        }
    }

    private func startHealthPolling(dashboardURL: String) {
        healthTask?.cancel()
        healthTask = Task { [weak self] in
            guard let self else { return }
            var checks = 0

            while !Task.isCancelled {
                let healthy = await HealthChecker.isHealthy(urlString: dashboardURL)
                checks += 1

                if healthy {
                    await MainActor.run {
                        self.status = .running
                        self.statusDetail = "Healthy"
                    }
                } else if checks > 15, self.status == .starting {
                    await MainActor.run {
                        self.status = .error
                        self.statusDetail = "Health check timeout"
                    }
                    break
                }

                let delay = (self.status == .starting) ? 1_500_000_000 : 7_000_000_000
                try? await Task.sleep(nanoseconds: UInt64(delay))
            }
        }
    }

    private func tryStopCommand(binaryPath: String) async -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = ["stop"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            await logManager.append("[\(Date())] openfang stop exit: \(process.terminationStatus)")
            return process.terminationStatus == 0
        } catch {
            await logManager.append("[\(Date())] openfang stop unavailable: \(error.localizedDescription)")
            return false
        }
    }

    private func tryStopTrackedProcess(binaryPath: String) async -> Bool {
        guard let pid = trackedPID else { return false }
        guard validatePID(pid, containsPath: binaryPath) else { return false }

        let term = kill(pid, SIGTERM)
        await logManager.append("[\(Date())] SIGTERM tracked pid \(pid), result=\(term)")

        for _ in 0 ..< 8 {
            if !validatePID(pid, containsPath: binaryPath) {
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        _ = kill(pid, SIGKILL)
        await logManager.append("[\(Date())] SIGKILL tracked pid \(pid)")
        return true
    }

    private func tryPortFallback(binaryPath: String) async -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-iTCP:4200", "-sTCP:LISTEN", "-n", "-P", "-Fp", "-Fc"]

        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            guard let data = try out.fileHandleForReading.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else {
                return false
            }

            let lines = text.split(separator: "\n").map(String.init)
            var pid: Int32?
            var cmd = ""
            for line in lines {
                if line.hasPrefix("p") { pid = Int32(line.dropFirst()) }
                if line.hasPrefix("c") { cmd = String(line.dropFirst()) }
            }

            guard let foundPID = pid else { return false }
            guard cmd.lowercased().contains("openfang") || validatePID(foundPID, containsPath: binaryPath) else {
                await logManager.append("[\(Date())] Port 4200 listener did not match OpenFang")
                return false
            }

            _ = kill(foundPID, SIGTERM)
            await logManager.append("[\(Date())] Fallback SIGTERM pid \(foundPID)")
            return true
        } catch {
            await logManager.append("[\(Date())] lsof fallback failed: \(error.localizedDescription)")
            return false
        }
    }

    private func validatePID(_ pid: Int32, containsPath: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "command="]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let data = try out.fileHandleForReading.readToEnd(),
                  let command = String(data: data, encoding: .utf8) else { return false }
            return command.contains(containsPath) || command.lowercased().contains("openfang")
        } catch {
            return false
        }
    }

    private func verifyStopped(dashboardURL: String) async {
        healthTask?.cancel()

        for _ in 0 ..< 10 {
            let healthy = await HealthChecker.isHealthy(urlString: dashboardURL)
            if !healthy {
                status = .stopped
                statusDetail = "Stopped"
                isBusy = false
                return
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        status = .error
        statusDetail = "Stop requested but service still reachable"
        isBusy = false
    }
}
