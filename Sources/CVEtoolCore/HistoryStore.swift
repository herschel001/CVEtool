import CryptoKit
import Foundation

public final class HistoryStore: @unchecked Sendable {
    public let directory: URL
    private let lock = NSLock()
    private var items: [HistoryItem] = []
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        load()
    }

    public var imagesDirectory: URL { directory.appendingPathComponent("images", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("history.json") }

    public func snapshot() -> [HistoryItem] {
        lock.lock()
        defer { lock.unlock() }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    public func usedBytes() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        return items.reduce(0) { $0 + $1.byteSize }
    }

    public func filtered(_ filter: HistoryFilter, query: String) -> [HistoryItem] {
        snapshot().filter { $0.matches(filter) && $0.matchesQuery(query) }
    }

    @discardableResult
    public func addText(kind: ItemKind, text: String, limitBytes: Int64, now: Date = Date()) -> AddResult {
        let hash = Self.hash(Data("\(kind.rawValue)|\(text)".utf8))
        let size = max(Int64(Data(text.utf8).count), 1)
        return insert(hash: hash, byteSize: size, limitBytes: limitBytes, now: now) { id in
            HistoryItem(id: id, createdAt: now, kind: kind, text: text, byteSize: size, contentHash: hash, isScreenshot: false)
        } writePayload: { _ in }
    }

    @discardableResult
    public func addImage(_ data: Data, isScreenshot: Bool, limitBytes: Int64, now: Date = Date()) -> AddResult {
        let hash = Self.hash(data)
        let size = Int64(data.count)
        return insert(hash: hash, byteSize: size, limitBytes: limitBytes, now: now) { id in
            HistoryItem(
                id: id,
                createdAt: now,
                kind: isScreenshot ? .screenshot : .image,
                imageFilename: "\(id.uuidString).png",
                byteSize: size,
                contentHash: hash,
                isScreenshot: isScreenshot
            )
        } writePayload: { item in
            if let name = item.imageFilename {
                try? data.write(to: imagesDirectory.appendingPathComponent(name), options: .atomic)
            }
        }
    }

    public func imageData(for item: HistoryItem) -> Data? {
        guard let name = item.imageFilename else { return nil }
        return try? Data(contentsOf: imagesDirectory.appendingPathComponent(name))
    }

    public func shrink(to limitBytes: Int64) {
        lock.lock()
        let victims = CapacityPolicy.planShrink(
            items: items.map { CapacityItem(id: $0.id, createdAt: $0.createdAt, byteSize: $0.byteSize) },
            limitBytes: limitBytes
        )
        lock.unlock()
        delete(ids: victims)
    }

    public func delete(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        lock.lock()
        let doomed = items.filter { ids.contains($0.id) }
        items.removeAll { ids.contains($0.id) }
        persistLocked()
        lock.unlock()
        for item in doomed {
            if let name = item.imageFilename {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
            }
        }
    }

    private func insert(
        hash: String,
        byteSize: Int64,
        limitBytes: Int64,
        now: Date,
        make: (UUID) -> HistoryItem,
        writePayload: (HistoryItem) -> Void
    ) -> AddResult {
        lock.lock()
        if let index = items.firstIndex(where: { $0.contentHash == hash }) {
            items[index].createdAt = now
            let item = items[index]
            persistLocked()
            lock.unlock()
            return .movedToFront(item)
        }
        let decision = CapacityPolicy.planInsert(
            items: items.map { CapacityItem(id: $0.id, createdAt: $0.createdAt, byteSize: $0.byteSize) },
            incomingBytes: byteSize,
            limitBytes: limitBytes
        )
        switch decision {
        case .rejectOversized:
            lock.unlock()
            return .rejectedOversized
        case .insert(let evicting):
            let doomed = items.filter { evicting.contains($0.id) }
            items.removeAll { evicting.contains($0.id) }
            let item = make(UUID())
            items.append(item)
            persistLocked()
            lock.unlock()
            writePayload(item)
            for old in doomed {
                if let name = old.imageFilename {
                    try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
                }
            }
            return .inserted(item)
        }
    }

    private func load() {
        lock.lock()
        defer { lock.unlock() }
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? decoder.decode([HistoryItem].self, from: data) else { return }
        items = decoded
    }

    private func persistLocked() {
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    public static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
