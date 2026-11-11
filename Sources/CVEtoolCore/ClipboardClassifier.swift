import Foundation

public enum ClipboardPayload: Equatable, Sendable {
    case text(String)
    case link(String)
    case color(String)
    case image(Data)
    case ignore
}

public enum ClipboardClassifier {
    public static func classify(text: String?, imagePNG: Data?, fileOnly: Bool) -> ClipboardPayload {
        if let imagePNG, !imagePNG.isEmpty {
            return .image(imagePNG)
        }
        if fileOnly {
            return .ignore
        }
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .ignore
        }
        if let color = normalizedColor(raw) {
            return .color(color)
        }
        if let link = normalizedLink(raw) {
            return .link(link)
        }
        return .text(raw)
    }

    public static func normalizedColor(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") {
            let hex = String(text.dropFirst())
            guard hex.allSatisfy(\.isHexDigit), [3, 6, 8].contains(hex.count) else { return nil }
            return "#" + hex.uppercased()
        }
        let lower = text.lowercased().replacingOccurrences(of: " ", with: "")
        guard lower.hasPrefix("rgb(") || lower.hasPrefix("rgba("), lower.hasSuffix(")") else { return nil }
        let inner = lower.drop(while: { $0 != "(" }).dropFirst().dropLast()
        let parts = inner.split(separator: ",").map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        let channels = parts.prefix(3).compactMap { Int($0) }
        guard channels.count == 3, channels.allSatisfy({ (0...255).contains($0) }) else { return nil }
        return String(format: "#%02X%02X%02X", channels[0], channels[1], channels[2])
    }

    public static func normalizedLink(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.contains(where: \.isNewline), !text.contains(" ") else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme), url.host != nil || scheme == "mailto" {
            return text
        }
        if text.lowercased().hasPrefix("www."), text.contains("."), !text.contains(" ") {
            return "https://" + text
        }
        return nil
    }
}
