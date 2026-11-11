import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("pick_simulator.py")
RUNTIME_26_2 = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
RUNTIME_26_4 = "com.apple.CoreSimulator.SimRuntime.iOS-26-4"
PHONE_16 = "11111111-1111-4111-8111-111111111111"
PHONE_17 = "22222222-2222-4222-8222-222222222222"
OTHER_RUNTIME = "33333333-3333-4333-8333-333333333333"


def select(devices, runtime="26.2"):
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "devices.json"
        path.write_text(json.dumps(devices), encoding="utf-8")
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path), "--runtime", runtime],
            capture_output=True,
            text=True,
            check=False,
        )


class SimulatorSelectionTests(unittest.TestCase):
    def test_selects_device_identifier_on_requested_runtime(self):
        result = select(
            {
                "devices": {
                    RUNTIME_26_2: [
                        {"name": "iPhone 16", "udid": PHONE_16, "isAvailable": True},
                        {"name": "iPhone 17 Pro", "udid": PHONE_17, "isAvailable": True},
                    ],
                    RUNTIME_26_4: [
                        {"name": "iPhone 17 Pro", "udid": OTHER_RUNTIME, "isAvailable": True}
                    ],
                }
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"{PHONE_17}\n")
        self.assertIn("iOS 26.2", result.stderr)

    def test_ignores_unavailable_non_phone_and_invalid_identifiers(self):
        result = select(
            {
                "devices": {
                    RUNTIME_26_2: [
                        {"name": "iPhone 18", "udid": PHONE_17, "isAvailable": False},
                        {"name": "iPad", "udid": OTHER_RUNTIME, "isAvailable": True},
                        {"name": "iPhone 19", "udid": "invalid", "isAvailable": True},
                        {"name": "iPhone 16", "udid": PHONE_16, "isAvailable": True},
                    ]
                }
            }
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, f"{PHONE_16}\n")

    def test_missing_runtime_fails_with_diagnostic(self):
        result = select({"devices": {RUNTIME_26_4: []}})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("No available iPhone simulator for iOS 26.2", result.stderr)

    def test_invalid_devices_json_fails_with_diagnostic(self):
        result = select({"devices": []})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")
        self.assertIn("does not contain a devices object", result.stderr)


if __name__ == "__main__":
    unittest.main()
