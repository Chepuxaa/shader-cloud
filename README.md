# Shaders cloud library

HLSL effects and declarative controls for three independent Fatality Lua clients.
The Lua clients and native bridges are not distributed by this repository.

| Client | Catalog | Style files |
| --- | --- | --- |
| Skybox | `skybox/manifest.json` | `skybox/styles/<id>.json` and `.hlsl` |
| Weapon | `weapons/manifest.json` | `weapons/styles/<id>.json` and `.hlsl` |
| Autopeek | `autopeek/manifest.json` | `autopeek/styles/<id>.json` and `.hlsl` |

Every style has exactly one JSON and one HLSL file. Edit those files in place.
There are no numbered style files or per-effect revisions. Git history retains
previous contents if a rollback is needed.

## Editing and refreshing

For example, edit `autopeek/styles/glass.json` to change its controls or
`autopeek/styles/glass.hlsl` to change its appearance. Commit the replacement,
then press **Refresh library** in Autopeek. No manifest edit is needed when
updating an existing style.

Refresh downloads the catalog and current style again, and marks other cached
styles for a fresh download when selected. Every HTTP request has a cache-busting
query. Working effects remain active if downloading, validation or compilation
fails. Cached files remain available without HTTP; compatible user settings are
preserved when controls refresh. Changed control types use their new defaults.

Use the updated Lua clients for this layout. Older clients that require numbered
files cannot load the new library. No Lua update is needed for later style edits
that remain within the existing shader/control contract.

To add a style, create `<id>.json` and `<id>.hlsl` in the appropriate `styles`
directory. Set the name and author in the style JSON:

```json
{
  "contract": 1,
  "id": "example",
  "name": "My effect",
  "author": "Your name",
  "order": 50,
  "controls": []
}
```

The author appears as **My effect (by Your name)** and is searchable. IDs are
lowercase letters, digits, underscores and hyphens; the ID must match both
filenames. Name and author support up to 48 and 32 UTF-8 bytes respectively.
Optional `order` controls list position (lower first, default 1000); equal values
are sorted by ID. Existing style order is preserved.

### Automatic catalogs

Do not edit `manifest.json` manually. After a push to `main`, the **Build style
manifests** GitHub Actions workflow validates all three libraries and commits
updated manifests as `github-actions[bot]`. No separate token or secret is needed.
Once the workflow finishes, press **Refresh library** in the Lua menu.

Changing a JSON name/author updates its list entry. Deleting both style files
removes the entry. Pull requests are validated without writing to the repository;
catalogs are published after merge. The Actions page also offers **Run workflow**
on `main` to rebuild manually.

Missing pairs, malformed JSON, duplicate keys, invalid controls, reserved or
overlapping slots and file-size limits stop generation before any catalog is
changed. Source checks enforce the client's HLSL size/include rules; they do not
compile HLSL or prove its appearance in game. The Lua client still compiles the
chosen shader and keeps its current effect if compilation fails.

Local generation uses Python 3.10+ with no external dependencies:

```text
python -m unittest discover -s tests -v
python scripts/build_manifests.py
python scripts/build_manifests.py --check
```

If repository or branch rules block the bot commit, the workflow reports a failed
publish. Generate locally and commit the catalogs, or grant the workflow access
under the repository's rules; it never force-pushes.

## Autopeek radius

Radius starts at **50%**. In the radius control of each style's JSON, keep
`default` at 50 and set `scale` to the desired world radius divided by 50:

```json
{
  "key": "radius", "label": "Radius", "type": "slider", "slot": 4,
  "min": 10, "max": 100, "step": 1, "default": 50, "scale": 0.84
}
```

| Scale | Radius at 50% |
| --- | ---: |
| 0.60 | 30 |
| 0.84 | 42 |
| 1.00 | 50 |

At 100%, the radius doubles. The client clamps physical radius to 8..128 world
units. Each style can draw a different proportion inside that carrier. Updating
`scale` changes size while preserving the user's percentage setting.

Autopeek styles: **Ripples** (polygon ring and trailing waves), **Glass** (thin
circular rim and blurred scene), **Radial** (soft center glow), and **Halo**
(by Codex: thin contour, orbiting highlights and a restrained inner pulse).

## Control schema

Each descriptor has `contract: 1`, `id`, `name`, `author` and `controls`. See the included
JSON files for complete examples. A control has a unique `key`, `label`, `type`,
`default` and either a `slot` or the special `binding: "speed"`.

| Type | Additional fields | Value |
| --- | --- | --- |
| slider | min, max, step, optional scale | displayed value multiplied by scale |
| select | options | zero-based selected index |
| checkbox | boolean default | 0 or 1 |
| color | RGB default | three consecutive normalized floats |

`group` is `main` or `colors`. Slots must not overlap. Color uses three slots.
`binding: "speed"` has no slot and controls animation time; 100 means normal
speed. The catalog supports 24 effects and each descriptor supports 16 controls.
HLSL is limited to 64 KiB, JSON to 32 KiB; external includes are rejected.

## Skybox shader contract

Skybox targets `ps_5_0`, receives the world-facing direction in `TEXCOORD0`,
and uses a 64-byte constant buffer at `b6`:

```hlsl
cbuffer Custom : register(b6) {
    float4 c_params;
    float4 c_low;
    float4 c_high;
    float4 c_glow;
};
struct ps_in { float3 dir:TEXCOORD0; float4 position:SV_Position; };
float4 main(ps_in i):SV_Target0 { return float4(c_low.rgb,1); }
```

`c_params.x` is animation time; the remaining 15 floats are slots 1..15.
A Static selector must ignore animation time in HLSL. Included styles are
Lines, Galaxy, Retro and Portal; Gradient is embedded in the client.

## Weapon shader contract

Weapon targets `ps_5_0` and uses the same `b6` constant-buffer layout. Only
slots 1..7 are available to effect controls; slots 8..15 hold viewport origin,
viewport size, reference vertical projection tangent and camera angles.
Only `csgo_weapon.vfx_ps` is replaced. Hologram uses the existing local-position
`TEXCOORD8`; Galaxy uses pixel position and the camera projection. Do not add
vertex-input dependencies that the original draw does not supply.

## Autopeek shader contract

Autopeek targets `ps_4_0` and uses Fatality's GUI pixel-shader input:

```hlsl
cbuffer cb:register(b0) { float4x4 mvp; float2 tex; float time; float alpha; };
struct Input { float4 pos:SV_POSITION; float4 col:COLOR0; float2 uv:TEXCOORD0; };
```

Slots 1..3 are RGB through `i.col.rgb`, slot 4 is the ground-plane radius, slot
5 is opacity through `i.col.a`. Slots 6..15 are reserved. Integer UV offsets
encode animation time and release age; use the included effects to decode them.
Ripples uses a 2.4-second wave lifecycle with emission offsets .25, 1.05 and 1.85.
Other styles can fade with the supplied release age.

The client wraps Autopeek HLSL for scene-depth occlusion. Leave `t1` and `b1/b2`
free. The observed world depth range is 0..0.95; the separate viewmodel range
must not replace it. The current depth path targets D24 MSAA x4.

An optional `capture_background: true` descriptor binds the shared scene texture
at `t0` with sampler `s0`. Glass uses screen-position UVs for blur. The shared
image may include HUD already rendered at capture time; depth masking alone
does not resolve that interaction.

## Permissions and development

Clients require FFI and HTTP. Filesystem permission is optional for offline
caching. Use one client per category; each owns its own tab. Tools are developer
build/check helpers and are not required by users. Existing native bridges are
embedded in the standalone Lua files; style files never execute Lua or native
modules.

Offline checks from the client workspace:

```text
python tools/check_cloud_refresh.py
python tools/check_sky_cloud.py
python tools/check_cloud_assets.py
python tools/check_shader_menus.py
python tools/check_autopeek_cloud.py
python tools/check_autopeek_mask_client.py
```

Checks do not attach to CS2. Actual appearance still needs validation in Fatality.
Marketplace approval and compatibility with future game updates are not promised.
