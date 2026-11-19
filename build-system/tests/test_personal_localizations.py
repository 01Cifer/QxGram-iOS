import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
from rebrand_info_plist import rebrand


class PersonalSystemLocalizationTests(unittest.TestCase):
    def test_display_name_and_permission_descriptions(self):
        source = (
            '"CFBundleDisplayName" = "텔레그램";\n'
            '"NSLocationWhenInUseUsageDescription" = "Telegram and 텔레그램";\n'
            '"NSContactsUsageDescription" = "в облаке Telegram";\n'
        )
        result = rebrand(source)
        self.assertEqual(result.count('"CFBundleDisplayName"'), 1)
        self.assertIn('"CFBundleDisplayName" = "QxGram";', result)
        self.assertIn('"CFBundleName" = "QxGram";', result)
        self.assertIn('"NSLocationWhenInUseUsageDescription" = "QxGram and QxGram";', result)
        self.assertIn("в облаке Telegram", result)


if __name__ == "__main__":
    unittest.main()
