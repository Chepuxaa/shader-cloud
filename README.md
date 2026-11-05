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
files cannot load the new library. Contract 2 styles require clients with dynamic
parameter support. No Lua update is needed for later edits within a supported
shader/control contract.

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

Missing pairs, malformed JSON, duplicate keys, invalid controls, legacy reserved
slots, overlapping slots and file-size limits stop generation before any catalog is
changed. Source checks enforce the client's HLSL size/include rules; they do not
compile HLSL or prove its appearance in game. The Lua client still compiles the
chosen shader and keeps its current effect if compilation fails.

Local generation uses Python 3.10+ with no external dependencies:

```text
python -m unittest discover -s tests -v
python scripts/build_manifests.py
python scripts/build_manifests.py --check
```

Inside the client workspace, the test suite also compares parameter validation
against `tools/cloud_parameter_contract.lua` when the optional `lupa` package is
available. This integration comparison is skipped in a standalone library clone;
ordinary schema tests need no dependencies. `CLOUD_PARAMETER_CONTRACT_LUA` can
point to the helper when it lives elsewhere.

If repository or branch rules block the bot commit, the workflow reports a failed
publish. Generate locally and commit the catalogs, or grant the workflow access
under the repository's rules; it never force-pushes.

## Legacy Autopeek radius (contract 1)

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

Each descriptor has `contract: 1` or `contract: 2`, `id`, `name`, `author` and
`controls`. Existing published styles retain contract 1 and their original HLSL.
A control has a unique `key`, `label`, `type`, `default` and either a one-based
`slot` or an engine `binding`.

| Type | Additional fields | Value |
| --- | --- | --- |
| slider | min, max, step, optional scale | displayed value multiplied by scale |
| select | options | zero-based selected index |
| checkbox | boolean default | 0 or 1 |
| color | RGB default | three consecutive normalized floats |

`group` is `main` or `colors`. Slots must not overlap. Color uses three consecutive
slots. A slider's `scale` multiplies its displayed value before publication.
Select and checkbox values occupy one scalar each.
Slider numbers and optional scale must be finite with magnitude at most 100000;
scale must be nonzero. Scaled slider endpoints must have magnitude below 1e9.
Speed uses its unscaled percentage value.

| Descriptor | User slots | Controls | Engine bindings |
| --- | --- | --- | --- |
| Contract 1 Skybox | 1..15 | at most 16 | speed |
| Contract 1 Weapon | 1..7; 8..15 reserved | at most 16 | speed |
| Contract 1 Autopeek | 1..5; 6..15 reserved | at most 16 | speed |
| Contract 2, all sections | 1..16368; no reserved user slots | hardware bound of 16368; also limited by JSON size | speed; Autopeek also radius and opacity |

The catalog supports 24 effects per section. HLSL is limited to 64 KiB and JSON
to 32 KiB; external includes are rejected. The JSON byte limit normally bounds
the number of controls long before the hardware-derived control-array limit.

`binding: "speed"` is a unique slotless slider with range inside 0..300. Its
displayed value is a percentage: 100 means normal animation speed. Contract 2
Autopeek additionally accepts unique slotless sliders with `binding: "radius"`
and `binding: "opacity"`. With those bindings absent, physical radius is 42 world
units and opacity is 1. Radius and opacity values use the slider's optional
`scale`; they are engine inputs and do not occupy user slots. For example:

```json
[
  {"key":"radius","label":"Radius","type":"slider","binding":"radius","min":8,"max":128,"step":1,"default":42},
  {"key":"opacity","label":"Opacity","type":"slider","binding":"opacity","min":0,"max":100,"step":1,"default":100,"scale":0.01},
  {"key":"speed","label":"Speed","type":"slider","binding":"speed","min":0,"max":300,"step":1,"default":100}
]
```

Bindings cannot also declare a slot, use another control type, or appear twice.
Radius and opacity bindings are rejected in contract 1 and in other sections.
Their schema uses ordinary finite slider validation; at runtime the client
clamps physical radius to 8..128 world units and opacity to 0..1.

## Dynamic shader contract (contract 2)

Contract 2 derives its scalar count entirely from the JSON controls. Each scalar
uses one slot and each color uses three; the count is the greatest occupied
slot, or zero when no controls occupy slots. Gaps are allowed and contain zero.
For example, a scalar in slot 18 allocates 18 user floats; a color starting in
slot 28 allocates 30. Switching between those descriptors resizes storage
automatically. There is no author-maintained `slot_count` field and no 15-slot
restriction for contract 2.

The maximum is 16368 user floats, derived from DX11's 64 KiB constant-buffer
limit after reserving 16 frame floats. This is a technical upper bound, not
unlimited storage. A color can start no later than slot 16366. Storage is padded
to four floats, with at least one user `float4`; a zero-slot style therefore uses
an 80-byte buffer.

The client prepends a generated HLSL constant buffer at pixel-shader register
`b6`, followed by accessors. Do not declare another buffer at `b6` or redefine
these names in contract 2 HLSL:

| Generated helper | Result |
| --- | --- |
| `SC_SLOT_COUNT` | compile-time inferred user scalar count |
| `SC_Get(uint slot)` | scalar in a one-based user slot; zero outside 1..count |
| `SC_Color(uint startSlot)` | three consecutive scalars as `float3` |
| `SC_Time()` | animation time, affected by the speed binding |
| `SC_Clock()` | frame clock |
| `SC_Opacity()` | engine opacity |
| `SC_ReleaseAge()` | Autopeek release age; -1 while active |
| `SC_FrameViewport()` | `float4(viewportX, viewportY, width, height)` |
| `SC_FrameCamera()` | `float4(pitch, yaw, roll, tanHalfVerticalFov)` |
| `SC_FrameAnchor()` | `float4(anchorX, anchorY, anchorZ, radius)` |

Camera angles use degrees. The vertical tangent is calibrated for Autopeek;
Skybox and Weapon supply the reference value 0.75 used by the legacy Weapon
projection. Weapon transparently remaps authored `b6` to its private `b7` slot.

The first frame `float4` contains time, clock, opacity and release age. The next
three contain viewport, camera and anchor respectively. User data starts after
these 16 frame scalars, so every user slot remains available in every section.
Shader input semantics and targets remain those of the corresponding section
below; the legacy `b6` layout applies only to contract 1.

Contract 2 Autopeek uses `i.col.rgb = float3(1,1,1)` and
`i.col.a = fade * opacity`. Read independent colors through `SC_Color`, and use
the radius binding for carrier geometry. User slots named `radius` or `opacity`
without a binding are ordinary shader parameters and do not change geometry or
engine opacity. Autopeek retains the packed UV position format in both contracts:
decode the local position as `(i.uv - floor(i.uv * 0.5) * 2) * 2 - 1`. Contract 2
shaders read animation time and release age through `SC_Time()` and
`SC_ReleaseAge()` instead of decoding them from UV offsets.

Authoring examples are in [`examples/autopeek`](examples/autopeek):
`three_color_18` and `three_color_30` each provide three independent colors,
controls beyond slot 15 and the three engine bindings. They infer 18 and 30 user
floats, respectively. These examples are outside the published `styles` folders
and do not add entries to the live catalog. Copy a JSON/HLSL pair into
`autopeek/styles` to publish it after testing in game.

All three manifests remain `contract: 1` and may list styles of either descriptor
version. Catalog generation emits the same ID/name/author entries for both.
Clients validate the chosen descriptor separately: an older client can continue
using contract 1 styles in a mixed catalog, and rejects an unsupported contract 2
style when selected while retaining its working effect.

## Legacy Skybox shader contract (contract 1)

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

## Legacy Weapon shader contract (contract 1)

Weapon targets `ps_5_0` and uses the same `b6` constant-buffer layout. Only
slots 1..7 are available to effect controls; slots 8..15 hold viewport origin,
viewport size, reference vertical projection tangent and camera angles.
Only `csgo_weapon.vfx_ps` is replaced. Hologram uses the existing local-position
`TEXCOORD8`; Galaxy uses pixel position and the camera projection. Do not add
vertex-input dependencies that the original draw does not supply.

## Autopeek shader inputs and legacy parameters

Autopeek targets `ps_4_0` and uses Fatality's GUI pixel-shader input:

```hlsl
cbuffer cb:register(b0) { float4x4 mvp; float2 tex; float time; float alpha; };
struct Input { float4 pos:SV_POSITION; float4 col:COLOR0; float2 uv:TEXCOORD0; };
```

In contract 1, slots 1..3 are RGB through `i.col.rgb`, slot 4 is the ground-plane
radius, and slot 5 is opacity through `i.col.a`. Slots 6..15 are reserved. Integer UV offsets
encode animation time and release age; use the included effects to decode them.
Ripples uses a 2.4-second wave lifecycle with emission offsets .25, 1.05 and 1.85.
Other styles can fade with the supplied release age.

Autopeek renders world geometry with the selected scene's hardware depth test.
The vertex shader owns `b1/b2` for its camera and geometry parameters. The scene
depth and viewport are selected at runtime; a separate viewmodel pass must not
replace them. Controlled-device checks cover several sample counts and formats;
in-game compatibility still needs testing.

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
