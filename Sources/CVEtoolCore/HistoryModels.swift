import Foundation

public enum ItemKind: String, Codable, Sendable {
    case text
    case image
    case link
    case color
    case screenshot
}

public enum HistoryFilter: String, CaseIterable, Sendable {
    case all
    case text
    case image
    case link
    case color
    case screenshot

    public var title: String {
        switch self {
        case .all: return "全部"
        case .text: return "文本"
        case .image: return "图片"
        case .link: return "链接"
        case .color: return "颜色"
        case .screenshot: return "截图"
        }
    }
}

public struct HistoryItem: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var createdAt: Date
    public var kind: ItemKind
    public var text: String?
    public var imageFilename: String?
    public var byteSize: Int64
    public var contentHash: String
    public var isScreenshot: Bool

    public init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: ItemKind,
        text: String? = nil,
        imageFilename: String? = nil,
        byteSize: Int64,
        contentHash: String,
        isScreenshot: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.text = text
        self.imageFilename = imageFilename
        self.byteSize = byteSize
        self.contentHash = contentHash
        self.isScreenshot = isScreenshot
    }

    public func matches(_ filter: HistoryFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .text:
            return kind == .text
        case .image:
            return kind == .image || kind == .screenshot || isScreenshot
        case .link:
            return kind == .link
        case .color:
            return kind == .color
        case .screenshot:
            return isScreenshot || kind == .screenshot
        }
    }

    public func matchesQuery(_ query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if needle.isEmpty { return true }
        return (text ?? "").localizedStandardContains(needle)
    }
}

public enum AddResult: Equatable, Sendable {
    case inserted(HistoryItem)
    case movedToFront(HistoryItem)
    case rejectedOversized
}
