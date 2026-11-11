import Foundation

public struct CapacityItem: Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var byteSize: Int64

    public init(id: UUID, createdAt: Date, byteSize: Int64) {
        self.id = id
        self.createdAt = createdAt
        self.byteSize = byteSize
    }
}

public enum InsertDecision: Equatable, Sendable {
    case rejectOversized
    case insert(evicting: [UUID])
}

public enum CapacityPolicy {
    public static let choicesMB = [50, 100, 200, 500, 1024]

    public static func bytes(fromMegabytes megabytes: Int) -> Int64 {
        Int64(megabytes) * 1024 * 1024
    }

    /// Oldest first. Equal timestamps break ties by UUID string so the order is stable.
    public static func oldestFirst(_ items: [CapacityItem]) -> [CapacityItem] {
        items.sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public static func planInsert(items: [CapacityItem], incomingBytes: Int64, limitBytes: Int64) -> InsertDecision {
        if incomingBytes > limitBytes {
            return .rejectOversized
        }
        var used = items.reduce(Int64(0)) { $0 + $1.byteSize }
        var evicting: [UUID] = []
        for item in oldestFirst(items) {
            if used + incomingBytes <= limitBytes { break }
            evicting.append(item.id)
            used -= item.byteSize
        }
        return .insert(evicting: evicting)
    }

    public static func planShrink(items: [CapacityItem], limitBytes: Int64) -> [UUID] {
        var used = items.reduce(Int64(0)) { $0 + $1.byteSize }
        var evicting: [UUID] = []
        guard used > limitBytes else { return [] }
        for item in oldestFirst(items) {
            if used <= limitBytes { break }
            evicting.append(item.id)
            used -= item.byteSize
        }
        return evicting
    }
}
