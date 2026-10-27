import plistlib
import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

from tools.inject_dylib import (
    InjectionError,
    LOAD_PATH,
    build_injected_ipa,
    inject_load_command,
)

MACH_HEADER_SIZE = 32
SEGMENT_COMMAND_SIZE = 152
TEXT_FILE_OFFSET = 16384


def synthetic_macho() -> bytes:
    """Minimal 64-bit MH_EXECUTE with one section at file offset 16 KiB."""
    header = struct.pack(
        "<IiiIIIII",
        0xFEEDFACF,       # MH_MAGIC_64, little endian
        0x0100000C,       # CPU_TYPE_ARM64
        0,                # CPU_SUBTYPE
        2,                # MH_EXECUTE
        1,                # ncmds
        SEGMENT_COMMAND_SIZE,
        0,
        0,
    )
    segment = bytearray(SEGMENT_COMMAND_SIZE)
    struct.pack_into("<II", segment, 0, 0x19, SEGMENT_COMMAND_SIZE)  # LC_SEGMENT_64
    segment[8:14] = b"__TEXT"
    struct.pack_into(
        "<QQQQIIII",
        segment,
        24,
        0x100000000,
        0x20000,
        0,
        0x20000,
        7,
        5,
        1,  # nsects
        0,
    )
    section = 72
    segment[section:section + 6] = b"__text"
    segment[section + 16:section + 22] = b"__TEXT"
    struct.pack_into("<QQI", segment, section + 32, 0x100004000, 16, TEXT_FILE_OFFSET)
    binary = bytearray(TEXT_FILE_OFFSET + 16)
    binary[:MACH_HEADER_SIZE] = header
    binary[MACH_HEADER_SIZE:MACH_HEADER_SIZE + SEGMENT_COMMAND_SIZE] = segment
    return bytes(binary)


def load_commands(binary: bytes):
    _, _, _, _, ncmds, _, _, _ = struct.unpack_from("<IiiIIIII", binary, 0)
    cursor = MACH_HEADER_SIZE
    result = []
    for _ in range(ncmds):
        command, size = struct.unpack_from("<II", binary, cursor)
        result.append((command, cursor, size))
        cursor += size
    return result


class InjectDylibTests(unittest.TestCase):
    def test_adds_dylib_load_command_and_updates_header(self):
        original = synthetic_macho()
        patched = inject_load_command(original)
        _, _, _, _, ncmds, sizeofcmds, _, _ = struct.unpack_from("<IiiIIIII", patched, 0)
        self.assertEqual(ncmds, 2)
        self.assertEqual(sizeofcmds, SEGMENT_COMMAND_SIZE + ((24 + len(LOAD_PATH.encode()) + 1 + 7) // 8) * 8)
        command, offset, size = load_commands(patched)[1]
        self.assertEqual(command, 0xC)  # LC_LOAD_DYLIB
        name_offset = struct.unpack_from("<I", patched, offset + 8)[0]
        name_start = offset + name_offset
        name_end = patched.index(b"\0", name_start, offset + size)
        self.assertEqual(patched[name_start:name_end].decode(), LOAD_PATH)

    def test_injection_is_idempotent(self):
        once = inject_load_command(synthetic_macho())
        twice = inject_load_command(once)
        self.assertEqual(once, twice)
        self.assertEqual(len(load_commands(twice)), 2)

    def test_rejects_non_macho_input(self):
        with self.assertRaises(InjectionError):
            inject_load_command(b"not a Mach-O")

    def test_builds_ipa_without_duplicate_info_plist_and_can_enable_file_sharing(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            input_ipa = root / "input.ipa"
            dylib = root / "PinaTVLabInjected.dylib"
            output = root / "output.ipa"
            app_root = "Payload/PinaTV.app"
            plist_path = f"{app_root}/Info.plist"
            executable_path = f"{app_root}/PinaTV"
            info = {
                "CFBundleIdentifier": "com.kevin.pinatv",
                "CFBundleExecutable": "PinaTV",
                "CFBundleShortVersionString": "2.0.4",
            }
            with zipfile.ZipFile(input_ipa, "w", compression=zipfile.ZIP_DEFLATED) as archive:
                archive.writestr(plist_path, plistlib.dumps(info))
                archive.writestr(executable_path, synthetic_macho())
                archive.writestr(f"{app_root}/Assets.car", b"assets")
            dylib.write_bytes(b"stand-in dylib for archive unit test")

            build_injected_ipa(input_ipa, dylib, output, enable_file_sharing=True)

            with zipfile.ZipFile(output) as archive:
                names = archive.namelist()
                self.assertEqual(names.count(plist_path), 1)
                patched_info = plistlib.loads(archive.read(plist_path))
                self.assertTrue(patched_info["UIFileSharingEnabled"])
                self.assertTrue(patched_info["LSSupportsOpeningDocumentsInPlace"])
                self.assertEqual(
                    archive.read(f"{app_root}/Frameworks/PinaTVLabInjected.dylib"),
                    dylib.read_bytes(),
                )
                self.assertEqual(
                    len(load_commands(archive.read(executable_path))),
                    2,
                )


if __name__ == "__main__":
    unittest.main()
