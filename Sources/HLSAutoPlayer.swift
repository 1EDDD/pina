#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// A minimal player wrapper for HLS sources controlled by the app operator.
/// It prefers a genuine 1080p rendition and starts playback once selection succeeds.
@MainActor
public final class HLSAutoPlayer {
    public let player = AVPlayer()
    public private(set) var selectedResult: HLS1080Selector.Result?

    public init() {}

    /// Starts the best advertised 1080p variant, falling back to the best advertised variant
    /// if the source has no 1080p entry. This never fabricates detail through upscaling.
    public func playEpisode(
        masterPlaylistURL: URL,
        session: URLSession = .shared
    ) async throws {
        let result = try await HLS1080Selector.select(
            from: masterPlaylistURL,
            policy: .prefer1080pAllowFallback,
            session: session
        )
        let item = HLS1080Selector.makePlayerItem(for: result)
        player.replaceCurrentItem(with: item)
        selectedResult = result
        player.play()
    }

    public func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        selectedResult = nil
    }

    public var selectedResolutionLabel: String? {
        guard let result = selectedResult else { return nil }
        let base = "\(result.variant.width) × \(result.variant.height)"
        return result.usedFallback ? "\(base) (1080p unavailable)" : base
    }
}
#endif
