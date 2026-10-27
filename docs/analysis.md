# PinaTV 2.0.4: static inspection findings

## Package identity
- Bundle ID: `com.kevin.pinatv`
- App version: `2.0.4`, build `1`
- Main executable: `Payload/PinaTV.app/PinaTV`
- Format: native ARM64 Mach-O; strings indicate a Swift app.

## Quality and membership indicators
The executable and localization resources contain identifiers including:
- `lockPlaybackResolution`
- `selectedResolution`
- `startResolution`
- `vip1080ResolutionTitle`
- `vip1080ResolutionMessage`
- `rewardAdTimePoints1080p`
- `VIPService`
- `Vip1080RequiredPromptModifier`

The bundled Arabic/English localization labels describe 1080p as VIP-exclusive and mention rewarded-ad behavior. These strings establish that the app includes quality/membership flows; they do not identify the exact runtime branch by themselves.

## Advertising indicators
The app bundle includes `TradPlusAdService`, splash-ad resources, and several ad SDKs/resources, including Google Mobile Ads, TikTok/Pangle, Unity Ads, Vungle, and IronSource-related components. Static presence does not prove every network is active at runtime.

## API/config indicators
The executable includes `https://api.pinatv.xyz` and routes such as:
- `/vlab/abtest/config`
- `/vlab/episode/detail`
- `/vlab/show/detail`
- `/vlab/market/banner/list`

The IPA alone does not reveal whether a separate media server controls these API responses or membership state.

## What remains unverified
- Whether any particular stream has a 1920x1080 HLS rendition.
- Whether the private server is used only for media URLs or also controls app configuration.
- Actual behavior on-device; this is static inspection only.

## Practical implication
A 1080p auto-select feature can only pick a 1080p source that the HLS master manifest actually advertises. `Sources/HLS1080Selector.swift` demonstrates that for a source app or player under the operator's control. It does not change the supplied PinaTV IPA, alter its VIP state, or suppress its ad SDK calls.
