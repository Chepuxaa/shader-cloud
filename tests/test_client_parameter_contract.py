"""Optional local comparison against the Lua client's shared parameter validator.

The standalone library needs no Lua dependency. In the client workspace install
lupa (or expose it through PYTHONPATH) to exercise these integration fixtures.
"""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
from build_manifests import descriptor, InvalidStyle, MAX_USER_SLOTS, SECTIONS, slot_count

try:
    from lupa import LuaRuntime
except ImportError:
    LuaRuntime = None

DEFAULT_HELPER = Path(__file__).resolve().parents[2] / "tools/cloud_parameter_contract.lua"
CLIENT_HELPER = Path(os.environ.get("CLOUD_PARAMETER_CONTRACT_LUA", str(DEFAULT_HELPER)))


def slider(**fields):
    result = dict(key="value", label="Value", type="slider", slot=1,
                  min=0, max=100, step=1, default=50)
    result.update(fields)
    return result


def binding(name, **fields):
    result = slider(key=name, binding=name, **fields)
    result.pop("slot")
    return result


def fixtures():
    color = dict(key="color", label="Color", type="color", slot=MAX_USER_SLOTS - 5,
                 default=[11, 22, 33])
    return [
        ("no slots", []),
        ("ordinary slider", [slider()]),
        ("negative raw boundary", [slider(min=-100000, max=0, default=-100000)]),
        ("positive raw boundary", [slider(max=100000, default=100000)]),
        ("negative raw overflow", [slider(min=-100001)]),
        ("positive raw overflow", [slider(max=100001)]),
        ("step raw overflow", [slider(min=-100000, max=100000, step=100001)]),
        ("boolean default", [slider(default=True)]),
        ("nonfinite default", [slider(default=float("nan"))]),
        ("positive scale boundary", [slider(scale=100000)]),
        ("negative scale boundary", [slider(scale=-100000)]),
        ("positive scale overflow", [slider(scale=100001)]),
        ("negative scale overflow", [slider(scale=-100001)]),
        ("zero scale", [slider(scale=0)]),
        ("nonfinite scale", [slider(scale=float("inf"))]),
        ("scaled positive endpoint boundary", [slider(max=10000, scale=100000)]),
        ("scaled negative endpoint boundary", [slider(min=-10000, max=0, default=0, scale=100000)]),
        ("scaled endpoints below boundary", [slider(min=-9999, max=9999, default=0, scale=100000)]),
        ("negative scale below boundary", [slider(min=-9999, max=9999, default=0, scale=-100000)]),
        ("speed scale boundary", [binding("speed", max=300, default=100, scale=100000)]),
        ("speed scale overflow", [binding("speed", scale=100001)]),
        ("radius ordinary range", [binding("radius", min=-100000, max=100000, default=42)]),
        ("opacity ordinary range", [binding("opacity", min=-100000, max=100000, default=1)]),
        ("radius raw overflow", [binding("radius", max=100001)]),
        ("opacity scaled overflow", [binding("opacity", max=10000, scale=100000)]),
        ("negative slot", [slider(slot=-1)]),
        ("maximum slot", [slider(slot=MAX_USER_SLOTS)]),
        ("excess slot", [slider(slot=MAX_USER_SLOTS + 1)]),
        ("large cross-vector color", [color]),
        ("large color overlap", [color, slider(slot=MAX_USER_SLOTS - 3)]),
        ("legacy reserved slot", [slider(slot=8)]),
        ("over sixteen controls", [slider(key=f"value_{i}", slot=i) for i in range(1, 18)]),
    ]


@unittest.skipUnless(LuaRuntime is not None and CLIENT_HELPER.is_file(),
                     "optional integration check requires lupa and the client parameter helper")
class ClientParameterContractTests(unittest.TestCase):
    def test_python_and_lua_agree_on_parameter_validation_and_inferred_counts(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        helper = lua.execute(CLIENT_HELPER.read_text(encoding="utf-8") + "\nreturn parameter_contract\n")

        def lua_value(value):
            if isinstance(value, dict):
                return lua.table_from({key: lua_value(item) for key, item in value.items()})
            if isinstance(value, list):
                return lua.table_from([lua_value(item) for item in value])
            return value

        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "demo.json"
            for section in SECTIONS:
                reserved = list(range(8, 16)) if section == "weapons" else list(range(6, 16)) if section == "autopeek" else []
                config = lua_value(dict(section=section, reserved_slots=reserved))
                for contract in (1, 2):
                    for name, controls in fixtures():
                        with self.subTest(section=section, contract=contract, fixture=name):
                            d = dict(contract=contract, id="demo", name="Demo", author="Codex", controls=copy.deepcopy(controls))
                            path.write_text(json.dumps(d), encoding="utf-8")
                            try:
                                validated = descriptor(path, section)
                                python_valid = True
                            except InvalidStyle:
                                python_valid = False
                            lua_d = lua_value(d)
                            self.assertEqual(python_valid, bool(helper.valid(lua_d, "demo", config)))
                            if python_valid:
                                self.assertEqual(slot_count(validated), helper.count(lua_d))


if __name__ == "__main__":
    unittest.main()
