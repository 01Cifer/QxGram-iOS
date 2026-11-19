#!/usr/bin/env python3
"""Fail closed if a personal-build IPA requests unsupported capabilities."""

import argparse
import plistlib
import struct
import zipfile


class VerificationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def inspect_macho(ipa, path, inspect_entitlements=False):
    info = ipa.getinfo(path)
    with ipa.open(info) as binary:
        header = binary.read(32)
        require(len(header) == 32, "truncated Mach-O header")
        magic, cpu, _, _, count, commands_size, _, _ = struct.unpack("<IiiIIIII", header)
        require(magic == 0xFEEDFACF and cpu == 0x0100000C, "binary is not thin arm64")
        require(commands_size <= 4 * 1024 * 1024, "invalid load command size")
        commands = binary.read(commands_size)
        require(len(commands) == commands_size, "truncated Mach-O commands")
        offset = 0
        platform = None
        signature = None
        for _ in range(count):
            require(offset + 8 <= len(commands), "invalid Mach-O command")
            command, size = struct.unpack_from("<II", commands, offset)
            require(size >= 8 and offset + size <= len(commands), "invalid Mach-O command size")
            if command == 0x32:
                require(size >= 24, "invalid LC_BUILD_VERSION")
                platform = struct.unpack_from("<I", commands, offset + 8)[0]
            elif command == 0x25:
                platform = 2
            elif command == 0x1D:
                require(size >= 16, "invalid LC_CODE_SIGNATURE")
                signature = struct.unpack_from("<II", commands, offset + 8)
            offset += size
        require(platform == 2, "binary is not built for an iOS device")
        if not inspect_entitlements:
            return None
        require(signature is not None, "main executable has no code signature")
        signature_offset, signature_size = signature
        require(signature_size >= 12 and signature_size <= 16 * 1024 * 1024, "invalid code signature size")
        require(signature_offset + signature_size <= info.file_size, "code signature is outside the binary")
        binary.seek(signature_offset)
        signature_data = binary.read(signature_size)
    require(len(signature_data) == signature_size, "truncated code signature")
    magic, length, count = struct.unpack_from(">III", signature_data, 0)
    require(magic == 0xFADE0CC0 and length <= len(signature_data), "invalid code signature superblob")
    require(12 + count * 8 <= length, "invalid code signature index")
    entitlements = None
    has_der_entitlements = False
    for index in range(count):
        slot, position = struct.unpack_from(">II", signature_data, 12 + index * 8)
        require(position + 8 <= length, "invalid code signature slot")
        blob_magic, blob_size = struct.unpack_from(">II", signature_data, position)
        require(blob_size >= 8 and position + blob_size <= length, "invalid code signature blob")
        if slot == 5:
            require(blob_magic == 0xFADE7171 and entitlements is None, "invalid entitlements slot")
            entitlements = plistlib.loads(signature_data[position + 8:position + blob_size])
        elif slot == 7:
            require(blob_magic == 0xFADE7172 and not has_der_entitlements, "invalid DER entitlements slot")
            has_der_entitlements = True
    require(not has_der_entitlements or entitlements is not None, "cannot inspect DER-only entitlements")
    if entitlements is None:
        entitlements = {}
    require(isinstance(entitlements, dict), "entitlements are not a dictionary")
    return entitlements


def inspect_ipa(ipa_file, bundle_id):
    with zipfile.ZipFile(ipa_file) as ipa:
        names = ipa.namelist()
        app_plists = [
            name for name in names
            if name.startswith("Payload/") and name.endswith(".app/Info.plist")
            and name.count("/") == 2
        ]
        require(len(app_plists) == 1, "IPA must have one main app")
        app_root = app_plists[0].rsplit("/", 1)[0] + "/"
        require(not any(".appex/" in name or name.endswith(".appex") for name in names), "app extensions are present")
        require(not any(name.startswith(app_root + "Watch/") or name.startswith(app_root + "AppClips/") for name in names), "watch app or App Clip is present")
        info = plistlib.loads(ipa.read(app_plists[0]))
        require(info.get("CFBundleIdentifier") == bundle_id, "unexpected bundle identifier")
        require(info.get("CFBundleDisplayName") == "QxGram", "unexpected app display name")
        require(info.get("CFBundleName") == "QxGram", "unexpected bundle name")
        require(info.get("QxGramPersonalBuild") is True, "personal build marker is missing")
        for key in ("CFBundleIcons", "CFBundleIcons~ipad"):
            icons = info.get(key)
            if key == "CFBundleIcons" or icons is not None:
                require(isinstance(icons, dict), "missing app icon metadata")
                require(icons.get("CFBundlePrimaryIcon", {}).get("CFBundleIconName") == "QxGram", "unexpected primary app icon")
                require(not icons.get("CFBundleAlternateIcons"), "alternate app icons are present")
        url_types = info.get("CFBundleURLTypes", [])
        require(isinstance(url_types, list) and all(isinstance(item, dict) for item in url_types), "invalid URL types")
        schemes = [scheme for item in url_types for scheme in item.get("CFBundleURLSchemes", [])]
        require(schemes == ["qxgram"], "unexpected registered URL schemes")
        localized_info = [
            name for name in names if name.startswith(app_root)
            and len(name[len(app_root):].split("/")) == 2
            and name[len(app_root):].split("/")[0].endswith(".lproj")
            and name.endswith("/InfoPlist.strings")
        ]
        require(localized_info, "localized system names are missing")
        for name in localized_info:
            localized = plistlib.loads(ipa.read(name))
            require(localized.get("CFBundleDisplayName") == "QxGram", "unexpected localized display name")
            require(localized.get("CFBundleName") == "QxGram", "unexpected localized bundle name")
        modes = info.get("UIBackgroundModes", [])
        require(isinstance(modes, list), "invalid background modes")
        require(set(modes) <= {"audio", "fetch", "location"}, "unsupported background modes are present")
        require("BGTaskSchedulerPermittedIdentifiers" not in info, "background task identifiers are present")
        executable = info.get("CFBundleExecutable")
        require(isinstance(executable, str) and executable, "main executable is missing")
        entitlements = inspect_macho(ipa, app_root + executable, inspect_entitlements=True)
        allowed = {
            "application-identifier",
            "com.apple.developer.team-identifier",
            "get-task-allow",
            "keychain-access-groups",
        }
        unexpected = set(entitlements) - allowed
        require(not unexpected, "unsupported entitlements: " + ", ".join(sorted(unexpected)))
        application_id = entitlements.get("application-identifier")
        if application_id is not None:
            require(isinstance(application_id, str) and application_id.endswith("." + bundle_id), "unexpected application identifier")
        groups = entitlements.get("keychain-access-groups", [])
        require(isinstance(groups, list), "invalid keychain access groups")
        for group in groups:
            require(isinstance(group, str) and group.endswith("." + bundle_id) and "*" not in group, "unexpected keychain access group")
            if application_id is not None:
                require(group == application_id, "keychain group differs from application identifier")
        framework_prefix = app_root + "Frameworks/"
        frameworks = []
        for name in names:
            if not name.startswith(framework_prefix):
                continue
            parts = name[len(framework_prefix):].split("/")
            if len(parts) == 2 and parts[0].endswith(".framework") and parts[1] == parts[0][:-len(".framework")]:
                frameworks.append(name)
        require(frameworks, "no embedded frameworks found")
        for framework in frameworks:
            require(not inspect_macho(ipa, framework, inspect_entitlements=True), "framework entitlements are present")
            framework_info = plistlib.loads(ipa.read(framework.rsplit("/", 1)[0] + "/Info.plist"))
            framework_id = framework_info.get("CFBundleIdentifier")
            require(isinstance(framework_id, str) and framework_id.startswith(bundle_id + "."), "unexpected framework bundle identifier")
        return {
            "bundle_id": bundle_id,
            "entitlement_keys": sorted(entitlements),
            "frameworks": len(frameworks),
            "minimum_ios": info.get("MinimumOSVersion"),
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ipa")
    parser.add_argument("--bundle-id", required=True)
    arguments = parser.parse_args()
    result = inspect_ipa(arguments.ipa, arguments.bundle_id)
    print("Personal IPA verified:", result)


if __name__ == "__main__":
    main()
