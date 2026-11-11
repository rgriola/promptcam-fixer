#!/usr/bin/env python3
"""Select an available iPhone simulator for a specific iOS runtime."""

import argparse
import json
import re
import sys
import uuid
from pathlib import Path


def device_key(name):
    nums = re.findall(r"\d+", name)
    return tuple(int(n) for n in nums), name


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("devices_json", type=Path)
    parser.add_argument("--runtime", required=True, help="iOS runtime version, such as 26.2")
    args = parser.parse_args()

    if not re.fullmatch(r"\d+(?:\.\d+)*", args.runtime):
        parser.error("--runtime must be an iOS version, such as 26.2")

    try:
        with args.devices_json.open(encoding="utf-8") as handle:
            data = json.load(handle)
    except (OSError, json.JSONDecodeError) as error:
        print(f"Unable to read simulator devices: {error}", file=sys.stderr)
        return 1

    devices = data.get("devices") if isinstance(data, dict) else None
    if not isinstance(devices, dict):
        print("Simulator JSON does not contain a devices object", file=sys.stderr)
        return 1

    runtime = f"com.apple.CoreSimulator.SimRuntime.iOS-{args.runtime.replace('.', '-')}"
    entries = devices.get(runtime, [])
    if not isinstance(entries, list):
        print(f"Invalid simulator list for iOS {args.runtime}", file=sys.stderr)
        return 1

    candidates = []
    for device in entries:
        if not isinstance(device, dict) or device.get("isAvailable") is not True:
            continue
        name, identifier = device.get("name"), device.get("udid")
        if not isinstance(name, str) or not name.startswith("iPhone") or not isinstance(identifier, str):
            continue
        try:
            uuid.UUID(identifier)
        except ValueError:
            continue
        candidates.append((device_key(name), identifier))

    if not candidates:
        print(f"No available iPhone simulator for iOS {args.runtime}", file=sys.stderr)
        return 1

    (_, name), identifier = max(candidates)
    print(f"Selected {name} (iOS {args.runtime}, {identifier})", file=sys.stderr)
    print(identifier)
    return 0


if __name__ == "__main__":
    sys.exit(main())
