#!/usr/bin/env python3
"""Inject a diagnostic dylib into a decrypted iOS IPA without re-signing it.

The output is an unsigned/invalidly signed package until it is re-signed by a
legitimate sideloading tool. This utility does not patch VIP, purchase, or ad logic.
"""
from __future__ import annotations

import argparse
import io
import plistlib
import struct
import sys
import zipfile
from pathlib import Path
from typing import Optional

MACH_HEADER_64_SIZE = 32
LC_LOAD_DYLIB = 0xC
LC_SEGMENT_64 = 0x19
DYLIB_LOAD_COMMANDS = {0xC, 0x18, 0x1F, 0x20, 0x23, 0x80000018, 0x8000001F}
LOAD_PATH = "@executable_path/Frameworks/PinaTVLabInjected.dylib"
TARGET_BUNDLE_ID = "com.kevin.pinatv"


class InjectionError(RuntimeError):
    pass


def _align(value: int, alignment: int) -> int:
    return (value + alignment - 1) & ~(alignment - 1)


def _section_data_start(binary: bytes, ncmds: int) -> Optional[int]:
    """Return the first non-empty on-disk section offset after Mach-O headers."""
    offset = MACH_HEADER_64_SIZE
    section_offsets: list[int] = []
    for _ in range(ncmds):
        if offset + 8 > len(binary):
            raise InjectionError("Truncated Mach-O load command.")
        cmd, cmdsize = struct.unpack_from("<II", binary, offset)
        if cmdsize < 8 or offset + cmdsize > len(binary):
            raise InjectionError("Invalid Mach-O load-command size.")
        if cmd == LC_SEGMENT_64:
            if cmdsize < 72:
                raise InjectionError("Invalid LC_SEGMENT_64 command.")
            nsects = struct.unpack_from("<I", binary, offset + 64)[0]
            section_table_start = offset + 72
            if section_table_start + nsects * 80 > offset + cmdsize:
                raise InjectionError("Section table exceeds its segment command.")
            for i in range(nsects):
                sect = section_table_start + i * 80
                size = struct.unpack_from("<Q", binary, sect + 40)[0]
                file_offset = struct.unpack_from("<I", binary, sect + 48)[0]
                if size and file_offset:
                    section_offsets.append(file_offset)
        offset += cmdsize
    return min(section_offsets) if section_offsets else None


def inject_load_command(binary: bytes, library_path: str = LOAD_PATH) -> bytes:
    """Append LC_LOAD_DYLIB to a thin 64-bit little-endian Mach-O if there is room."""
    if len(binary) < MACH_HEADER_64_SIZE or binary[:4] != b"\xcf\xfa\xed\xfe":
        raise InjectionError("Expected a thin little-endian 64-bit ARM Mach-O executable.")

    magic, cputype, cpusubtype, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack_from(
        "<IiiIIIII", binary, 0
    )
    if filetype != 2:  # MH_EXECUTE
        raise InjectionError(f"Expected MH_EXECUTE file type; got {filetype}.")

    command_end = MACH_HEADER_64_SIZE + sizeofcmds
    if command_end > len(binary):
        raise InjectionError("Mach-O load-command table exceeds file size.")

    offset = MACH_HEADER_64_SIZE
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from("<II", binary, offset)
        if cmdsize < 8 or offset + cmdsize > command_end:
            raise InjectionError("Invalid Mach-O load-command table.")
        if cmd in DYLIB_LOAD_COMMANDS and cmdsize >= 24:
            name_offset = struct.unpack_from("<I", binary, offset + 8)[0]
            if 0 <= name_offset < cmdsize:
                end = binary.find(b"\0", offset + name_offset, offset + cmdsize)
                if end != -1:
                    existing = binary[offset + name_offset : end].decode("utf-8", "replace")
                    if existing == library_path:
                        return binary
        offset += cmdsize

    path_bytes = library_path.encode("utf-8") + b"\0"
    cmdsize = _align(24 + len(path_bytes), 8)
    dylib_command = struct.pack("<IIIIII", LC_LOAD_DYLIB, cmdsize, 24, 0, 0, 0)
    dylib_command += path_bytes + b"\0" * (cmdsize - 24 - len(path_bytes))

    first_section = _section_data_start(binary, ncmds)
    new_command_end = command_end + cmdsize
    if first_section is not None and new_command_end > first_section:
        raise InjectionError(
            f"Not enough free header padding to add LC_LOAD_DYLIB: "
            f"command end {new_command_end}, first section {first_section}."
        )

    updated = bytearray(binary)
    updated[command_end : command_end + cmdsize] = dylib_command
    struct.pack_into("<I", updated, 16, ncmds + 1)
    struct.pack_into("<I", updated, 20, sizeofcmds + cmdsize)
    return bytes(updated)


def _read_ipa(ipa_path: Path) -> tuple[bytes, str, str, dict]:
    try:
        with zipfile.ZipFile(ipa_path, "r") as archive:
            infos = archive.infolist()
            app_candidates = [
                name for name in archive.namelist()
                if name.startswith("Payload/") and name.endswith(".app/Info.plist")
            ]
            if not app_candidates:
                raise InjectionError("No Payload/*.app/Info.plist found in this IPA.")
            matching = []
            for plist_path in app_candidates:
                info = plistlib.loads(archive.read(plist_path))
                if info.get("CFBundleIdentifier") == TARGET_BUNDLE_ID:
                    matching.append((plist_path, info))
            if len(matching) != 1:
                raise InjectionError(
                    f"Expected one app with bundle ID {TARGET_BUNDLE_ID}; found {len(matching)}."
                )
            plist_path, info = matching[0]
            app_root = plist_path.rsplit("/", 1)[0]
            executable = info.get("CFBundleExecutable")
            if not executable:
                raise InjectionError("CFBundleExecutable is missing from Info.plist.")
            executable_path = f"{app_root}/{executable}"
            if executable_path not in archive.namelist():
                raise InjectionError(f"Executable not found: {executable_path}")
            return archive.read(executable_path), plist_path, executable_path, info
    except zipfile.BadZipFile as exc:
        raise InjectionError(f"Input is not a valid ZIP/IPA file: {exc}") from exc


def build_injected_ipa(
    input_ipa: Path, dylib_path: Path, output_ipa: Path, enable_file_sharing: bool
) -> None:
    if not input_ipa.is_file():
        raise InjectionError(f"Input IPA does not exist: {input_ipa}")
    if not dylib_path.is_file() or dylib_path.stat().st_size == 0:
        raise InjectionError(f"Dylib does not exist or is empty: {dylib_path}")
    if input_ipa.resolve() == output_ipa.resolve():
        raise InjectionError("Output path must differ from input path.")

    executable, plist_path, executable_path, info = _read_ipa(input_ipa)
    patched_executable = inject_load_command(executable)
    app_root = plist_path.rsplit("/", 1)[0]
    framework_dir = f"{app_root}/Frameworks"
    dylib_in_ipa_path = f"{framework_dir}/PinaTVLabInjected.dylib"

    if enable_file_sharing:
        info["UIFileSharingEnabled"] = True
        info["LSSupportsOpeningDocumentsInPlace"] = True
    output_ipa.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(input_ipa, "r") as source, zipfile.ZipFile(
        output_ipa, "w", compression=zipfile.ZIP_DEFLATED
    ) as target:
        replaced = {executable_path, dylib_in_ipa_path}
        if enable_file_sharing:
            replaced.add(plist_path)
        for item in source.infolist():
            if item.filename in replaced:
                continue
            target.writestr(item, source.read(item.filename))
        target.writestr(executable_path, patched_executable, compress_type=zipfile.ZIP_STORED)
        plist_format = plistlib.FMT_BINARY if source.read(plist_path).startswith(b"bplist") else plistlib.FMT_XML
        target.writestr(
            plist_path,
            plistlib.dumps(info, fmt=plist_format, sort_keys=False),
            compress_type=zipfile.ZIP_DEFLATED,
        )
        target.writestr(
            dylib_in_ipa_path,
            dylib_path.read_bytes(),
            compress_type=zipfile.ZIP_STORED,
        )

    print(f"Created: {output_ipa}")
    print(f"Injected load path: {LOAD_PATH}")
    print(f"Embedded dylib: {dylib_in_ipa_path}")
    print("Status: package must be re-signed by your sideloading tool before installation.")
    if enable_file_sharing:
        print("File sharing enabled so Documents/PinaTVLab.log can be retrieved in Files.")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("input_ipa", type=Path)
    parser.add_argument("dylib", type=Path)
    parser.add_argument("output_ipa", type=Path)
    parser.add_argument(
        "--enable-file-sharing",
        action="store_true",
        help="Expose the app's Documents directory in Files to retrieve the diagnostic log.",
    )
    args = parser.parse_args()
    try:
        build_injected_ipa(args.input_ipa, args.dylib, args.output_ipa, args.enable_file_sharing)
    except (InjectionError, OSError, plistlib.InvalidFileException, zipfile.BadZipFile) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
