#!/usr/bin/env python3
"""Rebrand localized app names in system permission descriptions."""

import argparse
import pathlib
import re


KEY_PATTERN = re.compile(r'^\s*"([^"]+)"\s*=')
APP_NAMES = ("Telegram", "تيليجرام", "تلگرام", "텔레그램")
SERVICE_CLOUD = "облаке Telegram"
SERVICE_PLACEHOLDER = "__QXGRAM_TELEGRAM_CLOUD__"


def rebrand(text):
    if SERVICE_PLACEHOLDER in text:
        raise ValueError("Reserved placeholder found in localized text")
    output = ['"CFBundleDisplayName" = "QxGram";\n', '"CFBundleName" = "QxGram";\n']
    for line in text.splitlines(keepends=True):
        match = KEY_PATTERN.match(line)
        key = match.group(1) if match else None
        if key in ("CFBundleDisplayName", "CFBundleName"):
            continue
        if key and key.startswith("NS") and key.endswith("UsageDescription"):
            # This refers to the service, not the name of this application.
            line = line.replace(SERVICE_CLOUD, SERVICE_PLACEHOLDER)
            for name in APP_NAMES:
                line = line.replace(name, "QxGram")
            line = line.replace(SERVICE_PLACEHOLDER, SERVICE_CLOUD)
        output.append(line)
    return "".join(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source")
    parser.add_argument("destination")
    args = parser.parse_args()
    source = pathlib.Path(args.source).read_text(encoding="utf-8")
    pathlib.Path(args.destination).write_text(rebrand(source), encoding="utf-8")


if __name__ == "__main__":
    main()
