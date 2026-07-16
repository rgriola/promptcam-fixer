#!/usr/bin/env python3
"""Pick the newest available iPhone simulator from `simctl list devices --json`.

Reads the JSON produced by `xcrun simctl list devices available --json` and
prints the name of the newest available iPhone device. This avoids hard-coding
a device name (e.g. "iPhone 17") that may not exist on a given runner image.

Usage: pick_simulator.py <devices.json>
Prints the selected device name to stdout, or nothing if none is found.
"""
import json
import re
import sys


def version_key(runtime_identifier):
    """Extract a sortable iOS version tuple from a runtime identifier."""
    nums = re.findall(r"\d+", runtime_identifier)
    return tuple(int(n) for n in nums) if nums else (0,)


def device_key(name):
    """Sort iPhones by their trailing model numbers (e.g. 15 < 16 < 16 Pro)."""
    nums = re.findall(r"\d+", name)
    return tuple(int(n) for n in nums) if nums else (0,)


def main():
    if len(sys.argv) < 2:
        print("", end="")
        return 0
    with open(sys.argv[1], encoding="utf-8") as handle:
        devices = json.load(handle).get("devices", {})

    candidates = []
    for runtime, entries in devices.items():
        if "iOS" not in runtime:
            continue
        for device in entries:
            name = device.get("name", "")
            if device.get("isAvailable") and name.startswith("iPhone"):
                candidates.append((version_key(runtime), device_key(name), name))

    if not candidates:
        print("", end="")
        return 0

    candidates.sort()
    print(candidates[-1][2], end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
