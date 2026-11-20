import json
import pathlib
import struct
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[2]
ICON_SET = ROOT / "Telegram/Telegram-iOS/QxGramAppIcons.xcassets/QxGram.appiconset"


class PersonalIconTests(unittest.TestCase):
    def test_all_catalog_icons_are_square_and_opaque(self):
        contents = json.loads((ICON_SET / "Contents.json").read_text(encoding="utf-8"))
        self.assertEqual(len(contents["images"]), 17)
        self.assertFalse((ICON_SET / "ipad-76@1x.png").exists())
        self.assertFalse(any(
            item["idiom"] == "ipad" and item["size"] == "76x76" and item["scale"] == "1x"
            for item in contents["images"]
        ))
        for item in contents["images"]:
            with self.subTest(filename=item["filename"]):
                pixels = float(item["size"].split("x")[0]) * int(item["scale"][0])
                data = (ICON_SET / item["filename"]).read_bytes()
                self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
                self.assertEqual(struct.unpack_from(">II", data, 16), (pixels, pixels))
                self.assertEqual(data[25], 2)  # PNG RGB, no transparency


if __name__ == "__main__":
    unittest.main()
