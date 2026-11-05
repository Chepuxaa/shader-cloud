import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from build_manifests import descriptor, generate, InvalidStyle, MAX_USER_SLOTS, SECTIONS, slot_count


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

    def slider(self, key="value", slot=1, **fields):
        control = dict(key=key, label=key, type="slider", slot=slot,
                       min=0, max=100, step=1, default=50)
        control.update(fields)
        return control

    def binding(self, binding, **fields):
        control = self.slider(binding, binding=binding, **fields)
        control.pop("slot")
        return control

    def validated(self, section="skybox", contract=2, **fields):
        return descriptor(self.style(section=section, contract=contract, **fields), section)

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

    def test_dynamic_slot_count_is_maximum_endpoint_including_gaps(self):
        for controls, expected in (([], 0), ([self.binding("speed")], 0),
                                   ([self.slider(slot=18)], 18),
                                   ([self.slider(slot=30), self.slider("first", 1)], 30)):
            with self.subTest(expected=expected):
                self.assertEqual(slot_count(self.validated(controls=controls)), expected)

    def test_dynamic_colors_cross_legacy_boundary_and_reuse_reserved_slots(self):
        color = dict(key="tint", label="Tint", type="color", slot=15, default=[1, 2, 3])
        for section in SECTIONS:
            with self.subTest(section=section):
                d = self.validated(section=section, controls=[color, self.slider(slot=8)])
                self.assertEqual(slot_count(d), 17)

    def test_dynamic_hardware_slot_boundary(self):
        self.assertEqual(slot_count(self.validated(controls=[self.slider(slot=MAX_USER_SLOTS)])), MAX_USER_SLOTS)
        color = dict(key="tint", label="Tint", type="color", slot=MAX_USER_SLOTS - 2, default=[1, 2, 3])
        self.assertEqual(slot_count(self.validated(controls=[color])), MAX_USER_SLOTS)
        for slot in (0, -1, True, 1.5, MAX_USER_SLOTS + 1):
            with self.subTest(slot=slot):
                with self.assertRaisesRegex(InvalidStyle, "invalid slot"):
                    self.validated(controls=[self.slider(slot=slot)])
        color["slot"] += 1
        with self.assertRaisesRegex(InvalidStyle, "invalid slot"):
            self.validated(controls=[color])

    def test_dynamic_colors_cross_float4_vectors_near_hardware_boundary(self):
        # 16363..16365 straddles vectors; 16366..16368 is adjacent and valid.
        crossing = dict(key="crossing", label="Crossing", type="color",
                        slot=MAX_USER_SLOTS - 5, default=[11, 22, 33])
        last = dict(key="last", label="Last", type="color",
                    slot=MAX_USER_SLOTS - 2, default=[44, 55, 66])
        for section in SECTIONS:
            with self.subTest(section=section):
                self.assertEqual(slot_count(self.validated(section=section, controls=[crossing, last])),
                                 MAX_USER_SLOTS)
                with self.assertRaisesRegex(InvalidStyle, "overlapping"):
                    self.validated(section=section, controls=[crossing, dict(last, slot=MAX_USER_SLOTS - 3)])

    def test_dynamic_overlaps_include_entire_color_width(self):
        color = dict(key="tint", label="Tint", type="color", slot=15, default=[1, 2, 3])
        for slot in (15, 16, 17):
            with self.subTest(slot=slot):
                with self.assertRaisesRegex(InvalidStyle, "overlapping"):
                    self.validated(controls=[color, self.slider(slot=slot)])
        self.assertEqual(slot_count(self.validated(controls=[color, self.slider(slot=18)])), 18)

    def test_dynamic_more_than_sixteen_controls_and_natural_json_limit(self):
        controls = [self.slider(f"value_{i}", i) for i in range(1, 31)]
        self.assertEqual(slot_count(self.validated(controls=controls)), 30)
        path = self.style(contract=2, controls=controls)
        path.write_bytes(path.read_bytes() + b" " * 32768)
        with self.assertRaisesRegex(InvalidStyle, "32768"):
            descriptor(path, "skybox")

    def test_control_numbers_and_scale_match_client_magnitude_limit(self):
        for contract in (1, 2):
            with self.subTest(contract=contract):
                self.validated(contract=contract, controls=[self.slider(min=-100000, max=100000, default=0, step=100000)])
                for control in (self.slider(min=-100001), self.slider(max=100001),
                                self.slider(min=-100000, max=100000, step=100001),
                                self.slider(scale=100001), self.slider(scale=-100001),
                                self.slider(scale=0)):
                    with self.subTest(control=control):
                        with self.assertRaises(InvalidStyle):
                            self.validated(contract=contract, controls=[control])
                for scale in (-100000, 100000):
                    self.validated(contract=contract, controls=[self.slider(scale=scale)])

    def test_scaled_slider_range_stays_strictly_below_native_magnitude_limit(self):
        for contract in (1, 2):
            for scale in (-100000, 100000):
                with self.subTest(contract=contract, scale=scale):
                    for lower, upper in ((0, 10000), (-10000, 0)):
                        with self.assertRaisesRegex(InvalidStyle, "scaled slider range"):
                            self.validated(contract=contract, controls=[self.slider(min=lower, max=upper, default=0, scale=scale)])
                    self.validated(contract=contract, controls=[self.slider(min=-9999, max=9999, default=0, scale=scale)])

    def test_speed_uses_unscaled_percentage_but_scale_still_must_be_valid(self):
        for contract in (1, 2):
            self.validated(contract=contract, controls=[self.binding("speed", max=300, default=100, scale=100000)])
            with self.assertRaisesRegex(InvalidStyle, "invalid scale"):
                self.validated(contract=contract, controls=[self.binding("speed", scale=100001)])

    def test_legacy_slots_and_control_limit_are_unchanged(self):
        for section, slot in (("skybox", 16), ("weapons", 8), ("autopeek", 6)):
            with self.subTest(section=section):
                with self.assertRaises(InvalidStyle):
                    self.validated(section=section, contract=1, controls=[self.slider(slot=slot)])
        color = dict(key="tint", label="Tint", type="color", slot=14, default=[1, 2, 3])
        with self.assertRaisesRegex(InvalidStyle, "invalid slot"):
            self.validated(contract=1, controls=[color])
        color["slot"] = 13
        self.assertEqual(slot_count(self.validated(contract=1, controls=[color])), 15)
        with self.assertRaisesRegex(InvalidStyle, "at most 16"):
            self.validated(contract=1, controls=[self.slider(f"v_{i}", i) for i in range(1, 18)])

    def test_dynamic_engine_bindings_are_slotless_unique_sliders(self):
        controls = [self.binding("speed", max=300, default=100),
                    self.binding("radius", min=8, max=128, default=42),
                    self.binding("opacity", min=0, max=1, step=.01, default=1)]
        self.assertEqual(slot_count(self.validated(section="autopeek", controls=controls)), 0)
        for control in (dict(controls[0], slot=1), dict(controls[1], slot=1),
                        dict(controls[2], slot=1), self.binding("unknown"),
                        self.binding("speed", max=301), self.binding("speed", min=-1),
                        dict(controls[0], type="checkbox", default=True),
                        dict(controls[0], binding=True)):
            with self.subTest(control=control):
                with self.assertRaisesRegex(InvalidStyle, "binding"):
                    self.validated(section="autopeek", controls=[control])
        for binding in controls:
            with self.subTest(duplicate=binding["binding"]):
                with self.assertRaisesRegex(InvalidStyle, "binding"):
                    self.validated(section="autopeek", controls=[binding, dict(binding, key="other")])

    def test_radius_and_opacity_bindings_only_belong_to_dynamic_autopeek(self):
        for section, contract in (("skybox", 1), ("weapons", 1), ("autopeek", 1),
                                  ("skybox", 2), ("weapons", 2)):
            for binding in ("radius", "opacity"):
                with self.subTest(section=section, contract=contract, binding=binding):
                    with self.assertRaisesRegex(InvalidStyle, "binding"):
                        self.validated(section=section, contract=contract, controls=[self.binding(binding)])
        for section in SECTIONS:
            for contract in (1, 2):
                self.validated(section=section, contract=contract, controls=[self.binding("speed")])

    def test_mixed_contracts_generate_same_catalog_without_descriptor_changes(self):
        old = self.style("legacy", contract=1)
        new = self.style("dynamic", contract=2, controls=[self.slider(slot=30)])
        descriptors = {p: p.read_bytes() for p in (old, new)}
        generate(self.root)
        manifest = self.root / "skybox/manifest.json"
        before = manifest.read_bytes()
        self.assertEqual(json.loads(before)["contract"], 1)
        self.assertEqual(self.entries(), [dict(id="dynamic", name="Demo", author="kissd"),
                                         dict(id="legacy", name="Demo", author="kissd")])
        self.assertEqual(generate(self.root), [])
        self.assertEqual(generate(self.root, check=True), [])
        self.assertEqual(manifest.read_bytes(), before)
        for path, data in descriptors.items():
            self.assertEqual(path.read_bytes(), data)

    def test_upgrading_descriptor_contract_keeps_manifest_bytes_identical(self):
        self.style()
        generate(self.root)
        manifest = self.root / "skybox/manifest.json"
        before = manifest.read_bytes()
        self.style(contract=2, controls=[self.slider(slot=30)])
        self.assertEqual(generate(self.root), [])
        self.assertEqual(manifest.read_bytes(), before)

    def test_invalid_dynamic_descriptor_preserves_all_existing_manifests(self):
        self.style()
        generate(self.root)
        before = {s: (self.root / s / "manifest.json").read_bytes() for s in SECTIONS}
        self.style("new", contract=2, controls=[self.slider(slot=30)])
        self.style("bad", section="autopeek", contract=2,
                   controls=[self.slider(slot=MAX_USER_SLOTS + 1)])
        with self.assertRaisesRegex(InvalidStyle, "invalid slot"):
            generate(self.root)
        for section, data in before.items():
            self.assertEqual((self.root / section / "manifest.json").read_bytes(), data)

    def test_authoring_examples_infer_18_and_30_without_entering_live_catalog(self):
        repository = Path(__file__).resolve().parents[1]
        for count in (18, 30):
            path = repository / "examples/autopeek" / f"three_color_{count}.json"
            with self.subTest(count=count):
                d = descriptor(path, "autopeek")
                self.assertEqual(d["contract"], 2)
                self.assertEqual(slot_count(d), count)
                self.assertEqual(sum(c["type"] == "color" for c in d["controls"]), 3)
                self.assertEqual({c["binding"] for c in d["controls"] if "binding" in c},
                                 {"radius", "opacity", "speed"})
                self.assertIn("SV_Target", path.with_suffix(".hlsl").read_text())
                self.assertFalse((repository / "autopeek/styles" / path.name).exists())


if __name__ == "__main__":
    unittest.main()
