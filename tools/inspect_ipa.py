#!/usr/bin/env python3
"""Read-only static inventory of an iOS IPA; no binary patching or extraction to disk."""
from __future__ import annotations
import argparse
import json
import plistlib
import re
import shutil
import subprocess
import zipfile
from pathlib import PurePosixPath

FEATURE_TOKENS = [
    "ResolutionSelectorPanel", "ResolutionSelectorSheet", "ResolutionOption",
    "Vip1080RequiredPromptModifier", "VIPService", "TradPlusAdService",
    "lockPlaybackResolution", "selectedResolution", "startResolution",
    "vip1080ResolutionTitle", "vip1080ResolutionMessage", "rewardAdTimePoints1080p",
    "vipBenefitNoAds", "vipBenefitHdQuality", "isUserAPurchaser", "is_user_a_purchaser",
]
ROUTES = [
    "/vlab/abtest/config", "/vlab/episode/detail", "/vlab/market/banner/list",
    "/vlab/show/detail", "/vlab/show/search", "/vlab/user/app/store/transaction",
    "/vlab/version/check",
]
LOCALIZED_KEYS = [
    "guide.resolution.message", "reward_ad.prompt.message", "vip1080ResolutionMessage",
    "vip1080ResolutionTitle", "vipBenefitHdQualityDesc", "vipBenefitNoAdsDesc",
]


def get_strings(blob: bytes) -> list[str]:
    return [s.decode("ascii", "ignore") for s in re.findall(rb"[\x20-\x7e]{4,}", blob)]


def inspect_ipa(path: str) -> dict:
    with zipfile.ZipFile(path) as zf:
        names = zf.namelist()
        app_plist_path = next((n for n in names if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", n)), None)
        if not app_plist_path:
            raise ValueError("The IPA does not contain Payload/*.app/Info.plist")
        app_root = app_plist_path.rsplit("/", 1)[0]
        info = plistlib.loads(zf.read(app_plist_path))
        executable_name = info.get("CFBundleExecutable", "")
        binary = zf.read(f"{app_root}/{executable_name}")
        strings = get_strings(binary)
        haystack = "\n".join(strings)
        resource_bundles = sorted({
            PurePosixPath(n).parts[2]
            for n in names
            if len(PurePosixPath(n).parts) > 2
            and PurePosixPath(n).parts[0] == "Payload"
            and PurePosixPath(n).parts[1].endswith(".app")
            and (PurePosixPath(n).parts[2].endswith(".bundle") or PurePosixPath(n).parts[2].endswith(".framework"))
        })
        feature_hits = [s for s in FEATURE_TOKENS if s in haystack]
        route_hits = [s for s in ROUTES if s in haystack]
        class_hits = sorted({s for s in strings if s.startswith("_TtC6PinaTV") and any(w in s.lower() for w in ("vip", "ad", "video", "config", "api", "resolution"))})
        localizations = {}
        for lang in ("en", "ar"):
            loc_path = f"{app_root}/{lang}.lproj/Localizable.strings"
            if loc_path not in names:
                continue
            try:
                dictionary = plistlib.loads(zf.read(loc_path))
                localizations[lang] = {k: dictionary[k] for k in LOCALIZED_KEYS if k in dictionary}
            except Exception as exc:
                localizations[lang] = {"parse_error": str(exc)}
        cryptid = None
        if shutil.which("llvm-objdump"):
            try:
                with __import__("tempfile").NamedTemporaryFile() as stream:
                    stream.write(binary)
                    stream.flush()
                    out = subprocess.run(
                        ["llvm-objdump", "--macho", "--private-headers", stream.name],
                        stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False,
                    ).stdout.decode("utf-8", "ignore")
                match = re.search(r"cryptid\s+(\d+)", out)
                if match:
                    cryptid = int(match.group(1))
            except Exception:
                pass
        return {
            "package": {
                "bundle_id": info.get("CFBundleIdentifier"),
                "version": info.get("CFBundleShortVersionString"),
                "build": info.get("CFBundleVersion"),
                "minimum_ios": info.get("MinimumOSVersion"),
                "executable": executable_name,
                "executable_size_bytes": len(binary),
                "mach_o_magic_hex": binary[:4].hex(),
                "cryptid_from_llvm_objdump": cryptid,
            },
            "resource_bundles": resource_bundles,
            "feature_markers_found": feature_hits,
            "related_swift_classes": class_hits,
            "api_routes_found": route_hits,
            "localization_strings": localizations,
            "limitations": [
                "Static string inspection does not reveal the full control-flow logic.",
                "The presence of an SDK or route does not prove it is active at runtime.",
                "This tool does not modify the IPA, test playback, or establish the availability of 1080p media.",
            ],
        }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa", help="Path to a local IPA file")
    parser.add_argument("--json", action="store_true", help="Print machine-readable JSON")
    args = parser.parse_args()
    result = inspect_ipa(args.ipa)
    if args.json:
        print(json.dumps(result, indent=2, ensure_ascii=False))
        return 0
    p = result["package"]
    print(f"Bundle: {p['bundle_id']} | version {p['version']} ({p['build']})")
    print(f"Executable: {p['executable']} ({p['executable_size_bytes']:,} bytes), Mach-O magic {p['mach_o_magic_hex']}")
    print(f"Minimum iOS: {p['minimum_ios']}; cryptid: {p['cryptid_from_llvm_objdump']}")
    for title, key in (("Feature markers", "feature_markers_found"), ("Swift classes", "related_swift_classes"), ("API routes", "api_routes_found"), ("Bundled resources", "resource_bundles")):
        print(f"\n{title}:")
        for item in result[key]:
            print(f"  - {item}")
    print("\nLocalized strings:")
    print(json.dumps(result["localization_strings"], indent=2, ensure_ascii=False))
    print("\nLimitations:")
    for item in result["limitations"]:
        print(f"  - {item}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
