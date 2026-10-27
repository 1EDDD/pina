# PinaTV Lab

A small workspace for inspecting the supplied PinaTV IPA and validating HLS stream quality for media sources you control.

## Current findings from PinaTV 2.0.4

- Bundle identifier reported by the IPA: `com.kevin.pinatv`
- Native arm64 Mach-O executable; the app is Swift-based.
- The binary contains feature identifiers including `lockPlaybackResolution`, `vip1080ResolutionTitle`, and `rewardAdTimePoints1080p`.
- Ad-related code/resources include TradPlus and other advertising SDK components.
- The app references `https://api.pinatv.xyz`. The supplied IPA alone does not establish how a separate private media server is configured.

These identifiers are evidence of relevant code paths, not proof of exactly which branch or server response enforces each feature.

## Contents

- `Sources/HLS1080Selector.swift`: reusable Swift helper that reads an HLS master playlist and selects an explicitly listed 1080p variant. It works only for streams the operator is authorized to access.
- `tools/inspect-ipa.sh`: local, read-only IPA inventory helper.

## Use the HLS selector

The stream must be an HLS master playlist containing a variant with `RESOLUTION=1920x1080` (or another 1080p-wide variant with height 1080). If no 1080p variant exists, the helper reports that rather than pretending the stream is HD.

The helper does not modify PinaTV, bypass app entitlements, alter VIP state, or suppress another developer's ad/purchase controls. An IPA is a compiled app bundle, not its source project; reliable app-level changes need the app's source/build configuration or authorization to change the relevant service.
