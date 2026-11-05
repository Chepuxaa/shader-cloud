"""Validate style files and generate the catalogs consumed by the Lua clients."""
import argparse
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile


SECTIONS = ("skybox", "weapons", "autopeek")
ROOT = Path(__file__).resolve().parents[1]
ID = re.compile(r"[a-z][a-z0-9_-]{0,39}\Z")
MAX_USER_SLOTS = 16368  # 64 KiB DX11 constant buffer minus 16 frame floats.
MAX_JSON_BYTES = 32768
MAX_CONTROL_NUMBER = 100000
MAX_PUBLISHED_MAGNITUDE = 1e9


class InvalidStyle(ValueError):
    pass


def require(condition, message):
    if not condition:
        raise InvalidStyle(message)


def text(value, limit):
    return (isinstance(value, str) and bool(value.strip())
            and len(value.encode("utf-8")) <= limit
            and not any(ord(c) < 32 for c in value))


def number(value):
    return (type(value) in (int, float) and abs(value) <= MAX_CONTROL_NUMBER
            and math.isfinite(value))


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def invalid_constant(value):
    raise InvalidStyle(f"invalid JSON number: {value}")


def slot_count(d):
    """Infer scalar storage from controls; engine bindings consume no slots."""
    return max((c["slot"] + (3 if c["type"] == "color" else 1) - 1
                for c in d["controls"] if "slot" in c), default=0)


def descriptor(path, section):
    require(not path.is_symlink(), "style symlinks are not supported")
    data = path.read_bytes()
    require(0 < len(data) <= MAX_JSON_BYTES, "JSON must be 1..32768 bytes")
    d = json.loads(data.decode("utf-8"), object_pairs_hook=unique_object,
                   parse_constant=invalid_constant)
    require(isinstance(d, dict), "descriptor must be an object")
    require(type(d.get("contract")) is int and d["contract"] == 2, "style contract must be 2")
    require(d.get("id") == path.stem and ID.fullmatch(path.stem), "id must match the filename and use lowercase letters, digits, _ or -")
    require(text(d.get("name"), 48), "name must be 1..48 UTF-8 bytes")
    require(text(d.get("author"), 32), "author must be 1..32 UTF-8 bytes")
    require(type(d.get("order", 1000)) is int, "order must be an integer")
    require("capture_background" not in d or type(d["capture_background"]) is bool,
            "capture_background must be boolean")
    controls = d.get("controls")
    max_controls = MAX_USER_SLOTS
    require(isinstance(controls, list) and len(controls) <= max_controls,
            f"controls must be an array of at most {max_controls} items")
    used = set()
    keys, bindings = set(), set()
    for c in controls:
        require(isinstance(c, dict), "control must be an object")
        key = c.get("key")
        require(isinstance(key, str) and ID.fullmatch(key) and key not in keys, "control keys must be valid and unique")
        keys.add(key)
        require(text(c.get("label"), 48), f"{key}: invalid label")
        require(c.get("group", "main") in ("main", "colors"), f"{key}: invalid group")
        require("scale" not in c or (number(c["scale"]) and c["scale"] != 0), f"{key}: invalid scale")
        kind, value, width = c.get("type"), c.get("default"), 1
        if kind == "slider":
            require(all(number(c.get(k)) for k in ("min", "max", "step", "default")), f"{key}: invalid slider numbers")
            require(c["min"] < c["max"] and c["min"] <= value <= c["max"]
                    and 0 < c["step"] <= c["max"] - c["min"], f"{key}: invalid slider range")
            if c.get("binding") != "speed":
                scale = c.get("scale", 1)
                require(max(abs(c["min"] * scale), abs(c["max"] * scale)) < MAX_PUBLISHED_MAGNITUDE,
                        f"{key}: scaled slider range must have magnitude below 1e9")
        elif kind == "select":
            options = c.get("options")
            require(isinstance(options, list) and 1 <= len(options) <= 16
                    and all(text(v, 32) for v in options), f"{key}: invalid options")
            require(type(value) is int and 0 <= value < len(options), f"{key}: invalid selected index")
        elif kind == "checkbox":
            require(type(value) is bool, f"{key}: default must be boolean")
        elif kind == "color":
            width = 3
            require(isinstance(value, list) and len(value) == 3
                    and all(type(v) is int and 0 <= v <= 255 for v in value), f"{key}: invalid RGB color")
        else:
            raise InvalidStyle(f"{key}: unsupported control type")
        if "binding" in c:
            binding = c["binding"]
            allowed = ("speed", "radius", "opacity") if section == "autopeek" else ("speed",)
            require(isinstance(binding, str) and binding in allowed,
                    f"{key}: unsupported binding")
            require(binding not in bindings and kind == "slider" and "slot" not in c,
                    f"{key}: invalid {binding} binding")
            if binding == "speed":
                require(c["min"] >= 0 and c["max"] <= 300, f"{key}: invalid speed binding")
            bindings.add(binding)
        else:
            slot = c.get("slot")
            maximum = MAX_USER_SLOTS
            require(type(slot) is int and 1 <= slot <= maximum - width + 1,
                    f"{key}: invalid slot")
            slots = set(range(slot, slot + width))
            require(not used.intersection(slots), f"{key}: overlapping slots")
            used.update(slots)
    return d


def catalog(root, section):
    folder = root / section / "styles"
    require(folder.is_dir() and not folder.is_symlink(), f"{section}: styles directory is missing")
    files = [p for p in folder.iterdir() if p.suffix.lower() in (".json", ".hlsl")]
    require(all(p.is_file() and not p.is_symlink() and p.suffix in (".json", ".hlsl") for p in files),
            f"{section}: styles must be regular lowercase .json/.hlsl files")
    json_ids = {p.stem for p in files if p.suffix == ".json"}
    hlsl_ids = {p.stem for p in files if p.suffix == ".hlsl"}
    require(json_ids == hlsl_ids, f"{section}: unpaired style files: {', '.join(sorted(json_ids ^ hlsl_ids))}")
    require(len(json_ids) <= 24, f"{section}: client supports at most 24 styles")
    entries = []
    for identifier in sorted(json_ids):
        path = folder / f"{identifier}.json"
        try:
            d = descriptor(path, section)
            source = path.with_suffix(".hlsl").read_bytes()
            require(0 < len(source) <= 65536 and b"\0" not in source, "HLSL must be 1..65536 bytes without NUL")
            source = source.decode("utf-8")
            require(not re.search(r"#\s*include", source) and "SV_Target" in source,
                    "HLSL must declare SV_Target and cannot use includes")
        except (ValueError, UnicodeError, OSError) as error:
            raise InvalidStyle(f"{path.relative_to(root)}: {error}") from error
        entries.append(d)
    entries.sort(key=lambda d: (d.get("order", 1000), d["id"]))
    return {"contract": 1, "effects": [{k: d[k] for k in ("id", "name", "author")} for d in entries]}


def generate(root=ROOT, check=False):
    # Validate all sections before changing any existing catalog.
    outputs = {root / section / "manifest.json": (json.dumps(catalog(root, section), ensure_ascii=False, indent=2) + "\n").encode("utf-8")
               for section in SECTIONS}
    changed = [p for p, data in outputs.items() if not p.exists() or p.read_bytes() != data]
    if check:
        require(not changed, "manifests need regeneration: " + ", ".join(str(p.relative_to(root)) for p in changed))
        return []
    for path in changed:
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix=".manifest-", delete=False) as stream:
                temporary = Path(stream.name)
                stream.write(outputs[path])
            os.replace(temporary, path)
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true", help="validate without writing; fail if catalogs are stale")
    args = parser.parse_args()
    try:
        changed = generate(args.root.resolve(), args.check)
    except (ValueError, UnicodeError, OSError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("Updated: " + ", ".join(str(p.relative_to(args.root.resolve())) for p in changed)
          if changed else "Style files valid; all manifests up to date.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
