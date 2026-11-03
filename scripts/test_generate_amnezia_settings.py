import base64
from pathlib import Path
import stat
import tempfile
import unittest

from generate_amnezia_settings import build_settings, write_settings


class SettingsTests(unittest.TestCase):
    def test_generated_settings_fit_mobile_limits(self):
        for _ in range(100):
            values = dict(line.split(" = ", 1) for line in build_settings().splitlines())
            self.assertLessEqual(int(values["Jc"]), 32)
            self.assertGreater(int(values["Jmin"]), 0)
            self.assertLess(int(values["Jmin"]), int(values["Jmax"]))
            self.assertLessEqual(int(values["Jmax"]), 1280)
            self.assertNotEqual(int(values["S1"]) + 148, int(values["S2"]) + 92)
            self.assertTrue(all(12 <= int(values[f"S{i}"]) <= 128 for i in range(1, 5)))
            self.assertLessEqual(1280 + 80 + int(values["S4"]) + 32, 1500)
            ranges = sorted(tuple(map(int, values[f"H{i}"].split("-"))) for i in range(1, 5))
            self.assertTrue(all(low >= 5 and high <= 0xFFFFFFFF for low, high in ranges))
            self.assertTrue(all(ranges[i][1] < ranges[i + 1][0] for i in range(3)))
            self.assertEqual(len(base64.b64decode(values["HeaderProtectionKey"], validate=True)), 32)

    def test_independent_deployments_get_distinct_settings(self):
        self.assertNotEqual(build_settings(), build_settings())

    def test_private_file_and_no_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            destination = Path(directory) / "settings.conf"
            write_settings(destination)
            self.assertEqual(stat.S_IMODE(destination.stat().st_mode), 0o600)
            original = destination.read_bytes()
            with self.assertRaises(FileExistsError):
                write_settings(destination)
            self.assertEqual(destination.read_bytes(), original)

    def test_does_not_follow_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "target"
            target.write_text("unchanged")
            link = Path(directory) / "settings.conf"
            link.symlink_to(target)
            with self.assertRaises(FileExistsError):
                write_settings(link)
            self.assertEqual(target.read_text(), "unchanged")


if __name__ == "__main__":
    unittest.main()
