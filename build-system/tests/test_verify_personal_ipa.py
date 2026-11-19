import io
import pathlib
import plistlib
import struct
import sys
import unittest
import zipfile

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from verify_personal_ipa import VerificationError, inspect_ipa


BUNDLE_ID = "org.qxgram.app"
ROOT = "Payload/Telegram.app/"


def macho(entitlements, platform=2):
    plist = plistlib.dumps(entitlements)
    entitlement_blob = struct.pack(">II", 0xFADE7171, len(plist) + 8) + plist
    signature = struct.pack(">III", 0xFADE0CC0, 20 + len(entitlement_blob), 1)
    signature += struct.pack(">II", 5, 20) + entitlement_blob
    build_version = struct.pack("<IIIIII", 0x32, 24, platform, 0, 0, 0)
    signature_command = struct.pack("<IIII", 0x1D, 16, 72, len(signature))
    header = struct.pack("<IiiIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, 2, 40, 0, 0)
    return header + build_version + signature_command + signature


def make_ipa(entitlements=None, *, marker=True, background=None, extension=False, platform=2, task_ids=False, framework_entitlements=None, schemes=None, framework_id=None):
    data = io.BytesIO()
    info = {
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleDisplayName": "QxGram",
        "CFBundleName": "QxGram",
        "CFBundleExecutable": "Telegram",
        "CFBundleURLTypes": [{"CFBundleURLSchemes": ["qxgram"] if schemes is None else schemes}],
        "QxGramPersonalBuild": marker,
        "UIBackgroundModes": ["audio"] if background is None else background,
    }
    if task_ids:
        info["BGTaskSchedulerPermittedIdentifiers"] = [BUNDLE_ID + ".cleanup"]
    with zipfile.ZipFile(data, "w") as ipa:
        ipa.writestr(ROOT + "Info.plist", plistlib.dumps(info))
        ipa.writestr(ROOT + "Telegram", macho(entitlements or {}, platform=platform))
        ipa.writestr(ROOT + "Frameworks/Test.framework/Test", macho(framework_entitlements or {}))
        ipa.writestr(ROOT + "Frameworks/Test.framework/Info.plist", plistlib.dumps({
            "CFBundleIdentifier": framework_id or BUNDLE_ID + ".Test",
        }))
        if extension:
            ipa.writestr(ROOT + "PlugIns/Test.appex/Info.plist", b"test")
    data.seek(0)
    return data


class VerifyPersonalIpaTests(unittest.TestCase):
    def test_accepts_minimal_personal_ipa(self):
        result = inspect_ipa(make_ipa(), BUNDLE_ID)
        self.assertEqual(result["entitlement_keys"], [])
        self.assertEqual(result["frameworks"], 1)

    def test_rejects_extensions(self):
        with self.assertRaisesRegex(VerificationError, "extensions"):
            inspect_ipa(make_ipa(extension=True), BUNDLE_ID)

    def test_rejects_missing_personal_marker(self):
        with self.assertRaisesRegex(VerificationError, "marker"):
            inspect_ipa(make_ipa(marker=False), BUNDLE_ID)

    def test_rejects_telegram_url_schemes(self):
        for scheme in ["tg", "tonsite", "telegram", "ton", "tc"]:
            with self.subTest(scheme=scheme), self.assertRaisesRegex(VerificationError, "URL schemes"):
                inspect_ipa(make_ipa(schemes=["qxgram", scheme]), BUNDLE_ID)

    def test_rejects_old_framework_identifier(self):
        with self.assertRaisesRegex(VerificationError, "framework bundle identifier"):
            inspect_ipa(make_ipa(framework_id="org.example.old.Test"), BUNDLE_ID)

    def test_rejects_push_background_mode(self):
        with self.assertRaisesRegex(VerificationError, "background modes"):
            inspect_ipa(make_ipa(background=["remote-notification"]), BUNDLE_ID)

    def test_rejects_background_task_identifiers(self):
        with self.assertRaisesRegex(VerificationError, "task identifiers"):
            inspect_ipa(make_ipa(task_ids=True), BUNDLE_ID)

    def test_rejects_privileged_entitlement(self):
        with self.assertRaisesRegex(VerificationError, "unsupported entitlements"):
            inspect_ipa(make_ipa({"aps-environment": "production"}), BUNDLE_ID)

    def test_rejects_framework_entitlements(self):
        with self.assertRaisesRegex(VerificationError, "framework entitlements"):
            inspect_ipa(make_ipa(framework_entitlements={"aps-environment": "production"}), BUNDLE_ID)

    def test_rejects_wildcard_keychain_group(self):
        with self.assertRaisesRegex(VerificationError, "keychain access group"):
            inspect_ipa(make_ipa({"keychain-access-groups": ["TEAM.*"]}), BUNDLE_ID)

    def test_rejects_simulator_binary(self):
        with self.assertRaisesRegex(VerificationError, "iOS device"):
            inspect_ipa(make_ipa(platform=7), BUNDLE_ID)


if __name__ == "__main__":
    unittest.main()
