# PinaTV 2.0.4: static inspection findings

## Package identity
- Bundle ID: `com.kevin.pinatv`
- Version/build: `2.0.4 (1)`
- Minimum iOS: `15.0`
- Main executable: `Payload/PinaTV.app/PinaTV`
- Executable size: 28,819,152 bytes
- Format: ARM64 Mach-O; strings identify Swift runtime/class names.
- Mach-O encryption field from the supplied package: `cryptid = 0`. This reports the main executable's encryption flag only; it is not a source recovery or signing guarantee.

## Quality and membership indicators
The executable contains:
- `ResolutionSelectorPanel`, `ResolutionSelectorSheet`, `ResolutionOption`
- `Vip1080RequiredPromptModifier`, `VIPService`, `VipStoreKitManager`
- `lockPlaybackResolution`, `selectedResolution`, `startResolution`
- `vip1080ResolutionTitle`, `vip1080ResolutionMessage`
- `rewardAdTimePoints1080p`
- `vipBenefitNoAds`, `vipBenefitHdQuality`
- `isUserAPurchaser`, `is_user_a_purchaser`

The English localization says: “Change resolution here. VIP unlocks 1080p.” It describes 1080p as a VIP-exclusive feature, and defines no-ads benefits as no splash or in-video ads. The Arabic localization communicates the same restrictions.

This shows quality selection and membership checks are implemented in the application. The precise branch logic and the role of remote configuration are not proven by string matches alone.

## Ad-related components
Bundled resources include:
- `TradPlusAds.bundle`, `TradPlusADX.bundle`
- `GoogleMobileAdsResources.bundle`
- `PAGAdSDK.bundle` (Pangle/TikTok-related)
- `UnityAdsResources.bundle`, `VungleAds.bundle`
- `AdsGlobalSDK.bundle`, `TikTokBusinessSDK.bundle`
- `UserMessagingPlatformResources.bundle`

Swift class strings include `TradPlusAdService`, `BannerAdLoader`, `BannerAdManager`, and `SplashAdHandler`. SDK/resource presence is static evidence only; it does not establish which ad placement ran during a specific session.

## API/config indicators
The main executable contains `https://api.pinatv.xyz` and routes:
- `/vlab/abtest/config`
- `/vlab/episode/detail`
- `/vlab/market/banner/list`
- `/vlab/show/detail`, `/vlab/show/search`
- `/vlab/user/app/store/transaction`
- `/vlab/version/check`

The application also has `APIService`, `ConfigService`, and `VideoService` class names. The IPA alone cannot establish whether your private media server handles app configuration or supplies only media URLs.

## Practical 1080p requirement
A client can choose 1080p only if the master playlist advertises a 1920×1080 variant (or a compatible wider variant with height 1080) and the media URL is reachable. A quality label or UI change cannot create a 1080p stream from 720p source material.

The repository includes a tested HLS parser/selector for integration into a media client you control. It has six local unit tests and reports clearly when a 1080p variant does not exist.

## Not yet completed
- The original PinaTV Swift/Xcode project is not present in this repository.
- No byte-level modification of the PinaTV executable has been made.
- No modified IPA has been produced, re-signed, or tested on device.
- Runtime playback and server availability were not tested; no media URL was supplied.

The static inventory tool writes `docs/ipa-static-report.json`. It does not patch binaries or bypass app controls.
