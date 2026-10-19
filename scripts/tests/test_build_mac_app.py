"""Exercise bundle-signing failures without compiling or launching the app."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "build-mac-app.sh"


class BundleSigningTests(unittest.TestCase):
    def run_bundle(self, *, signing_status=0, verification_status=0):
        with tempfile.TemporaryDirectory(prefix="kotoro bundle test ") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            shutil.copy2(SCRIPT, root / "scripts/build-mac-app.sh")
            binary = root / ".build/release/KotoroMac"
            binary.parent.mkdir(parents=True)
            binary.write_text("#!/bin/sh\nexit 0\n")
            binary.chmod(0o755)
            tools = root / "tools"
            tools.mkdir()
            for name in ("swift", "sips", "iconutil"):
                stub = tools / name
                stub.write_text("#!/bin/sh\nexit 0\n")
                stub.chmod(0o755)
            codesign = tools / "codesign"
            codesign.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$SIGNING_LOG"
case "$1" in
  --force)
    echo "fixture signing diagnostic" >&2
    exit "$SIGNING_STATUS"
    ;;
  --verify)
    echo "fixture verification diagnostic" >&2
    exit "$VERIFICATION_STATUS"
    ;;
  *) exit 99 ;;
esac
''')
            codesign.chmod(0o755)
            log = root / "signing.log"
            env = {
                **os.environ,
                "PATH": str(tools) + os.pathsep + os.environ["PATH"],
                "SIGNING_LOG": str(log),
                "SIGNING_STATUS": str(signing_status),
                "VERIFICATION_STATUS": str(verification_status),
            }
            result = subprocess.run(
                ["bash", str(root / "scripts/build-mac-app.sh"), "release"],
                env=env, capture_output=True, text=True, timeout=15,
            )
            return result, log.read_text().splitlines()

    def test_signing_failure_stops_before_verification_and_success(self):
        result, calls = self.run_bundle(signing_status=17)
        self.assertEqual(result.returncode, 17)
        self.assertNotIn("\nbuilt ", result.stdout)
        self.assertIn("fixture signing diagnostic", result.stderr)
        self.assertEqual(len(calls), 1)

    def test_verification_failure_is_not_reported_as_success(self):
        result, calls = self.run_bundle(verification_status=23)
        self.assertEqual(result.returncode, 23)
        self.assertNotIn("\nbuilt ", result.stdout)
        self.assertIn("fixture verification diagnostic", result.stderr)
        self.assertEqual(len(calls), 2)

    def test_success_requires_signing_then_strict_bundle_verification(self):
        result, calls = self.run_bundle()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("\nbuilt ", result.stdout)
        self.assertEqual(len(calls), 2)
        self.assertTrue(calls[0].startswith("--force --deep --sign - "))
        self.assertTrue(calls[1].startswith("--verify --deep --strict "))
        self.assertEqual(calls[0].split("--sign - ", 1)[1], calls[1].split("--strict ", 1)[1])


if __name__ == "__main__":
    unittest.main()
