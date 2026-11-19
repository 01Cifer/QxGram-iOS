#!/usr/bin/env python3
"""Rewrite an upstream fake profile for a capability-free personal build."""

import argparse
import datetime
import plistlib


SUFFIXES = {
    "Telegram": "",
    "BroadcastUpload": ".BroadcastUpload",
    "Intents": ".SiriIntents",
    "NotificationContent": ".NotificationContent",
    "NotificationService": ".NotificationService",
    "Share": ".Share",
    "WatchApp": ".watchkitapp",
    "WatchExtension": ".watchkitapp.watchkitextension",
    "Widget": ".Widget",
}


def prepare_profile(profile, profile_name, bundle_id):
    if profile_name not in SUFFIXES:
        raise ValueError("Unexpected fake profile name")
    if not bundle_id or any(not part for part in bundle_id.split(".")):
        raise ValueError("Invalid bundle identifier")
    team_id = profile["TeamIdentifier"][0]
    suffix = SUFFIXES[profile_name]
    old_identifier = profile["Entitlements"]["application-identifier"]
    if not old_identifier.startswith(team_id + ".") or not old_identifier.endswith(suffix):
        raise ValueError("Unexpected fake profile identifier")
    profile["Name"] = "QxGram fake " + profile_name
    profile["AppIDName"] = "QxGram fake " + profile_name
    profile["TeamName"] = "QxGram Fake"
    profile["Entitlements"] = {
        "application-identifier": team_id + "." + bundle_id + suffix,
        "com.apple.developer.team-identifier": team_id,
        "get-task-allow": False,
        "keychain-access-groups": [team_id + ".*"],
    }
    profile["ExpirationDate"] = datetime.datetime(2029, 6, 1)
    profile["TimeToLive"] = 900
    return profile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("profile_plist")
    parser.add_argument("profile_name", choices=sorted(SUFFIXES))
    parser.add_argument("bundle_id")
    args = parser.parse_args()
    with open(args.profile_plist, "rb") as source:
        profile = prepare_profile(plistlib.load(source), args.profile_name, args.bundle_id)
    with open(args.profile_plist, "wb") as destination:
        plistlib.dump(profile, destination)


if __name__ == "__main__":
    main()
