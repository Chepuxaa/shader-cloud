import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from build_manifests import generate, InvalidStyle, SECTIONS


class ManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for section in SECTIONS:
            (self.root / section / "styles").mkdir(parents=True)

    def style(self, identifier="demo", section="skybox", **fields):
        d = dict(contract=1, id=identifier, name="Demo", author="kissd", controls=[])
        d.update(fields)
        path = self.root / section / "styles" / f"{identifier}.json"
        path.write_text(json.dumps(d), encoding="utf-8")
        path.with_suffix(".hlsl").write_text("float4 main():SV_Target{return 1;}", encoding="utf-8")
        return path

    def entries(self, section="skybox"):
        return json.loads((self.root / section / "manifest.json").read_text())["effects"]

    def test_add_edit_delete_and_stable_order(self):
        self.style("zebra", order=10)
        p = self.style("alpha", order=20, name="Alpha", author="Codex")
        self.style("beta", order=20)
        generate(self.root)
        self.assertEqual([e["id"] for e in self.entries()], ["zebra", "alpha", "beta"])
        self.assertEqual(self.entries()[1], dict(id="alpha", name="Alpha", author="Codex"))
        self.assertEqual(generate(self.root), [])
        self.style("alpha", order=20, name="Renamed", author="Another author")
        generate(self.root)
        self.assertEqual(self.entries()[1]["author"], "Another author")
        p.unlink()
        p.with_suffix(".hlsl").unlink()
        generate(self.root)
        self.assertEqual([e["id"] for e in self.entries()], ["zebra", "beta"])

    def test_check_is_read_only(self):
        self.style()
        with self.assertRaises(InvalidStyle):
            generate(self.root, check=True)
        self.assertFalse((self.root / "skybox/manifest.json").exists())
        generate(self.root)
        self.assertEqual(generate(self.root, check=True), [])

    def test_invalid_other_section_preserves_every_manifest(self):
        self.style()
        generate(self.root)
        before = {s: (self.root / s / "manifest.json").read_bytes() for s in SECTIONS}
        self.style("new")
        self.style(section="autopeek", author="")
        with self.assertRaisesRegex(InvalidStyle, "author"):
            generate(self.root)
        for section, data in before.items():
            self.assertEqual((self.root / section / "manifest.json").read_bytes(), data)

    def test_missing_pair_rejected(self):
        path = self.style()
        path.with_suffix(".hlsl").unlink()
        with self.assertRaisesRegex(InvalidStyle, "unpaired"):
            generate(self.root)

    def test_bad_metadata_and_control_contracts_rejected(self):
        for fields in (dict(id="other"), dict(author="я" * 17), dict(name=""),
                       dict(order=True), dict(contract=True),
                       dict(controls=[dict(key="x", label="X", type="color", slot=7, default=[1, 2, 3])])):
            with self.subTest(fields=fields):
                self.style(section="weapons", **fields)
                with self.assertRaises(InvalidStyle):
                    generate(self.root)

    def test_duplicate_json_keys_and_nonfinite_numbers_rejected(self):
        path = self.style()
        for data in ('{"id":"a","id":"b"}', '{"order":NaN}'):
            path.write_text(data)
            with self.assertRaises(InvalidStyle):
                generate(self.root)

    def test_style_limits_and_source_restrictions(self):
        for i in range(25):
            self.style(f"style_{i}")
        with self.assertRaisesRegex(InvalidStyle, "24"):
            generate(self.root)
        for path in (self.root / "skybox/styles").iterdir():
            path.unlink()
        path = self.style()
        path.with_suffix(".hlsl").write_text('#include "external.hlsl"\nfloat4 main():SV_Target{return 1;}')
        with self.assertRaisesRegex(InvalidStyle, "includes"):
            generate(self.root)


if __name__ == "__main__":
    unittest.main()
