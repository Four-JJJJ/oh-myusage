import Foundation

final class ThirdPartyBalanceBaselineStore: @unchecked Sendable {
    private struct Payload: Codable {
        var entries: [String: ThirdPartyBalanceBaselineTracker.Entry]
    }

    private let fileURL: URL
    private let fileManager: FileManager
    /// Baselines are persisted after every successful third-party refresh,
    /// which lands on the main actor, so the file IO lives on this queue;
    /// reads are synchronized against it to keep save-then-load ordered.
    private let ioQueue = DispatchQueue(label: "OhMyUsage.thirdPartyBaselineStore.io", qos: .utility)
    private var lastWrittenPayload: Data?

    init(fileManager: FileManager = .default, fileURL: URL? = nil) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let directory = appSupport.appendingPathComponent("OhMyUsage", isDirectory: true)
            self.fileURL = directory.appendingPathComponent("third_party_balance_baselines.json")
        }
    }

    func load() -> [String: ThirdPartyBalanceBaselineTracker.Entry] {
        ioQueue.sync { loadLocked() }
    }

    func save(_ entries: [String: ThirdPartyBalanceBaselineTracker.Entry]) {
        ioQueue.async { [weak self] in
            guard let self else { return }
            guard let data = self.encodePayload(entries) else { return }
            // Refreshes rewrite the same baselines almost every cycle; skip
            // the disk write when nothing changed.
            guard data != self.lastWrittenPayload else { return }
            do {
                if entries.isEmpty {
                    if self.fileManager.fileExists(atPath: self.fileURL.path) {
                        try self.fileManager.removeItem(at: self.fileURL)
                    }
                } else {
                    try PrivateProfileFile(url: self.fileURL, fileManager: self.fileManager).write(data)
                }
                self.lastWrittenPayload = data
            } catch {
                return
            }
        }
    }

    func reset() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            if self.fileManager.fileExists(atPath: self.fileURL.path) {
                try? self.fileManager.removeItem(at: self.fileURL)
            }
            self.lastWrittenPayload = nil
        }
    }

    private func loadLocked() -> [String: ThirdPartyBalanceBaselineTracker.Entry] {
        guard fileManager.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return [:]
        }
        return payload.entries
    }

    private func encodePayload(_ entries: [String: ThirdPartyBalanceBaselineTracker.Entry]) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(Payload(entries: entries))
    }
}
