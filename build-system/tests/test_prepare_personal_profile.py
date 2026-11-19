import copy
import pathlib
import plistlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from prepare_personal_profile import SUFFIXES, prepare_profile


class PreparePersonalProfileTests(unittest.TestCase):
    def test_all_profiles_use_new_id_and_minimal_entitlements(self):
        for name, suffix in SUFFIXES.items():
            with self.subTest(name=name):
                profile = {
                    "TeamIdentifier": ["TEAM"],
                    "Name": "old profile",
                    "AppIDName": "old app",
                    "Entitlements": {
                        "application-identifier": "TEAM.org.example.old" + suffix,
                        "aps-environment": "production",
                        "com.apple.security.application-groups": ["group.org.example.old"],
                    },
                }
                result = prepare_profile(copy.deepcopy(profile), name, "org.qxgram.app")
                entitlements = result["Entitlements"]
                self.assertEqual(entitlements["application-identifier"], "TEAM.org.qxgram.app" + suffix)
                self.assertEqual(set(entitlements), {
                    "application-identifier", "com.apple.developer.team-identifier",
                    "get-task-allow", "keychain-access-groups",
                })
                self.assertNotIn(b"org.example.old", plistlib.dumps(result))

    def test_rejects_unknown_profile(self):
        with self.assertRaises(ValueError):
            prepare_profile({}, "unexpected", "org.qxgram.app")

    def test_rejects_invalid_team_prefix(self):
        profile = {"TeamIdentifier": ["TEAM"], "Entitlements": {"application-identifier": "OTHER.org.example.old"}}
        with self.assertRaises(ValueError):
            prepare_profile(profile, "Telegram", "org.qxgram.app")


if __name__ == "__main__":
    unittest.main()
