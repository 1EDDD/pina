import Foundation

/// One variant explicitly advertised by an HLS master playlist.
public struct HLSVariant: Equatable {
    public let url: URL
    public let width: Int
    public let height: Int
    public let bandwidth: Int

    public init(url: URL, width: Int, height: Int, bandwidth: Int) {
        self.url = url
        self.width = width
        self.height = height
        self.bandwidth = bandwidth
    }
}

public enum HLSVariantError: Error, LocalizedError, Equatable {
    case emptyPlaylist
    case noVariants
    case no1080pVariant(availableHeights: [Int])
    case invalidVariantURI(String)

    public var errorDescription: String? {
        switch self {
        case .emptyPlaylist:
            return "The playlist is empty."
        case .noVariants:
            return "The playlist does not advertise any usable HLS variants."
        case .no1080pVariant(let heights):
            let detail = heights.isEmpty ? "no resolution metadata" : "available heights: " + heights.map(String.init).joined(separator: ", ")
            return "No 1080p rendition is advertised (\(detail))."
        case .invalidVariantURI(let value):
            return "Invalid HLS variant URI: \(value)"
        }
    }
}

/// Parses HLS master manifests. It never fabricates a resolution or upscales media.
public enum HLSVariantParser {
    private struct PendingVariant {
        let bandwidth: Int
        let width: Int
        let height: Int
    }

    public static func parse(masterPlaylist: String, masterURL: URL) throws -> [HLSVariant] {
        let lines = masterPlaylist.components(separatedBy: .newlines)
        guard lines.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#EXTM3U") }) else {
            throw HLSVariantError.emptyPlaylist
        }

        var pending: PendingVariant?
        var variants: [HLSVariant] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#EXT-X-STREAM-INF:") {
                let rawAttributes = String(line.dropFirst("#EXT-X-STREAM-INF:".count))
                let attributes = parseAttributes(rawAttributes)
                let bandwidth = Int(attributes["AVERAGE-BANDWIDTH"] ?? "")
                    ?? Int(attributes["BANDWIDTH"] ?? "") ?? 0
                let dimensions = (attributes["RESOLUTION"] ?? "")
                    .lowercased().split(separator: "x", omittingEmptySubsequences: false)
                let width = dimensions.count == 2 ? Int(dimensions[0]) ?? 0 : 0
                let height = dimensions.count == 2 ? Int(dimensions[1]) ?? 0 : 0
                pending = PendingVariant(bandwidth: bandwidth, width: width, height: height)
                continue
            }

            // A URI line follows EXT-X-STREAM-INF. Other comment lines may appear first.
            guard !line.hasPrefix("#"), let info = pending else { continue }
            guard let url = URL(string: line, relativeTo: masterURL)?.absoluteURL else {
                throw HLSVariantError.invalidVariantURI(line)
            }
            variants.append(HLSVariant(url: url, width: info.width, height: info.height, bandwidth: info.bandwidth))
            pending = nil
        }

        guard !variants.isEmpty else { throw HLSVariantError.noVariants }
        return variants
    }

    /// Selects the highest-bandwidth advertised 1080p landscape rendition.
    public static func select1080p(from variants: [HLSVariant]) throws -> HLSVariant {
        let heights = Array(Set(variants.map(\.height).filter { $0 > 0 })).sorted()
        guard let selected = variants
            .filter({ $0.height == 1080 && $0.width >= 1920 })
            .max(by: { $0.bandwidth < $1.bandwidth }) else {
            throw HLSVariantError.no1080pVariant(availableHeights: heights)
        }
        return selected
    }

    /// Explicit fallback for clients that prefer the best available rendition when 1080p is absent.
    public static func selectBestAvailable(from variants: [HLSVariant]) throws -> HLSVariant {
        guard let selected = variants.max(by: {
            if $0.height != $1.height { return $0.height < $1.height }
            if $0.width != $1.width { return $0.width < $1.width }
            return $0.bandwidth < $1.bandwidth
        }) else {
            throw HLSVariantError.noVariants
        }
        return selected
    }

    private static func parseAttributes(_ input: String) -> [String: String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        for character in input {
            if character == "\"" {
                inQuotes.toggle()
                current.append(character)
            } else if character == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { fields.append(current) }

        var result: [String: String] = [:]
        for field in fields {
            guard let equals = field.firstIndex(of: "=") else { continue }
            let key = String(field[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            var value = String(field[field.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if value.count >= 2, value.first == "\"", value.last == "\"" {
                value.removeFirst()
                value.removeLast()
            }
            result[key] = value
        }
        return result
    }
}
