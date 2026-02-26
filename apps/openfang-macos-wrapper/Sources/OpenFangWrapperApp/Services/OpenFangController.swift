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

            attachPipeReader(out.fileHandleForReading, label: "stdout")
            attachPipeReader(err.fileHandleForReading, label: "stderr")

            process.terminationHandler = { [weak self] terminated in
                Task { [weak self] in
                    await self?.logManager.append("[\(Date())] openfang start process exited: \(terminated.terminationStatus)")
                }
            }

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

    func stop(binaryPath: String, dashboardURL: String, completion: ((Bool) -> Void)? = nil) {
        guard !isBusy else {
            completion?(false)
            return
        }
        if status == .stopped || status == .stopping {
            completion?(status == .stopped)
            return
        }

        isBusy = true
        status = .stopping
        statusDetail = "Stopping OpenFang..."

        Task {
            await logManager.append("[\(Date())] Stopping OpenFang")

            if await tryStopCommand(binaryPath: binaryPath),
               await verifyStopped(dashboardURL: dashboardURL) {
                completion?(true)
                return
            }

            if await tryStopTrackedProcess(binaryPath: binaryPath),
               await verifyStopped(dashboardURL: dashboardURL) {
                completion?(true)
                return
            }

            if await tryPortFallback(binaryPath: binaryPath, dashboardURL: dashboardURL),
               await verifyStopped(dashboardURL: dashboardURL) {
                completion?(true)
                return
            }

            status = .error
            statusDetail = "Stop failed"
            isBusy = false
            completion?(false)
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

    func canAdoptControl(binaryPath: String, dashboardURL: String) -> Bool {
        guard status == .runningExternal,
              let port = dashboardPort(from: dashboardURL),
              let listener = findListeningPID(port: port) else {
            return false
        }
        return validatePID(listener.pid, containsPath: binaryPath)
    }

    func adoptControl(binaryPath: String, dashboardURL: String) -> Bool {
        guard canAdoptControl(binaryPath: binaryPath, dashboardURL: dashboardURL),
              let port = dashboardPort(from: dashboardURL),
              let listener = findListeningPID(port: port) else {
            return false
        }

        trackedPID = listener.pid
        status = .running
        statusDetail = "Adopted control for pid \(listener.pid)"
        startHealthPolling(dashboardURL: dashboardURL)

        Task {
            await logManager.append("[\(Date())] Adopted external OpenFang process: pid=\(listener.pid)")
        }
        return true
    }

    func shutdown() {
        healthTask?.cancel()
    }

    private func attachPipeReader(_ handle: FileHandle, label: String) {
        handle.readabilityHandler = { [weak self] fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else {
                fileHandle.readabilityHandler = nil
                return
            }

            guard let line = String(data: data, encoding: .utf8), !line.isEmpty else { return }
            Task { [weak self] in
                await self?.logManager.append("[\(label)] \(line.trimmingCharacters(in: .newlines))")
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
                        if self.status != .stopping {
                            self.status = .running
                            self.statusDetail = "Healthy"
                        }
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

    private func tryPortFallback(binaryPath: String, dashboardURL: String) async -> Bool {
        guard let port = dashboardPort(from: dashboardURL),
              let listener = findListeningPID(port: port) else {
            return false
        }

        guard listener.command.lowercased().contains("openfang") || validatePID(listener.pid, containsPath: binaryPath) else {
            await logManager.append("[\(Date())] Port \(port) listener did not match OpenFang")
            return false
        }

        _ = kill(listener.pid, SIGTERM)
        await logManager.append("[\(Date())] Fallback SIGTERM pid \(listener.pid) on port \(port)")
        trackedPID = listener.pid
        return true
    }

    private func findListeningPID(port: Int) -> (pid: Int32, command: String)? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-iTCP:\(port)", "-sTCP:LISTEN", "-n", "-P", "-Fp", "-Fc"]

        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()

        do {
            try proc.run()
            proc.waitUntilExit()
            guard proc.terminationStatus == 0,
                  let data = try out.fileHandleForReading.readToEnd(),
                  let text = String(data: data, encoding: .utf8) else {
                return nil
            }

            let lines = text.split(separator: "\n").map(String.init)
            var pid: Int32?
            var command = ""
            for line in lines {
                if line.hasPrefix("p") { pid = Int32(line.dropFirst()) }
                if line.hasPrefix("c") { command = String(line.dropFirst()) }
                if pid != nil, !command.isEmpty { break }
            }

            guard let foundPID = pid else { return nil }
            return (foundPID, command)
        } catch {
            return nil
        }
    }

    private func dashboardPort(from dashboardURL: String) -> Int? {
        guard let url = URL(string: dashboardURL) else { return 4200 }
        if let port = url.port { return port }
        return 4200
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
            let configuredPath = containsPath.trimmingCharacters(in: .whitespacesAndNewlines)
            let pathMatch = !configuredPath.isEmpty && command.contains(configuredPath)
            return pathMatch || command.lowercased().contains("openfang")
        } catch {
            return false
        }
    }

    private func verifyStopped(dashboardURL: String) async -> Bool {
        healthTask?.cancel()

        for _ in 0 ..< 10 {
            let healthy = await HealthChecker.isHealthy(urlString: dashboardURL)
            if !healthy {
                status = .stopped
                statusDetail = "Stopped"
                isBusy = false
                startProcess = nil
                trackedPID = nil
                return true
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }

        status = .error
        statusDetail = "Stop requested but service still reachable"
        isBusy = false
        return false
    }
}
