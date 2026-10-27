import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Fetches an HLS master playlist and chooses a real, advertised 1080p rendition.
/// Use only with media streams you own or are authorized to access.
public enum HLS1080Selector {
    public enum Policy: Equatable {
        /// Fail clearly when the source does not advertise 1080p.
        case require1080p
        /// Select 1080p when available, otherwise use the best advertised variant.
        case prefer1080pAllowFallback
    }

    public struct Result: Equatable {
        public let variant: HLSVariant
        public let usedFallback: Bool
    }

    public static func select(
        from masterURL: URL,
        policy: Policy = .require1080p,
        session: URLSession = .shared
    ) async throws -> Result {
        let (data, response) = try await session.data(from: masterURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let manifest = String(data: data, encoding: .utf8) else {
            throw HLSVariantError.emptyPlaylist
        }
        let variants = try HLSVariantParser.parse(masterPlaylist: manifest, masterURL: masterURL)
        do {
            return Result(variant: try HLSVariantParser.select1080p(from: variants), usedFallback: false)
        } catch let error as HLSVariantError {
            guard case .no1080pVariant = error, policy == .prefer1080pAllowFallback else { throw error }
            return Result(variant: try HLSVariantParser.selectBestAvailable(from: variants), usedFallback: true)
        }
    }

    #if canImport(AVFoundation)
    /// Creates an AVPlayerItem for the selected media playlist. Choosing a real 1080p variant
    /// is preferable to asking the player to upscale a 720p source.
    public static func makePlayerItem(for result: Result) -> AVPlayerItem {
        let item = AVPlayerItem(url: result.variant.url)
        item.preferredMaximumResolution = CGSize(width: result.variant.width, height: result.variant.height)
        item.preferredPeakBitRate = 0
        return item
    }
    #endif
}
