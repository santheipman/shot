import Foundation

final class EventLog {
    static let shared = EventLog()

    private let fileURL: URL?
    private let queue = DispatchQueue(label: "dev.sanvq.shot.event-log")
    private let formatter = ISO8601DateFormatter()
    var isFileLoggingEnabled: Bool { fileURL != nil }

    private init() {
        // The environment variable only reaches Shot when it is launched from a
        // shell, which is not how it normally runs. The defaults key covers a
        // normal launch: `defaults write dev.sanvq.shot eventLogPath /tmp/shot.log`.
        let path = ProcessInfo.processInfo.environment["SHOT_EVENT_LOG"]
            ?? UserDefaults.standard.string(forKey: "eventLogPath")
        guard let path, !path.isEmpty else {
            fileURL = nil
            return
        }
        fileURL = URL(fileURLWithPath: path)
    }

    func write(_ message: String) {
        guard let fileURL else { return }

        let line = "\(formatter.string(from: Date())) \(message)\n"
        queue.async {
            let data = Data(line.utf8)
            if FileManager.default.fileExists(atPath: fileURL.path),
               let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
