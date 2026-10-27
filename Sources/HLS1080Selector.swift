import AVFoundation
import Foundation

/// Selects an explicitly advertised 1080p HLS variant from a master playlist.
/// This does not upscale lower-resolution streams or invent missing variants.
public enum HLS1080Selector {
    public enum SelectionError: Error, LocalizedError {
        case invalidUTF8
        case no1080pVariant(availableHeights: [Int])
        case noVariantURI

        public var errorDescription: String? {
            switch self {
            case .invalidUTF8:
                return "The HLS master playlist was not valid UTF-8."
            case .no1080pVariant(let heights):
                let values = heights.isEmpty
                    ? "none were advertised"
                    : "advertised heights: " + heights.map(String.init).joined(separator: ", ")
                return "The source does not advertise a 1080p variant ((values))."
            case .noVariantURI:
                return "An HLS variant did not have a valid URI."
            }
        }
    }

    private struct Variant {
        let url: URL
        let width: Int
        let height: Int
        let bandwidth: Int
    }

    /// Downloads a master manifest and returns its best explicitly advertised
    /// 1080p variant URL. Relative variant paths are resolved against masterURL.
    public static func select1080p(
        from masterURL: URL,
        using session: URLSession = .shared
    ) async throws -> URL {
        let (data, _) = try await session.data(from: masterURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SelectionError.invalidUTF8
        }

        let lines = text.components(separatedBy: .newlines)
        var pending: (bandwidth: Int, width: Int, height: Int)?
        var variants: [Variant] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let attributes = parseAttributes(
                    String(line.dropFirst("#EXT-X-STREAM-INF:".count))
                )
                let bandwidth = Int(attributes["AVERAGE-BANDWIDTH"] ?? "")
                    ?? Int(attributes["BANDWIDTH"] ?? "")
                    ?? 0

                let resolution = (attributes["RESOLUTION"] ?? "")
                    .split(separator: "x", omittingEmptySubsequences: false)
                let width = resolution.count == 2 ? Int(resolution[0]) ?? 0 : 0
                let height = resolution.count == 2 ? Int(resolution[1]) ?? 0 : 0
                pending = (bandwidth, width, height)
                continue
            }

            // Per RFC 8216, the URI line follows EXT-X-STREAM-INF.
            guard !line.hasPrefix("#"), let info = pending else { continue }
            defer { pending = nil }

            guard let variantURL = URL(string: line, relativeTo: masterURL)?.absoluteURL else {
                throw SelectionError.noVariantURI
            }
            variants.append(
                Variant(
                    url: variantURL,
                    width: info.width,
                    height: info.height,
                    bandwidth: info.bandwidth
                )
            )
        }

        let advertisedHeights = Array(Set(variants.map(\.height).filter { $0 > 0 })).sorted()
        let candidates = variants.filter { $0.height == 1080 && $0.width >= 1920 }
        guard let best = candidates.max(by: { $0.bandwidth < $1.bandwidth }) else {
            throw SelectionError.no1080pVariant(availableHeights: advertisedHeights)
        }
        return best.url
    }

    /// Convenience helper for AVPlayer after selecting a 1080p variant URL.
    /// The selected source still needs to actually contain 1080p media.
    public static func makePlayerItem(for1080pVariant url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        item.preferredMaximumResolution = CGSize(width: 1920, height: 1080)
        item.preferredPeakBitRate = 0 // no app-imposed peak bitrate cap
        return item
    }

    /// Splits HLS attribute lists on commas while respecting quoted values.
    private static func parseAttributes(_ input: String) -> [String: String] {
        var pairs: [String] = []
        var current = ""
        var inQuotes = false

        for character in input {
            if character == "\"" {
                inQuotes.toggle()
                current.append(character)
            } else if character == "," && !inQuotes {
                pairs.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { pairs.append(current) }

        var result: [String: String] = [:]
        for pair in pairs {
            guard let equals = pair.firstIndex(of: "=") else { continue }
            let key = String(pair[..<equals]).trimmingCharacters(in: .whitespaces)
            var value = String(pair[pair.index(after: equals)...])
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.first == "\"", value.last == "\"" {
                value.removeFirst()
                value.removeLast()
            }
            result[key] = value
        }
        return result
    }
}
