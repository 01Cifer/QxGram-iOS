import json
import pathlib
import plistlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]


class PersonalConfigurationTests(unittest.TestCase):
    def test_all_build_configurations_use_qxgram_identity(self):
        for name in [
            "appcenter-configuration.json", "appstore-configuration.json",
            "qxgram-configuration.json", "template_minimal_development_configuration.json",
        ]:
            with self.subTest(name=name):
                config = json.loads((ROOT / "build-system" / name).read_text(encoding="utf-8"))
                self.assertEqual(config["bundle_id"], "org.qxgram.app")
                self.assertEqual(config["app_specific_url_scheme"], "qxgram")

    def test_static_plists_do_not_register_telegram_schemes(self):
        for name in ["Info.plist", "InfoBazel.plist"]:
            with self.subTest(name=name):
                info = plistlib.loads((ROOT / "Telegram/Telegram-iOS" / name).read_bytes())
                schemes = [
                    scheme for item in info.get("CFBundleURLTypes", [])
                    for scheme in item.get("CFBundleURLSchemes", [])
                ]
                self.assertEqual(schemes, ["qxgram"])
                imported = info.get("UTImportedTypeDeclarations", [])
                self.assertFalse(any(
                    item.get("UTTypeIdentifier", "").startswith("org.telegram.Telegram-iOS")
                    for item in imported
                ))


if __name__ == "__main__":
    unittest.main()
