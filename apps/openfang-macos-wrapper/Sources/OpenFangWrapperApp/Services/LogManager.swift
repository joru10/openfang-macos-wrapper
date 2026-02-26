import Foundation

actor LogManager {
    private(set) var logFileURL: URL

    init() {
        let logs = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/OpenFangWrapper", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        self.logFileURL = logs.appendingPathComponent("openfang.log")

        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }
    }

    func append(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: logFileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            // no-op
        }
    }

    func tail(lines: Int) -> String {
        guard let data = try? Data(contentsOf: logFileURL),
              let text = String(data: data, encoding: .utf8) else {
            return ""
        }

        let rows = text.split(separator: "\n", omittingEmptySubsequences: false)
        return rows.suffix(max(0, lines)).joined(separator: "\n")
    }
}
