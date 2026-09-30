import importlib.util
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("lp_metadata", ROOT / "tools/lp_metadata.py")
lp = importlib.util.module_from_spec(spec)
assert spec.loader
sys.modules[spec.name] = lp
spec.loader.exec_module(lp)


class MetadataTests(unittest.TestCase):
    def setUp(self):
        self.text = (ROOT / "tests/fixtures/lpdump.txt").read_text()

    def test_parses_geometry_and_extent_sizes(self):
        value = lp.parse_lpdump(self.text)
        self.assertEqual(value.metadata_max_size, 65536)
        self.assertEqual(value.metadata_slot_count, 3)
        self.assertEqual(value.block_device_size, 8388608)
        self.assertEqual(value.groups, {"main_a": 3145728, "main_b": 3145728})
        self.assertEqual({p.name: p.size for p in value.partitions}, {
            "system_a": 1048576, "vendor_a": 262144, "system_b": 524288,
        })

    def test_command_contains_every_partition(self):
        metadata = lp.parse_lpdump(self.text)
        command = lp.make_command(metadata, Path("parts"), Path("super.img"))
        joined = " ".join(str(x) for x in command)
        self.assertIn("system_a:readonly:1048576:main_a", joined)
        self.assertIn("system_a=parts/system_a.img", joined)
        self.assertEqual(command[-2:], ["--output", "super.img"])

    def test_rejects_missing_extents(self):
        broken = self.text.replace("0 .. 511 linear super 6144", "none")
        with self.assertRaises(ValueError):
            lp.parse_lpdump(broken)


if __name__ == "__main__":
    unittest.main()
