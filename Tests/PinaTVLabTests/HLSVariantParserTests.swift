import XCTest
@testable import PinaTVLab

final class HLSVariantParserTests: XCTestCase {
    private let base = URL(string: "https://media.example.test/catalog/master.m3u8")!

    func testSelects1080pAndUsesHighestBandwidthAtThatResolution() throws {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=1200000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2"
        720/index.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1920x1080
        1080/high.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
        1080/max.m3u8
        """
        let variants = try HLSVariantParser.parse(masterPlaylist: manifest, masterURL: base)
        let selected = try HLSVariantParser.select1080p(from: variants)
        XCTAssertEqual(selected.url.absoluteString, "https://media.example.test/catalog/1080/max.m3u8")
        XCTAssertEqual(selected.height, 1080)
        XCTAssertEqual(selected.bandwidth, 5_000_000)
    }

    func testResolvesAbsoluteAndRelativeVariantURLs() throws {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080
        https://cdn.example.test/master/1080.m3u8
        #EXT-X-STREAM-INF:BANDWIDTH=1000000,RESOLUTION=1280x720
        ../720/index.m3u8
        """
        let variants = try HLSVariantParser.parse(masterPlaylist: manifest, masterURL: base)
        XCTAssertEqual(variants[0].url.absoluteString, "https://cdn.example.test/master/1080.m3u8")
        XCTAssertEqual(variants[1].url.absoluteString, "https://media.example.test/720/index.m3u8")
    }

    func testReportsAvailableHeightsIf1080pIsMissing() throws {
        let variants = [HLSVariant(url: base, width: 1280, height: 720, bandwidth: 1_000_000)]
        XCTAssertThrowsError(try HLSVariantParser.select1080p(from: variants)) { error in
            XCTAssertEqual(error as? HLSVariantError, .no1080pVariant(availableHeights: [720]))
        }
    }

    func testBestAvailableFallbackPrefersHeightThenBandwidth() throws {
        let variants = [
            HLSVariant(url: base, width: 1920, height: 1080, bandwidth: 4_000_000),
            HLSVariant(url: base, width: 1280, height: 720, bandwidth: 2_000_000),
            HLSVariant(url: base, width: 854, height: 480, bandwidth: 900_000)
        ]
        XCTAssertEqual(try HLSVariantParser.selectBestAvailable(from: variants).height, 1080)
    }

    func testRejectsNonMasterPlaylist() {
        XCTAssertThrowsError(try HLSVariantParser.parse(masterPlaylist: "#EXTM3U\n#EXTINF:10,\nseg.ts", masterURL: base))
    }

    func testHandlesQuotedCodecCommas() throws {
        let manifest = """
        #EXTM3U
        #EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2"
        video.m3u8
        """
        let variants = try HLSVariantParser.parse(masterPlaylist: manifest, masterURL: base)
        XCTAssertEqual(variants.count, 1)
        XCTAssertEqual(try HLSVariantParser.select1080p(from: variants).height, 1080)
    }
}
